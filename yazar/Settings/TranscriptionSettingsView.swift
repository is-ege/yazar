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

                if usesOpenRouter {
                    RowDivider()

                    SettingsRow(
                        "API key",
                        description: "Stored securely in your Mac's Keychain."
                    ) {
                        SecureField("Required", text: $settings.openRouterAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .frame(width: 220)
                    }

                    if let error = settings.apiKeyError {
                        RowDivider()
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
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

            SettingsSection("Model Routing") {
                SettingsRow(
                    "Enable model routing",
                    description: "Choose a transcription provider and model for each keyboard input source."
                ) {
                    Toggle("Enable model routing", isOn: $settings.isModelRoutingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if settings.isModelRoutingEnabled {
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

    private var usesOpenRouter: Bool {
        if settings.provider == .openRouter { return true }
        guard settings.isModelRoutingEnabled else { return false }
        return inputSources.contains {
            settings.model(for: $0.id).provider == .openRouter
        }
    }

    private func loadInputSources() {
        inputSources = KeyboardInputSource.enabled
    }
}
