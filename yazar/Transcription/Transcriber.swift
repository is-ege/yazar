import Foundation

/// Transcribes speech with a selected speech-to-text provider.
nonisolated protocol Transcriber: Sendable {
    /// Returns finalized, trimmed text for one complete recording. An empty
    /// string means the provider recognized no text. Implementations must
    /// cooperate with task cancellation.
    func transcribe(_ recording: Recording) async throws -> String

    /// Transcribes canonical audio from a complete buffer, stored range, or a
    /// file that is still being captured.
    ///
    /// Updates come back while a live meeting is still running rather than in
    /// one lump at the end. Ending the returned stream, or cancelling the
    /// consuming task, abandons the transcription.
    func transcribe(_ audio: MeetingAudio) -> AsyncThrowingStream<TranscriptUpdate, any Error>
}
