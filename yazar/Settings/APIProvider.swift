/// A service Yazar holds an API key for. The raw value is the Keychain account
/// name, so a case that already shipped cannot be renamed without stranding the
/// stored credential.
nonisolated enum APIProvider: String, CaseIterable, Identifiable, Sendable {
    case openRouter

    var id: Self { self }

    var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        }
    }

    /// What this key unlocks, so the Providers page says why it is needed.
    var keyDescription: String {
        switch self {
        case .openRouter:
            "Used for OpenRouter transcription and meeting notes. Stored in your Mac's Keychain."
        }
    }
}
