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

                // Apple model status belongs to the effective route even when
                // its provider is inherited. Showing it does not pin the source.
                if case .appleSpeech = route.model {
                    AppleSpeechModelControl(language: route.language)
                        .frame(width: 172, alignment: .trailing)
                } else if isFollowingDefault,
                          case .openRouter(let model) = route.model {
                    // An inherited OpenRouter model stays read-only because
                    // editing it would silently turn inheritance into a pin.
                    Text(model)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(width: 172, alignment: .trailing)
                } else {
                    TranscriptionModelMenu(
                        model: openRouterModelSelection,
                        accessibilityName: modelAccessibilityName
                    )
                    .frame(width: 172)
                }
            }
        }
    }

    /// The same model and language dictation will use. This row only appears
    /// while routing is enabled, so route resolution includes the source.
    private var route: TranscriptionRoute {
        settings.dictationRoute(for: inputSource)
    }

    private var isFollowingDefault: Bool {
        settings.modelOverride(for: inputSource.id) == nil
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
            if case .openRouter(let model) = route.model {
                return model
            }
            return settings.openRouterModel
        } set: { model in
            settings.setModel(.openRouter(model), for: inputSource.id)
        }
    }

    private var sourceDescription: String {
        guard isFollowingDefault else { return languageDescription }
        return "\(languageDescription) Follows the default model."
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
