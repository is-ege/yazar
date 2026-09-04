import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class Yazar {
    enum State: Hashable {
        case idle
        case warmingUp
        case recording
        case transcribing
        case noSpeech
        case error(DictationFailure)
    }

    // Escape capture follows the cancellable states so every path that finishes
    // or abandons a dictation releases the global key.
    private(set) var state: State = .idle {
        didSet {
            switch state {
            case .warmingUp, .recording, .transcribing:
                escapeHotKey.capture(true)
            case .idle, .noSpeech, .error:
                escapeHotKey.capture(false)
            }
        }
    }
    /// Whether the hot key is live. Starting can fail when Accessibility is
    /// missing, so the permissions screen reads this rather than assuming a
    /// granted permission means Yazar is listening.
    private(set) var isListening = false
    private(set) var level = 0.0
    private(set) var recordingStartedAt: Date?

    private let settings: Settings
    private let hotKey = HotKey()
    private let escapeHotKey = EscapeHotKey()
    private let recorder = Recorder()
    private let soundPlayer = StatusSoundPlayer()
    private let textContextCapture = TextContextCapture()
    /// Set while the settings screen is recording a new trigger, so pressing keys
    /// to choose one does not start a dictation.
    var ignoresTrigger = false
    private var triggerHeld = false
    private var transcriptionTask: Task<Void, Never>?
    private var stateResetTask: Task<Void, Never>?
    private var recorderPollingTask: Task<Void, Never>?

    init(settings: Settings) {
        self.settings = settings
        hotKey.onModifiersChanged = { [weak self] held in self?.modifiersChanged(held) }
        escapeHotKey.onPress = { [weak self] in self?.cancel() }
    }

    func start() throws(HotKeyError) {
        try hotKey.start()
        isListening = true
    }

    func stop() {
        hotKey.stop()
        escapeHotKey.stop()
        isListening = false
        transcriptionTask?.cancel()
        stateResetTask?.cancel()
        recorderPollingTask?.cancel()
        textContextCapture.cancel()
        recorder.shutDown()
    }

    func show(_ failure: DictationFailure) {
        fail(failure)
    }

#if DEBUG
    func triggerDemoError() {
        play(.error)
        fail(.transcription("This is a demo error from Yazar."))
    }
#endif

    /// The trigger is whatever combination the user chose, matched exactly, so an
    /// unrelated modifier pressed on top of it reads as a release.
    private func modifiersChanged(_ held: Set<TriggerModifier>) {
        let isHeld = !ignoresTrigger && settings.dictationTrigger.isHeld(held)
        guard isHeld != triggerHeld else { return }
        triggerHeld = isHeld
        if isHeld {
            pressed()
        } else {
            released()
        }
    }

    private func pressed() {
        switch state {
        case .idle:
            break
        case .noSpeech, .error:
            stateResetTask?.cancel()
        case .warmingUp, .recording, .transcribing:
            return
        }

        recordingStartedAt = nil
        level = 0
        state = .warmingUp
        play(.start)
        textContextCapture.begin()
        do {
            try recorder.start(inputID: settings.audioInputID)
            startPollingRecorder()
        } catch {
            fail(.recorder(error))
        }
    }

    private func released() {
        switch state {
        case .warmingUp, .recording:
            break
        case .idle, .transcribing, .noSpeech, .error:
            return
        }

        finishRecording()
    }

    private func receivedFirstBuffer() {
        if state == .warmingUp {
            recordingStartedAt = Date()
            state = .recording
        } else if case .recording = state, recordingStartedAt == nil {
            recordingStartedAt = Date()
        }
    }

    /// Drives the meter, and is also what notices a microphone that never starts
    /// or stops part-way. Without it a device unplugged mid-hold just delivers no
    /// samples, and the empty recording fails the speech gate — so a hardware
    /// problem reads to the user as "No speech".
    private func startPollingRecorder() {
        recorderPollingTask?.cancel()
        recorderPollingTask = Task { [weak self] in
            // A reused session starts in ~100 ms and the first buffer follows
            // immediately; three seconds means it is not coming.
            let firstBufferDeadline = ContinuousClock.now + .seconds(3)
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = recorder.poll()
                level = snapshot.level
                if snapshot.receivedFirstBuffer {
                    receivedFirstBuffer()
                    guard snapshot.isCapturing else {
                        fail(.recorder(.captureInterrupted))
                        return
                    }
                } else if ContinuousClock.now >= firstBufferDeadline {
                    fail(.recorder(.microphoneUnavailable))
                    return
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func finishRecording() {
        recorderPollingTask?.cancel()
        let recording = recorder.stop()
        let insertionContext = textContextCapture.finish()
        // Prefer the focused element's application so formatting and fitting
        // describe the same target. Fall back to the workspace when
        // Accessibility cannot provide a context.
        let targetApplication = insertionContext?.applicationBundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let rules = settings.formatting.rules(for: targetApplication)
        let demoMode = isDemoMode
        play(.stop)
        recordingStartedAt = nil
        level = 0

        guard demoMode || recording.containsSpeech else {
            showNoSpeech()
            return
        }

        let route = settings.transcription.dictationRoute(for: KeyboardInputSource.current)
        let transcriber = settings.makeTranscriber(for: route)
        state = .transcribing
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            do {
                let text: String
#if DEBUG
                if demoMode {
                    try await Task.sleep(for: .seconds(2))
                    text = "This is a demo transcription from Yazar."
                } else {
                    text = try await transcriber.transcribe(recording)
                }
#else
                text = try await transcriber.transcribe(recording)
#endif
                try Task.checkCancellation()
                self?.deliver(text, rules: rules, context: insertionContext)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.play(.error)
                self?.fail(.transcription(error.localizedDescription))
            }
        }
    }

    /// Escape drops whatever is in flight. Only reachable while a dictation is
    /// running, since that is the only time the hot key is registered.
    private func cancel() {
        textContextCapture.cancel()
        switch state {
        case .warmingUp, .recording:
            recorderPollingTask?.cancel()
            recorder.cancel()
            recordingStartedAt = nil
            level = 0
            state = .idle
        case .transcribing:
            transcriptionTask?.cancel()
            transcriptionTask = nil
            play(.cancel)
            state = .idle
        case .idle, .noSpeech, .error:
            return
        }
    }

    private func fail(_ failure: DictationFailure) {
        textContextCapture.cancel()
        recorderPollingTask?.cancel()
        recorder.cancel()
        transcriptionTask?.cancel()
        state = .error(failure)
        resetState(after: .seconds(2.5))
    }

    /// Keep every transcription on the clipboard and attempt to paste it into the
    /// focused application. A provider that recognized nothing lands in the same
    /// place as audio that never cleared the speech gate.
    private func deliver(
        _ text: String,
        rules: Set<FormattingRule>,
        context: TextInsertionContext?
    ) {
        guard !text.isEmpty else {
            showNoSpeech()
            return
        }
        // The user's rules first, then the fit to the surrounding text: fitting
        // reconciles the final string with its neighbours, so nothing may run
        // after it.
        var textToPaste = TranscriptFormatter.apply(rules, to: text)
        if let context {
            textToPaste = TranscriptFitter.fit(textToPaste, to: context)
        }
        switch Inserter.insert(textToPaste) {
        case .delivered:
            state = .idle
        case .clipboardUnavailable:
            play(.error)
            fail(.clipboardUnavailable)
        }
    }

    private func showNoSpeech() {
        state = .noSpeech
        resetState(after: .seconds(1.2))
    }

    private func resetState(after delay: Duration) {
        let expectedState = state
        stateResetTask?.cancel()
        stateResetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            guard self?.state == expectedState else { return }
            self?.state = .idle
        }
    }

    private func play(_ status: StatusSound) {
        soundPlayer.play(status, theme: settings.soundTheme, enabled: settings.playSounds)
    }

    private var isDemoMode: Bool {
#if DEBUG
        settings.demoMode
#else
        false
#endif
    }

}
