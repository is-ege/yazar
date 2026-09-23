/// How the dictation key starts and stops a recording.
enum DictationMode: String, CaseIterable, Identifiable, Sendable {
    /// Record while the key is held; letting go transcribes.
    case hold
    /// One press starts recording and the next press transcribes, so long
    /// dictations do not need a finger on the key.
    case toggle

    var id: Self { self }

    var displayName: String {
        switch self {
        case .hold: "Hold to talk"
        case .toggle: "Press to toggle"
        }
    }
}
