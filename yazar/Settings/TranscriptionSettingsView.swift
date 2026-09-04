import SwiftUI

/// Fixed transcription configuration and optional per-input-source routing.
struct TranscriptionSettingsView: View {
    @Bindable var settings: TranscriptionSettings
    let credentials: Credentials
    @Binding var page: AppPage
    @State private var inputSources: [KeyboardInputSource] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Default Provider") {
                SettingsRow("Provider", description: settings.provider.summary) {
                    Picker("Provider", selection: $settings.provider) {
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }

                if settings.provider == .openRouter {
                    RowDivider()

                    SettingsRow(
                        "Model",
                        description: "OpenRouter model used when no input-source route replaces it."
                    ) {
                        TranscriptionModelMenu(
                            model: $settings.openRouterModel,
                            accessibilityName: "Default OpenRouter model"
                        )
                        .frame(width: 220)
                    }
                }

                MissingKeyWarning(
                    needs: settings.provider.requiredKey,
                    credentials: credentials,
                    page: $page
                )
            }

            SettingsSection("Language") {
                SettingsRow("Language", description: settings.provider.languageHint) {
                    TextField(settings.provider.languagePlaceholder, text: $settings.language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                if settings.provider == .appleSpeech {
                    RowDivider()

                    SettingsRow(
                        "Apple Speech model",
                        description: "On-device model used by the fixed configuration."
                    ) {
                        AppleSpeechModelControl(language: settings.optionalLanguage)
                            .frame(width: 220, alignment: .trailing)
                    }
                }
            }

            SettingsSection("Input Source Routing") {
                SettingsRow(
                    "Enable routing",
                    description: "Choose a provider and model for each keyboard input source, and transcribe in that source's own language."
                ) {
                    Toggle("Enable routing", isOn: $settings.isInputSourceRoutingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if settings.isInputSourceRoutingEnabled {
                    if inputSources.isEmpty {
                        RowDivider()
                        Label(
                            "No enabled keyboard input sources were found.",
                            systemImage: "keyboard"
                        )
                        .foregroundStyle(.secondary)
                        .padding(12)
                    } else {
                        ForEach(inputSources) { inputSource in
                            RowDivider()
                            ModelRoutingRow(settings: settings, inputSource: inputSource)
                        }
                    }

                    MissingKeyWarning(
                        needs: routedKey,
                        credentials: credentials,
                        page: $page
                    )
                }
            }
        }
        .onAppear(perform: loadInputSources)
    }

    /// A key a pinned input source needs that the default provider does not, so
    /// the two sections never warn about the same missing key twice.
    private var routedKey: APIProvider? {
        inputSources
            .compactMap { settings.modelOverride(for: $0.id)?.provider.requiredKey }
            .first { $0 != settings.provider.requiredKey }
    }

    private func loadInputSources() {
        inputSources = KeyboardInputSource.enabled
    }
}
