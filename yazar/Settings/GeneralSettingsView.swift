import SwiftUI

/// How dictation is triggered, captured, and what it sounds like.
struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    let yazar: Yazar

    private var audioInputs: [AudioInput] { AudioInput.available }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Activation") {
                SettingsRow(
                    "Dictation key",
                    description: "Click to rebind."
                ) {
                    TriggerRecorder(trigger: $settings.dictationTrigger, yazar: yazar)
                }

                RowDivider()

                SettingsRow(
                    "Dictation mode",
                    description: settings.dictationMode == .hold
                        ? "Hold the key while you speak; let go to transcribe."
                        : "Press once to start and again to transcribe."
                ) {
                    Picker("Dictation mode", selection: $settings.dictationMode) {
                        ForEach(DictationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }
            }

            SettingsSection("Audio") {
                SettingsRow(
                    "Audio input",
                    description: "Microphone used for dictation."
                ) {
                    Picker("Audio input", selection: $settings.audioInputID) {
                        if !settings.audioInputID.isEmpty,
                           !audioInputs.contains(where: { $0.id == settings.audioInputID }) {
                            Text("Unavailable device").tag(settings.audioInputID)
                        }
                        ForEach(audioInputs) { input in
                            Text(input.name).tag(input.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            SettingsSection("Feedback") {
                SettingsRow(
                    "Show timer",
                    description: "Show elapsed time while recording."
                ) {
                    Toggle("Show timer", isOn: $settings.showRecordingTimer)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                RowDivider()

                SettingsRow(
                    "Play sounds",
                    description: "Play feedback for recording and transcription status."
                ) {
                    Toggle("Play sounds", isOn: $settings.playSounds)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                RowDivider()

                SettingsRow(
                    "Sound theme",
                    description: "Sounds used for start, stop, cancellation, and transcription errors."
                ) {
                    Picker("Sound theme", selection: $settings.soundTheme) {
                        ForEach(SoundTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                    .disabled(!settings.playSounds)
                }
            }

#if DEBUG
            SettingsSection("Development") {
                SettingsRow(
                    "Demo mode",
                    description: "Use the microphone, wait five seconds, then paste sample text."
                ) {
                    Toggle("Demo mode", isOn: $settings.demoMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
#endif
        }
    }
}
