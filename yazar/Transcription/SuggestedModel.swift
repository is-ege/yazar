import Foundation

/// An OpenRouter transcription model offered in Settings. `summary` is the one
/// line shown beneath the model name in the model pop-up, so it stays short
/// enough to read at a glance.
struct SuggestedModel: Identifiable {
    let id: String
    let summary: String

    static let all: [SuggestedModel] = [
        SuggestedModel(
            id: "microsoft/mai-transcribe-2",
            summary: "Excellent accuracy and broad language support"
        ),
        SuggestedModel(
            id: "mistralai/voxtral-mini-transcribe",
            summary: "Very fast, affordable. Limited language support"
        ),
    ]
}
