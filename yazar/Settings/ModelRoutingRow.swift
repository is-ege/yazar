import SwiftUI

/// Provider and model controls for one enabled macOS input source.
struct ModelRoutingRow: View {
    @Bindable var settings: TranscriptionSettings
    let inputSource: KeyboardInputSource

    var body: some View {
        SettingsRow(inputSource.name, description: sourceDescription) {
            HStack(spacing: 8) {
                Picker(providerAccessibilityName, selection: providerSelection) {
                    Text("Default").tag(TranscriptionProvider?.none)
                    Divider()
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(TranscriptionProvider?.some(provider))
                    }
                }
                .labelsHidden()
                .frame(width: 124)

                if selectedModel.provider == .openRouter {
                    TranscriptionModelMenu(
                        model: openRouterModelSelection,
                        accessibilityName: modelAccessibilityName
                    )
                    .frame(width: 172)
                } else {
                    AppleSpeechModelControl(language: inputSource.languageIdentifier)
                        .frame(width: 172, alignment: .trailing)
                }
            }
        }
    }

    /// What this source transcribes with, whether it follows the fixed choice
    /// or overrides it. The controls show the model that will actually run.
    private var selectedModel: TranscriptionModel {
        settings.model(for: inputSource.id)
    }

    /// Picking a provider pins the source; picking Default releases it. The
    /// selection is the stored override, not the resolved model, so a source
    /// pinned to today's fixed choice still reads as pinned.
    private var providerSelection: Binding<TranscriptionProvider?> {
        Binding {
            settings.modelOverride(for: inputSource.id)?.provider
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
        guard settings.modelOverride(for: inputSource.id) != nil else {
            return "\(languageDescription) Follows the default model."
        }
        return languageDescription
    }

    private var languageDescription: String {
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
