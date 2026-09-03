import SwiftUI

/// Provider and model controls for one enabled macOS input source.
struct ModelRoutingRow: View {
    @Bindable var settings: TranscriptionSettings
    let inputSource: KeyboardInputSource

    var body: some View {
        SettingsRow(inputSource.name, description: sourceDescription) {
            HStack(spacing: 8) {
                Picker(providerAccessibilityName, selection: providerSelection) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 112)

                if selectedModel.provider == .openRouter {
                    TranscriptionModelMenu(
                        model: openRouterModelSelection,
                        accessibilityName: modelAccessibilityName
                    )
                    .frame(width: 184)
                } else {
                    AppleSpeechModelControl(language: inputSource.languageIdentifier)
                        .frame(width: 184, alignment: .trailing)
                }
            }
        }
    }

    private var selectedModel: TranscriptionModel {
        settings.model(for: inputSource.id)
    }

    private var providerSelection: Binding<TranscriptionProvider> {
        Binding {
            selectedModel.provider
        } set: { provider in
            settings.setProvider(provider, for: inputSource.id)
        }
    }

    private var openRouterModelSelection: Binding<String> {
        Binding {
            if case .openRouter(let model) = selectedModel {
                return model
            }
            return settings.openRouterModel
        } set: { model in
            settings.setModel(.openRouter(model), for: inputSource.id)
        }
    }

    private var sourceDescription: String {
        guard let language = inputSource.languageIdentifier else {
            return "No intended language; uses the fixed language setting."
        }
        let name = Locale.current.localizedString(forIdentifier: language) ?? language
        return "Uses \(name) as the transcription language."
    }

    private var providerAccessibilityName: String {
        "Provider for \(inputSource.name)"
    }

    private var modelAccessibilityName: String {
        "Model for \(inputSource.name)"
    }
}
