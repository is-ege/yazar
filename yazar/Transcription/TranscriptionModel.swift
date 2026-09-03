import Foundation

/// One valid provider/model choice. Apple chooses its model from the language;
/// OpenRouter needs the exact remote model identifier.
nonisolated enum TranscriptionModel: Hashable, Sendable {
    case appleSpeech
    case openRouter(String)

    var provider: TranscriptionProvider {
        switch self {
        case .appleSpeech: .appleSpeech
        case .openRouter: .openRouter
        }
    }
}

extension TranscriptionModel: Codable {
    private enum CodingKeys: String, CodingKey {
        case provider
        case model
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(TranscriptionProvider.self, forKey: .provider)
        switch provider {
        case .appleSpeech:
            self = .appleSpeech
        case .openRouter:
            self = .openRouter(try container.decode(String.self, forKey: .model))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        if case .openRouter(let model) = self {
            try container.encode(model, forKey: .model)
        }
    }
}
