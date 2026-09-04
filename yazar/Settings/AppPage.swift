import Foundation

enum AppPage: CaseIterable, Identifiable {
    case general
    case transcription
    case formatting
    case meetings
    case providers
    case systemAccess

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .transcription: "Transcription"
        case .formatting: "Formatting"
        case .meetings: "Meetings (Beta)"
        case .providers: "Providers"
        case .systemAccess: "System Access"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "waveform"
        case .transcription: "text.bubble"
        case .formatting: "textformat"
        case .meetings: "person.2.wave.2"
        case .providers: "key.horizontal"
        case .systemAccess: "lock.shield"
        }
    }
}
