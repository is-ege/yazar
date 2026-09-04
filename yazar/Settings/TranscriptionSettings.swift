import Foundation
import Observation

/// Fixed transcription configuration and per-input-source overrides, resolved
/// into the route one transcription runs with.
@MainActor
@Observable
final class TranscriptionSettings {
    private enum Key {
        static let provider = "transcriptionProvider"
        static let model = "model"
        static let language = "language"
        /// Named for models when it shipped; it routes the language too.
        static let inputSourceRouting = "modelRoutingEnabled"
        static let modelsByInputSource = "transcriptionModelsByInputSource"
    }

    private let defaults: UserDefaults

    var provider: TranscriptionProvider {
        didSet { defaults.set(provider.rawValue, forKey: Key.provider) }
    }

    var openRouterModel: String {
        didSet { defaults.set(openRouterModel, forKey: Key.model) }
    }

    /// Raw text-field contents. `optionalLanguage` is the canonical reading of
    /// it, and persistence goes through that too, so blank means no hint.
    var language: String {
        didSet { defaults.set(optionalLanguage, forKey: Key.language) }
    }

    /// Whether the selected keyboard input source picks the model and the
    /// language, rather than the fixed configuration above.
    var isInputSourceRoutingEnabled: Bool {
        didSet {
            defaults.set(isInputSourceRoutingEnabled, forKey: Key.inputSourceRouting)
        }
    }

    private var modelsByInputSource: [String: TranscriptionModel] {
        didSet {
            guard let data = try? JSONEncoder().encode(modelsByInputSource) else { return }
            defaults.set(data, forKey: Key.modelsByInputSource)
        }
    }

    var optionalLanguage: String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var defaultRoute: TranscriptionRoute {
        TranscriptionRoute(model: defaultModel, language: optionalLanguage)
    }

    private var defaultModel: TranscriptionModel {
        switch provider {
        case .appleSpeech: .appleSpeech
        case .openRouter: .openRouter(openRouterModel)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = defaults.string(forKey: Key.provider)
            .flatMap(TranscriptionProvider.init(rawValue:))
            ?? .openRouter
        openRouterModel = defaults.string(forKey: Key.model) ?? "microsoft/mai-transcribe-2"
        language = defaults.string(forKey: Key.language) ?? ""
        isInputSourceRoutingEnabled = defaults.bool(forKey: Key.inputSourceRouting)
        modelsByInputSource = defaults.data(forKey: Key.modelsByInputSource)
            .flatMap {
                try? JSONDecoder().decode([String: TranscriptionModel].self, from: $0)
            }
            ?? [:]
    }

    /// Selects one route from a snapshot of the current input source. A missing
    /// source or language falls back to the fixed configuration without making
    /// callers handle an unconfigured state.
    func dictationRoute(for inputSource: KeyboardInputSource?) -> TranscriptionRoute {
        guard isInputSourceRoutingEnabled, let inputSource else { return defaultRoute }
        return TranscriptionRoute(
            model: model(for: inputSource.id),
            language: inputSource.languageIdentifier ?? optionalLanguage
        )
    }

    /// The override stored for a source, or nil when it follows the fixed
    /// choice. The routing row needs the difference; transcription does not.
    func modelOverride(for inputSourceID: String) -> TranscriptionModel? {
        modelsByInputSource[inputSourceID]
    }

    /// What a source transcribes with, override or not.
    func model(for inputSourceID: String) -> TranscriptionModel {
        modelOverride(for: inputSourceID) ?? defaultModel
    }

    /// Stores exactly what the user picked; nil returns the source to the fixed
    /// choice. Matching today's default is not inheritance — a source pinned to
    /// it has to stay put when the fixed choice changes.
    func setModel(_ model: TranscriptionModel?, for inputSourceID: String) {
        modelsByInputSource[inputSourceID] = model
    }

    func setProvider(_ provider: TranscriptionProvider?, for inputSourceID: String) {
        switch provider {
        case nil:
            setModel(nil, for: inputSourceID)
        case .appleSpeech:
            setModel(.appleSpeech, for: inputSourceID)
        case .openRouter:
            setModel(.openRouter(openRouterModel), for: inputSourceID)
        }
    }
}
