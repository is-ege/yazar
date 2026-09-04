import Foundation

/// The model and language selected for one transcription, snapshotted before
/// asynchronous work begins.
nonisolated struct TranscriptionRoute: Equatable, Sendable {
    let model: TranscriptionModel
    let language: String?
}
