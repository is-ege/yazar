import Foundation
import Observation

@MainActor
@Observable
final class Settings {
    private enum Key {
        static let notesModel = "notesModel"
        static let playSounds = "playSounds"
        static let showRecordingTimer = "showRecordingTimer"
        static let meetingsEnabled = "meetingsEnabled"
        static let soundTheme = "soundTheme"
        static let audioInputID = "audioInputID"
        static let dictationTrigger = "dictationTrigger"
#if DEBUG
        static let demoMode = "demoMode"
#endif
    }

    private let defaults: UserDefaults

    /// Formatting owns a growing collection rather than a scalar, so it
    /// keeps its own store and invariants and shares this one's defaults.
    let formatting: FormattingSettings
    let transcription: TranscriptionSettings

    /// Shared by transcription and meeting notes, which authenticate against
    /// the same account, so neither feature owns the key.
    let credentials: Credentials

    /// The chat model that writes notes, kept apart from the transcription
    /// model because the two are never the same model.
    var openRouterNotesModel: String {
        didSet { defaults.set(openRouterNotesModel, forKey: Key.notesModel) }
    }

    var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Key.playSounds) }
    }

    var showRecordingTimer: Bool {
        didSet { defaults.set(showRecordingTimer, forKey: Key.showRecordingTimer) }
    }

    /// Meeting recording is opt-in: it needs Screen Recording and writes audio
    /// to disk, neither of which a dictation-only user should be asked for.
    var meetingsEnabled: Bool {
        didSet { defaults.set(meetingsEnabled, forKey: Key.meetingsEnabled) }
    }

    var soundTheme: SoundTheme {
        didSet { defaults.set(soundTheme.rawValue, forKey: Key.soundTheme) }
    }

    var audioInputID: String {
        didSet { defaults.set(audioInputID, forKey: Key.audioInputID) }
    }

    var dictationTrigger: DictationTrigger {
        didSet { defaults.set(dictationTrigger.rawValue, forKey: Key.dictationTrigger) }
    }

#if DEBUG
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Key.demoMode) }
    }
#endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        formatting = FormattingSettings(defaults: defaults)
        transcription = TranscriptionSettings(defaults: defaults)
        credentials = Credentials()
        openRouterNotesModel = defaults.string(forKey: Key.notesModel)
            ?? "nvidia/nemotron-3-ultra-550b-a55b:free"
        playSounds = defaults.object(forKey: Key.playSounds) == nil
            ? true
            : defaults.bool(forKey: Key.playSounds)
        showRecordingTimer = defaults.bool(forKey: Key.showRecordingTimer)
        meetingsEnabled = defaults.bool(forKey: Key.meetingsEnabled)
        soundTheme = defaults.string(forKey: Key.soundTheme)
            .flatMap(SoundTheme.init(rawValue:))
            ?? .minimal
        audioInputID = defaults.string(forKey: Key.audioInputID)
            ?? AudioInput.defaultID
            ?? ""
        dictationTrigger = defaults.string(forKey: Key.dictationTrigger)
            .flatMap(DictationTrigger.init(rawValue:))
            ?? .default
#if DEBUG
        demoMode = defaults.bool(forKey: Key.demoMode)
#endif
    }

    /// Builds the transcriber for one already-resolved route, binding its
    /// language and any credential before asynchronous transcription begins.
    func makeTranscriber(for route: TranscriptionRoute) -> any Transcriber {
        switch route.model {
        case .appleSpeech:
            AppleSpeechTranscriber(language: route.language)
        case .openRouter(let model):
            OpenRouterTranscriber(
                apiKey: credentials.key(for: .openRouter),
                model: model,
                language: route.language
            )
        }
    }
}
