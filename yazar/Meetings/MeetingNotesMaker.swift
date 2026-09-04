import Foundation
import Observation

/// Makes notes from a stored meeting's transcript and files them with it.
///
/// Distinct from `NotesComposer`, which owns the transcript the settings screen
/// is editing and belongs to that screen's lifetime. This one owns no text at
/// all: it is handed a meeting's id and works on the stored record, which is
/// what lets a meeting that ends while nobody is watching still come back with
/// notes.
@MainActor
@Observable
final class MeetingNotesMaker {
    private let store: MeetingStore
    private let settings: Settings
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Why the last attempt failed, per meeting. Kept here rather than in the
    /// record because it describes an attempt, not the meeting, and the answer
    /// to it is to try again.
    private(set) var failures: [UUID: String] = [:]

    init(store: MeetingStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    func isWorking(on id: UUID) -> Bool {
        tasks[id] != nil
    }

    /// Generates notes for one meeting. Does nothing for a meeting with no
    /// transcript to read or one already being worked on, so the automatic call
    /// at the end of a recording and the button in the library are the same path.
    func make(for id: UUID) {
        guard tasks[id] == nil,
              let meeting = store.meetings.first(where: { $0.id == id }),
              !meeting.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let transcript = meeting.transcript
        let maker = OpenRouterNoteMaker(
            client: OpenRouterClient(
                apiKey: settings.credentials.key(for: .openRouter),
                model: settings.openRouterNotesModel
            )
        )
        failures[id] = nil

        tasks[id] = Task { [weak self] in
            let result: Result<Notes, any Error>
            do {
                result = .success(try await maker.makeNotes(from: transcript))
            } catch {
                result = .failure(error)
            }
            self?.finish(id, result: result)
        }
    }

    private func finish(
        _ id: UUID,
        result: Result<Notes, any Error>
    ) {
        tasks[id] = nil
        guard var meeting = store.meetings.first(where: { $0.id == id }) else { return }
        switch result {
        case .success(let notes):
            meeting.notes = notes
        case .failure(let error):
            NSLog("Yazar could not make notes for a meeting: %@", error.localizedDescription)
            failures[id] = error.localizedDescription
        }
        store.save(meeting)
    }
}
