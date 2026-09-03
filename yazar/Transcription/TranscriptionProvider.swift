nonisolated enum TranscriptionProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleSpeech
    case openRouter

    var id: Self { self }

    var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .openRouter: "OpenRouter"
        }
    }

    /// What choosing this provider means for the user's audio.
    var summary: String {
        switch self {
        case .appleSpeech:
            "Processes audio on this Mac. macOS may fetch a language asset on first use."
        case .openRouter:
            "Sends each recording to OpenRouter for transcription."
        }
    }

    /// What a blank language field falls back to.
    var languageHint: String {
        switch self {
        case .appleSpeech: "Leave blank to use your Mac's current language."
        case .openRouter: "Leave blank to detect the spoken language."
        }
    }

    /// Whether this provider needs a credential in the Keychain.
    var needsAPIKey: Bool {
        switch self {
        case .appleSpeech: false
        case .openRouter: true
        }
    }

    var languagePlaceholder: String {
        switch self {
        case .appleSpeech: "System language"
        case .openRouter: "Auto-detect"
        }
    }

}
