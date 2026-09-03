import Foundation
import Observation

/// Fixed transcription configuration, per-input-source overrides, and the
/// credentials needed to turn a resolved route into a transcriber.
@MainActor
@Observable
final class TranscriptionSettings {
    private enum Key {
        static let provider = "transcriptionProvider"
        static let model = "model"
        static let language = "language"
        static let modelRoutingEnabled = "modelRoutingEnabled"
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

    var isModelRoutingEnabled: Bool {
        didSet { defaults.set(isModelRoutingEnabled, forKey: Key.modelRoutingEnabled) }
    }

    private var modelsByInputSource: [String: TranscriptionModel] {
        didSet {
            guard let data = try? JSONEncoder().encode(modelsByInputSource) else { return }
            defaults.set(data, forKey: Key.modelsByInputSource)
        }
    }

    private(set) var apiKeys: [TranscriptionProvider: String] = [:]
    private(set) var apiKeyError: String?

    /// OpenRouter is currently the only provider with a credential. This stays
    /// writable even when the fixed provider is Apple because a routed source
    /// may still need it.
    var openRouterAPIKey: String {
        get { apiKey(for: .openRouter) }
        set { setAPIKey(newValue, for: .openRouter) }
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
        openRouterModel = defaults.string(forKey: Key.model) ?? "openai/whisper-1"
        language = defaults.string(forKey: Key.language) ?? ""
        isModelRoutingEnabled = defaults.bool(forKey: Key.modelRoutingEnabled)
        modelsByInputSource = defaults.data(forKey: Key.modelsByInputSource)
            .flatMap {
                try? JSONDecoder().decode([String: TranscriptionModel].self, from: $0)
            }
            ?? [:]

        do {
            try ProviderKeychain.migrateLegacyKey()
            for provider in TranscriptionProvider.allCases where provider.needsAPIKey {
                apiKeys[provider] = try ProviderKeychain.load(for: provider)
            }
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    /// Selects one route from a snapshot of the current input source. A missing
    /// source or language falls back to the fixed configuration without making
    /// callers handle an unconfigured state.
    func dictationRoute(for inputSource: KeyboardInputSource?) -> TranscriptionRoute {
        guard isModelRoutingEnabled, let inputSource else { return defaultRoute }
        return TranscriptionRoute(
            model: model(for: inputSource.id),
            language: inputSource.languageIdentifier ?? optionalLanguage
        )
    }

    /// The choice a source inherits or overrides in the routing section.
    func model(for inputSourceID: String) -> TranscriptionModel {
        modelsByInputSource[inputSourceID] ?? defaultModel
    }

    /// Stores only a real override. New sources and sources reset to the fixed
    /// choice continue following that single fallback truth.
    func setModel(_ model: TranscriptionModel, for inputSourceID: String) {
        if model == defaultModel {
            modelsByInputSource[inputSourceID] = nil
        } else {
            modelsByInputSource[inputSourceID] = model
        }
    }

    func setProvider(_ provider: TranscriptionProvider, for inputSourceID: String) {
        switch provider {
        case .appleSpeech:
            setModel(.appleSpeech, for: inputSourceID)
        case .openRouter:
            setModel(.openRouter(openRouterModel), for: inputSourceID)
        }
    }

    /// Builds a transcriber with its language and any credential already bound.
    func makeTranscriber(for route: TranscriptionRoute) -> any Transcriber {
        switch route.model {
        case .appleSpeech:
            AppleSpeechTranscriber(language: route.language)
        case .openRouter(let model):
            OpenRouterTranscriber(
                apiKey: apiKey(for: .openRouter),
                model: model,
                language: route.language
            )
        }
    }

    func apiKey(for provider: TranscriptionProvider) -> String {
        apiKeys[provider] ?? ""
    }

    private func setAPIKey(_ key: String, for provider: TranscriptionProvider) {
        guard apiKey(for: provider) != key else { return }
        apiKeys[provider] = key
        do {
            try ProviderKeychain.save(key, for: provider)
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }
}
