import AppKit
import Foundation
import Observation

/// Runs one meeting recording: the meeting-mode peer of `Yazar`.
///
/// Independent of dictation on purpose. Meeting capture never opens the
/// microphone, so `Recorder` keeps it and the dictation trigger stays live while
/// a meeting records.
@MainActor
@Observable
final class MeetingSession {
    enum State: Hashable {
        case idle
        case starting
        case recording
        case stopping
        /// Audio has stopped but the provider has not finished with it. Kept
        /// distinct from stopping because the wait is open-ended: a chunk may
        /// still be uploading, and the meeting is not filed until it lands.
        case transcribing
        case failed(String)
    }

    /// A provider that never returns must not wedge meeting mode for the rest of
    /// the launch, so the wait after the last sample is bounded. Generous, since
    /// it may cover one more upload of a long chunk.
    private static let finalizeTimeout = Duration.seconds(180)

    /// The activity token follows the states that are holding audio, so every
    /// path that ends or abandons a meeting also releases it. A leaked assertion
    /// keeps the Mac awake indefinitely and is visible in `pmset -g assertions`.
    private(set) var state: State = .idle {
        didSet {
            switch state {
            case .starting, .recording, .stopping, .transcribing:
                beginActivity()
            case .idle, .failed:
                endActivity()
            }
        }
    }

    private(set) var activeMeetingID: UUID?
    private(set) var elapsed: TimeInterval = 0
    /// Settled text for the segment being recorded. Written into the segment as
    /// the meeting runs, so a crash costs the last few seconds rather than the
    /// whole transcript.
    private(set) var liveTranscript = ""
    /// The provider's guess at what is being said right now, replaced with every
    /// update and never stored. Only Apple Speech produces one; a chunked upload
    /// has nothing provisional to show.
    private(set) var liveVolatileText = ""
    /// A transcription that failed while the recording carried on. Surfaced
    /// rather than thrown, because the audio is still being kept and the meeting
    /// should not be stopped over it.
    private(set) var transcriptionFailure: String?

    private let store: MeetingStore
    private let settings: Settings
    private let notesMaker: MeetingNotesMaker
    private let recorder = SystemAudioRecorder()
    private var audioFile: MeetingAudioFile?
    private var transcriptionTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var activity: (any NSObjectProtocol)?
    private var sleepObserver: (any NSObjectProtocol)?
    private var tickTask: Task<Void, Never>?

    init(store: MeetingStore, settings: Settings, notesMaker: MeetingNotesMaker) {
        self.store = store
        self.settings = settings
        self.notesMaker = notesMaker
    }

    /// Whether audio is still being captured.
    var isRecording: Bool {
        switch state {
        case .starting, .recording, .stopping: true
        case .idle, .transcribing, .failed: false
        }
    }

    /// Whether a meeting is in flight at all, transcription included. This is
    /// what guards starting another one; `isRecording` is what the microphone
    /// indicator and the stop control follow.
    var isActive: Bool {
        switch state {
        case .starting, .recording, .stopping, .transcribing: true
        case .idle, .failed: false
        }
    }

    /// Begins a new meeting, or continues an existing one with a fresh segment.
    func start(resuming meeting: Meeting? = nil) async {
        guard !isActive else { return }
        state = .starting

        var subject = meeting ?? Meeting(
            title: Self.title(for: Date()),
            segments: []
        )
        subject.transcriptionFailure = nil

        let audio: MeetingAudio
        do {
            let file = try MeetingAudioFile(url: try store.audioURL(for: subject))
            audioFile = file
            audio = MeetingAudio(source: .tail(file.url, at: Int(file.byteCount), file: file))
            // The file already holds every earlier segment, so where it ends is
            // where this one starts.
            subject.segments.append(
                MeetingSegment(startedAt: Date(), audioStart: Int(file.byteCount))
            )
            // Written before capture starts so a crash during startup still
            // leaves a record for the launch scan to find.
            store.save(subject)
            activeMeetingID = subject.id
            try await recorder.start(writingTo: file) { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.finish(reason: .interrupted, failure: error.localizedDescription)
                }
            }
        } catch {
            audioFile?.close()
            audioFile = nil
            activeMeetingID = nil
            // A start that captured nothing leaves no trace. Otherwise the
            // library fills with empty meetings that the next launch scan reads
            // as interrupted recordings.
            if let meeting {
                store.save(meeting)
            } else {
                store.delete(subject)
            }
            state = .failed(error.localizedDescription)
            return
        }

        state = .recording
        startTranscribing(audio)
        observeSleep()
        startTicking()
    }

    /// Closes the meeting on the way out of the process.
    ///
    /// Interrupted rather than stopped by the user: quitting ends the recording,
    /// but the meeting itself carried on without Yazar, and the transcript will
    /// need to say so.
    func endForTermination() {
        guard isRecording else { return }
        recorder.stopImmediately()
        finish(reason: .interrupted, failure: nil)
    }

    func stop() async {
        guard isRecording else { return }
        state = .stopping
        await recorder.stop()
        finish(reason: .stoppedByUser, failure: nil)
    }

    /// Transcribes the meeting as it is captured.
    ///
    /// The same provider dictation uses. Failures land in `transcriptionFailure`
    /// instead of stopping the meeting: the audio is being written either way,
    /// and losing an hour of recording because a request failed would be the
    /// worse trade.
    private func startTranscribing(_ audio: MeetingAudio) {
        let transcriber = settings.makeTranscriber(
            for: settings.transcription.defaultRoute
        )
        liveTranscript = ""
        liveVolatileText = ""
        transcriptionFailure = nil
        transcriptionTask = Task { [weak self] in
            do {
                for try await update in transcriber.transcribe(audio) {
                    guard let self else { return }
                    liveTranscript += update.finalized
                    liveVolatileText = update.volatile
                }
            } catch is CancellationError {
                return
            } catch {
                // Logged as well as shown. A meeting is long, and the window
                // that displays this may not have been open when it happened.
                NSLog("Yazar could not transcribe a meeting: %@", error.localizedDescription)
                self?.transcriptionFailure = error.localizedDescription
            }
        }
    }

    /// Closes the current segment and files the meeting.
    ///
    /// The segment is closed at the time recording actually ended, and the reason
    /// is recorded rather than inferred, because that reason is what will choose
    /// the wording of the transcript's gap marker. What the provider has settled
    /// on so far is written with it, so a process that dies here still keeps the
    /// transcript up to this point.
    private func finish(reason: MeetingSegment.EndReason, failure: String?) {
        tickTask?.cancel()
        tickTask = nil
        stopObservingSleep()
        // Read before closing: this is where the segment's audio ends.
        let endOffset = audioFile.map { Int($0.byteCount) }
        audioFile?.close()
        audioFile = nil
        elapsed = 0

        guard let id = activeMeetingID else {
            state = failure.map(State.failed) ?? .idle
            return
        }
        closeSegment(of: id, reason: reason, endOffset: endOffset)
        state = .transcribing
        finalizeTask = Task { [weak self] in
            await self?.awaitTranscription()
            self?.file(id, reason: reason, failure: failure)
        }
    }

    /// Waits for the tail of the transcription, under a deadline.
    private func awaitTranscription() async {
        guard let task = transcriptionTask else { return }
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: Self.finalizeTimeout)
            guard !Task.isCancelled else { return }
            self?.transcriptionFailure = "Transcription did not finish in time."
            task.cancel()
        }
        await task.value
        deadline.cancel()
    }

    /// Writes the finished meeting: the last of the transcript, any failure that
    /// makes it incomplete, and then its notes.
    ///
    /// Notes are made without being asked for. A meeting is recorded in order to
    /// have them, and the transcript is finished at exactly this moment; leaving
    /// it to a button means the useful half of the feature waits on the user
    /// remembering to press one.
    private func file(_ id: UUID, reason: MeetingSegment.EndReason, failure: String?) {
        // The session is released whether or not the record is still there, so a
        // meeting that vanished underneath cannot leave meeting mode stuck.
        if var meeting = store.meetings.first(where: { $0.id == id }) {
            writeTranscript(into: &meeting)
            // Kept with the meeting so the library can say why it has no text,
            // and offer to transcribe the audio again.
            meeting.transcriptionFailure = transcriptionFailure
            store.save(meeting)
            // Audio goes only once it has produced something. A provider that
            // returns nothing raises no failure, and that is exactly when the
            // recording is the only thing left to try again from.
            if transcriptionFailure == nil, !meeting.transcript.isEmpty {
                store.deleteAudio(for: meeting)
                notesMaker.make(for: id)
            }
        }

        transcriptionTask = nil
        activeMeetingID = nil
        liveVolatileText = ""
        state = failure.map(State.failed) ?? .idle
    }

    private func closeSegment(of id: UUID, reason: MeetingSegment.EndReason, endOffset: Int?) {
        guard var meeting = store.meetings.first(where: { $0.id == id }) else { return }
        if let index = meeting.segments.indices.last, meeting.segments[index].isOpen {
            meeting.segments[index].endedAt = Date()
            meeting.segments[index].endReason = reason
            meeting.segments[index].audioEnd = endOffset
        }
        writeTranscript(into: &meeting)
        store.save(meeting)
    }

    /// Copies the settled text into the segment being recorded. The volatile tail
    /// is deliberately left out: it is a guess, and it is about to be replaced.
    private func writeTranscript(into meeting: inout Meeting) {
        guard let index = meeting.segments.indices.last else { return }
        meeting.segments[index].transcript = liveTranscript
    }

    /// macOS grants a short window before sleep. Idle sleep is already prevented
    /// by the activity token, so reaching here means a deliberate sleep, and the
    /// meeting closes its segment rather than leaving it open.
    private func observeSleep() {
        guard sleepObserver == nil else { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                // Synchronous: the window before sleep is short, and an open
                // segment is the thing to avoid.
                self.recorder.stopImmediately()
                self.finish(reason: .interrupted, failure: nil)
            }
        }
    }

    private func stopObservingSleep() {
        guard let sleepObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        self.sleepObserver = nil
    }

    /// Drives the elapsed readout, and periodically rewrites the record so a
    /// crash loses seconds of bookkeeping rather than the whole segment.
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            var sinceFlush = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                elapsed = audioFile?.duration ?? elapsed
                if recorder.hasWriteFailure {
                    await recorder.stop()
                    finish(reason: .interrupted, failure: "Yazar could not write the meeting's audio.")
                    return
                }
                sinceFlush += 1
                if sinceFlush >= 10 {
                    sinceFlush = 0
                    flushRecord()
                }
            }
        }
    }

    private func flushRecord() {
        guard let id = activeMeetingID,
              var meeting = store.meetings.first(where: { $0.id == id }) else { return }
        writeTranscript(into: &meeting)
        store.save(meeting)
    }

    private func beginActivity() {
        guard activity == nil else { return }
        // .userInitiated already implies idleSystemSleepDisabled and disables
        // sudden termination, which is what lets applicationWillTerminate run.
        // idleDisplaySleepDisabled is deliberately not included: capture does not
        // care whether the screen is lit, and an hour of it costs battery.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Recording a meeting"
        )
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    private static func title(for date: Date) -> String {
        "Meeting — \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
