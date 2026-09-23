import AppKit
import SwiftUI

/// One meeting: its notes, and the transcript they came from. While the meeting
/// is the one being recorded, the transcript in progress stands in for both.
struct MeetingDetailView: View {
    let meeting: Meeting
    @Bindable var store: MeetingStore
    let session: MeetingSession
    let notesMaker: MeetingNotesMaker
    let transcriptMaker: MeetingTranscriptMaker
    @State private var showsTranscript = false
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if isLive {
                    live
                } else if meeting.hasNotes, let notes = meeting.notes {
                    if let failure = meeting.transcriptionFailure {
                        problem("These notes were made from an incomplete transcript. \(failure)")
                    }
                    NotesView(notes: notes)
                } else {
                    // Notes that came back empty are treated as none: the retry
                    // is the useful thing to offer, not a sentence saying the
                    // meeting had nothing in it.
                    pendingNotes
                }

                if !isLive, !meeting.transcript.isEmpty {
                    DisclosureGroup("Transcript", isExpanded: $showsTranscript) {
                        Text(meeting.transcript)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(maxWidth: 640, alignment: .topLeading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The meeting being recorded right now, whose text is still arriving and is
    /// therefore read from the session rather than from the stored record.
    private var isLive: Bool {
        session.activeMeetingID == meeting.id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.title)
                .font(.system(size: 18, weight: .semibold))

            HStack(spacing: 8) {
                Text(meeting.startedAt.formatted(date: .long, time: .shortened))
                if meeting.recordedDuration > 0 {
                    Text(duration)
                }
                if let badge = meetingBadge(
                    for: meeting,
                    activeMeetingID: session.activeMeetingID,
                    isRecording: session.isRecording,
                    isTranscribing: transcriptMaker.isWorking(on: meeting.id),
                    isMakingNotes: notesMaker.isWorking(on: meeting.id)
                ) {
                    Text(badge).foregroundStyle(.orange)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let notes = meeting.notes, !notes.isEmpty {
                    Button("Copy as Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notes.markdown, forType: .string)
                    }
                }
                Button("Delete", role: .destructive) { confirmsDelete = true }
                    .disabled(isLive)
            }
            .confirmationDialog(
                "Delete this meeting?",
                isPresented: $confirmsDelete
            ) {
                Button("Delete", role: .destructive) { store.delete(meeting) }
            } message: {
                Text("Its transcript and notes are removed from this Mac. This cannot be undone.")
            }
        }
    }

    /// A meeting without notes, which is a meeting that stopped somewhere along
    /// the way from audio to text to notes. Both steps run on their own when a
    /// recording ends, so this says which one did not finish and offers it again.
    @ViewBuilder
    private var pendingNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            if transcriptMaker.isWorking(on: meeting.id) {
                working("Transcribing…")
            } else if notesMaker.isWorking(on: meeting.id) {
                working("Making notes…")
            } else if let failure = meeting.transcriptionFailure {
                Text("Transcription did not finish, so this transcript may be incomplete.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                problem(failure)

                HStack(spacing: 10) {
                    if hasAudio {
                        Button("Transcribe") { transcriptMaker.make(for: meeting.id) }
                            .buttonStyle(.borderedProminent)
                    }
                    if !meeting.transcript.isEmpty {
                        Button("Make Notes from Incomplete Transcript") {
                            notesMaker.make(for: meeting.id)
                        }
                    }
                }

                if !hasAudio {
                    Text("Its audio is no longer on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if let notesFailure = notesMaker.failures[meeting.id] {
                    problem(notesFailure)
                }
            } else if meeting.transcript.isEmpty {
                Text("This meeting has no transcript yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if hasAudio {
                    // The audio is still on disk, so a failed transcription is a
                    // retry rather than a lost meeting.
                    Button("Transcribe") { transcriptMaker.make(for: meeting.id) }
                } else {
                    Text("Its audio is no longer on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("This meeting has no notes yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let failure = notesMaker.failures[meeting.id] {
                    problem(failure)
                }

                Button("Make Notes") { notesMaker.make(for: meeting.id) }
            }
        }
    }

    private var hasAudio: Bool {
        store.audioByteCount(for: meeting) > 0
    }

    private func working(_ title: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(title)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private func problem(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: session.isRecording ? "record.circle" : "ellipsis.circle")
                Text(session.isRecording ? "Recording" : "Finishing the transcript")
                if session.isRecording, session.elapsed > 0 {
                    Text(Duration.seconds(session.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(session.isRecording ? .red : .secondary)

            // The recording carries on when transcription fails, so this reads as
            // a warning about the text rather than as the meeting having stopped.
            if let failure = session.transcriptionFailure {
                problem(failure)
            }

            // The volatile tail is dimmed inside this view because it is the
            // provider's current guess and is replaced, not appended to.
            LiveTranscriptView(session: session)
        }
    }

    private var duration: String {
        Duration.seconds(meeting.recordedDuration)
            .formatted(.time(pattern: .hourMinute))
    }
}
