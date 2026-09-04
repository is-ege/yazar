#if DEBUG
import Foundation
import Observation

/// Owns one imported development transcript and the notes made from it.
///
/// Shaped after `Yazar`: a state enum the view reads, one cancellable task, and
/// no view-facing wording beyond what a failure already carries.
@MainActor
@Observable
final class NotesComposer {
    enum State: Hashable {
        case idle
        case working
        case failed(String)
    }

    var transcript = "" {
        didSet {
            // Notes on screen belong to the text that produced them, so editing
            // the transcript retires them rather than leaving a stale document
            // beside a changed source.
            guard transcript != oldValue else { return }
            notes = nil
            // A new transcript is a new meeting. Without this, regenerating
            // after replacing the text would overwrite the previous meeting's
            // notes with notes from unrelated words.
            savedMeetingID = nil
            if case .failed = state { state = .idle }
        }
    }

    private(set) var state: State = .idle
    private(set) var notes: Notes?

    private let settings: Settings
    private let store: MeetingStore
    private var task: Task<Void, Never>?
    /// Set once a transcript has been filed, so regenerating updates that
    /// meeting instead of leaving a duplicate behind.
    private var savedMeetingID: UUID?

    init(settings: Settings, store: MeetingStore) {
        self.settings = settings
        self.store = store
    }

    var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGenerate: Bool {
        state != .working && hasTranscript
    }

    func generate() {
        guard canGenerate else { return }
        let maker = OpenRouterNoteMaker(
            client: OpenRouterClient(
                apiKey: settings.credentials.key(for: .openRouter),
                model: settings.openRouterNotesModel
            )
        )
        let transcript = transcript
        notes = nil
        state = .working
        task?.cancel()
        task = Task { [weak self] in
            do {
                let notes = try await maker.makeNotes(from: transcript)
                try Task.checkCancellation()
                self?.notes = notes
                self?.state = .idle
                self?.file(notes)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Files the result under Meetings so notes the developer waited for survive
    /// closing the settings window. Regeneration updates the same meeting.
    private func file(_ notes: Notes) {
        let id = savedMeetingID ?? UUID()
        savedMeetingID = id
        var meeting = store.meetings.first { $0.id == id }
            ?? Meeting(id: id, title: Self.title(for: Date()))
        meeting.importedTranscript = transcript
        meeting.notes = notes
        store.save(meeting)
    }

    private static func title(for date: Date) -> String {
        "Transcript — \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    /// Reads a dropped or chosen transcript file. Anything that is not decodable
    /// text fails here rather than being sent to the model as mojibake.
    func load(contentsOf url: URL) {
        do {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            transcript = try String(contentsOf: url, encoding: .utf8)
            state = .idle
        } catch {
            state = .failed("Could not read \(url.lastPathComponent) as text.")
        }
    }
}
#endif
