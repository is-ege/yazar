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
        case retrying
        /// Something is retained and waiting on the user. Which offer that is —
        /// retry the audio, or copy the text — is `pendingDictation`'s to say.
        case recovery
        case copied
        case noSpeech
        case error(DictationFailure)
    }

    // Escape capture follows the cancellable states so every path that finishes
    // or abandons a dictation releases the global key.
    private(set) var state: State = .idle {
        didSet {
            // Any transition is fresh news, so a card the user hid stops hiding.
            // Only re-showing without a transition stays an explicit call.
            isRecoveryHidden = false
            switch state {
            case .warmingUp, .recording, .transcribing, .retrying:
                escapeHotKey.capture(true)
            case .idle, .noSpeech, .error, .recovery, .copied:
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

    private(set) var pendingDictation: PendingDictation?
    private(set) var isRecoveryHidden = false
    private let makeTranscriber: (TranscriptionRoute) -> any Transcriber
    private let insertText: @MainActor (String) -> Inserter.Outcome
    private let copyText: @MainActor (String) -> Inserter.Outcome
    private let refreshInput: @MainActor () async throws -> TextInputSnapshot

    /// Whether the overlay is showing the recovery card rather than plain
    /// dictation progress.
    var showsCard: Bool {
        switch state {
        case .error, .retrying, .recovery: true
        default: false
        }
    }

    /// Whether the card holds something the user can still act on or lose. This
    /// is what the menu offers and what quitting warns about, so a first attempt
    /// does not count: it retains audio, but nothing has failed and nothing is
    /// on offer until it does.
    var hasRecovery: Bool { pendingDictation != nil && showsCard }

    private let settings: Settings
    private let hotKey = HotKey()
    private let escapeHotKey = EscapeHotKey()
    private let recorder = Recorder()
    private let soundPlayer = StatusSoundPlayer()
    private let textContextCapture = TextContextCapture()
#if DEBUG
    let inputMonitor = DebugInputMonitor()
#endif
    /// Set while the settings screen is recording a new trigger, so pressing keys
    /// to choose one does not start a dictation.
    var ignoresTrigger = false
    private var triggerHeld = false
    private var transcriptionTask: Task<Void, Never>?
    private var stateResetTask: Task<Void, Never>?
    private var recorderPollingTask: Task<Void, Never>?

    init(
        settings: Settings,
        makeTranscriber: ((TranscriptionRoute) -> any Transcriber)? = nil,
        insertText: @escaping @MainActor (String) -> Inserter.Outcome = Inserter.insert,
        copyText: @escaping @MainActor (String) -> Inserter.Outcome = Inserter.copy,
        refreshInput: @escaping @MainActor () async throws -> TextInputSnapshot = TextContextCapture.refresh
    ) {
        self.settings = settings
        self.makeTranscriber = makeTranscriber ?? { settings.makeTranscriber(for: $0) }
        self.insertText = insertText
        self.copyText = copyText
        self.refreshInput = refreshInput
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
        discardRecovery()
        stateResetTask?.cancel()
        recorderPollingTask?.cancel()
        textContextCapture.cancel()
        recorder.shutDown()
    }

    func show(_ failure: DictationFailure) {
        fail(failure)
    }

    /// The trigger is whatever combination the user chose, matched exactly, so an
    /// unrelated modifier pressed on top of it reads as a release.
    private func modifiersChanged(_ held: Set<TriggerModifier>) {
        let isHeld = !ignoresTrigger && settings.dictationTrigger.isHeld(held)
        guard isHeld != triggerHeld else { return }
        triggerHeld = isHeld
        switch (settings.dictationMode, isHeld) {
        case (.hold, true):
            pressed()
        case (.hold, false):
            released()
        case (.toggle, true):
            toggled()
        case (.toggle, false):
            return
        }
    }

    /// In toggle mode each press flips between recording and not, so the press
    /// that ends a recording does what releasing the key does in hold mode.
    private func toggled() {
        switch state {
        case .warmingUp, .recording:
            released()
        default:
            pressed()
        }
    }

    private func pressed() {
        guard !hasRecovery else {
            revealRecovery()
            return
        }
        switch state {
        case .idle:
            break
        case .noSpeech, .error, .copied:
            stateResetTask?.cancel()
        case .warmingUp, .recording, .transcribing, .retrying, .recovery:
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
        case .idle, .transcribing, .noSpeech, .error, .retrying, .recovery, .copied:
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
        transcribe(recording, rules: rules, route: route, context: insertionContext)
    }

    /// Own the recording before launching work. Initial delivery can use its
    /// captured target; recovery deliberately never keeps that target alive.
    func transcribe(
        _ recording: Recording,
        rules: Set<FormattingRule>,
        route: TranscriptionRoute,
        context: TextInputSnapshot? = nil
    ) {
        guard pendingDictation == nil else { return }
        pendingDictation = .audio(recording, rules: rules, route: route)
        runTranscription(recording, rules: rules, route: route, context: context, isRetry: false)
    }

    /// Reuses retained speech and language with current credentials. Repeated
    /// clicks and calls without recoverable audio are harmless.
    func retry(using model: TranscriptionModel) {
        guard transcriptionTask == nil,
              case .audio(let recording, let rules, let previous) = pendingDictation else { return }
        let route = TranscriptionRoute(model: model, language: previous.language)
        pendingDictation = .audio(recording, rules: rules, route: route)
        runTranscription(recording, rules: rules, route: route, context: nil, isRetry: true)
    }

    private func runTranscription(
        _ recording: Recording,
        rules: Set<FormattingRule>,
        route: TranscriptionRoute,
        context: TextInputSnapshot?,
        isRetry: Bool
    ) {
        stateResetTask?.cancel()
        let transcriber = makeTranscriber(route)
        let demoMode = isDemoMode
        state = isRetry ? .retrying : .transcribing
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
                guard let self else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fail(.transcription(.emptyText))
                    return
                }
                var result = TranscriptFormatter.apply(rules, to: text)
                var targetChanged = false
#if DEBUG
                var currentInput: TextInputSnapshot?
#endif
                if !isRetry, let context {
                    let current = try await refreshInput()
#if DEBUG
                    currentInput = current
#endif
                    try Task.checkCancellation()
                    targetChanged = current.targetChanged(since: context)
                    if !targetChanged, let freshContext = current.context {
                        result = TranscriptFitter.fit(result, to: freshContext)
                    }
                }
#if DEBUG
                inputMonitor.record(
                    stop: context, current: currentInput, transcript: text, output: result,
                    decision: isRetry || targetChanged ? "Retain for recovery; no paste" : "Request paste"
                )
#endif
                transcriptionTask = nil
                // A successful retry retains text instead of delivering it: the
                // window it was dictated into is long gone.
                pendingDictation = .text(result)
                if isRetry || targetChanged {
                    state = .recovery
                } else {
                    switch insertText(result) {
                    case .delivered:
                        pendingDictation = nil
                        state = .idle
                    case .clipboardUnavailable:
                        fail(.clipboardUnavailable)
                    }
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                transcriptionTask = nil
                let failure = TranscriptionFailure(error)
                if failure == .unknown {
                    // An unclassified error means the cause vocabulary is missing
                    // a case, and the user only sees "couldn't finish". Domain and
                    // code are enough to find it later; the message is left out
                    // because it can quote the audio that was sent.
                    let error = error as NSError
                    NSLog(
                        "Yazar could not classify a dictation transcription failure from %@ (%@ %ld)",
                        route.model.provider.displayName, error.domain, error.code
                    )
                }
                fail(.transcription(failure))
            }
        }
    }

    /// Copy failure preserves the text; success releases the recovery artifact.
    func copyRecoveredText() {
        guard case .text(let text) = pendingDictation else { return }
        switch copyText(text) {
        case .delivered:
            pendingDictation = nil
            state = .copied
            resetState(after: .seconds(2))
        case .clipboardUnavailable:
            fail(.clipboardUnavailable)
        }
    }

    /// Cancel before freeing the payloads: a reply that lands afterwards sees a
    /// cancelled task and returns without reviving what it was carrying.
    func discardRecovery() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        stateResetTask?.cancel()
        pendingDictation = nil
        state = .idle
    }

    func dismissRecovery() {
        isRecoveryHidden = true
    }

    /// Shows retained recovery without changing or discarding its payload.
    func revealRecovery() {
        isRecoveryHidden = false
    }

    /// Escape abandons an initial dictation, but cancelling a retry keeps audio.
    /// The card's dismiss button routes here too, so both ways of closing it
    /// agree on what closing means in each state.
    func cancel() {
        textContextCapture.cancel()
        switch state {
        case .warmingUp, .recording:
            recorderPollingTask?.cancel()
            recorder.cancel()
            recordingStartedAt = nil
            level = 0
            state = .idle
        case .transcribing:
            discardRecovery()
            play(.cancel)
        case .retrying:
            transcriptionTask?.cancel()
            transcriptionTask = nil
            // Cancellation retains audio.
            state = .recovery
            play(.cancel)
        case .error:
            // Closing a failure gives it up. Keeping the payload would make the
            // next trigger reopen the error instead of starting a recording.
            discardRecovery()
        case .recovery:
            dismissRecovery()
        case .idle, .noSpeech, .copied:
            return
        }
    }

    private func fail(_ failure: DictationFailure) {
        textContextCapture.cancel()
        recorderPollingTask?.cancel()
        recorderPollingTask = nil
        recorder.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        stateResetTask?.cancel()
        recordingStartedAt = nil
        level = 0
        play(.error)
        state = .error(failure)
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
