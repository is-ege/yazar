import Foundation
import Synchronization

/// The text of a transcription in progress, held away from the main actor.
///
/// A provider revises its guess many times a second, and the view that shows the
/// result costs a full text layout to redraw. Consuming the provider's stream
/// straight into observable state ties the two together: while SwiftUI is laying
/// out the transcript, the consuming task cannot run, the updates behind it
/// queue, and words arrive on screen seconds after they were spoken — some of
/// them after the recording has already stopped.
///
/// Accumulating here breaks that. The stream is drained as fast as it arrives,
/// on whatever thread is free, and the main actor reads only the newest text —
/// however many revisions it missed in between, since every one of them was
/// superseded anyway.
nonisolated final class LiveTranscript: Sendable {
    /// What the transcript looks like at one moment: everything settled, plus
    /// the tail the provider has not committed to yet.
    struct Snapshot: Hashable, Sendable {
        var finalized = ""
        var volatile = ""
    }

    private let state = Mutex(Snapshot())

    var snapshot: Snapshot {
        state.withLock { $0 }
    }

    /// The settled text on its own, which is what gets written to disk. The
    /// volatile tail is a guess and is about to be replaced.
    var finalized: String {
        state.withLock { $0.finalized }
    }

    func reset() {
        state.withLock { $0 = Snapshot() }
    }

    func append(_ update: TranscriptUpdate) {
        state.withLock {
            $0.finalized += update.finalized
            $0.volatile = update.volatile
        }
    }

    /// Drops the tail once nothing more is coming, so a finished meeting is not
    /// left showing a guess that will never be confirmed.
    func clearVolatile() {
        state.withLock { $0.volatile = "" }
    }
}
