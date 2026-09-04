import SwiftUI

/// Fixed transcription configuration and optional per-input-source routing.
struct TranscriptionSettingsView: View {
    @Bindable var settings: TranscriptionSettings
    @State private var inputSources: [KeyboardInputSource] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Provider") {
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
                }
            }
        }
        .onAppear(perform: loadInputSources)
    }

    private func loadInputSources() {
        inputSources = KeyboardInputSource.enabled
    }
}
