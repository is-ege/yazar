import SwiftUI

/// Controls access to meeting recording and its note-writing model.
struct MeetingsSettingsView: View {
    @Bindable var settings: Settings
    let store: MeetingStore
    let session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Meetings") {
                SettingsRow(
                    "Enable meeting recording",
                    description: "Record system audio during a meeting and write notes from it. Needs Screen Recording."
                ) {
                    Toggle("Enable meeting recording", isOn: $settings.meetingsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(session.isActive)
                }
            }

            if settings.meetingsEnabled {
                SettingsSection("Notes") {
                    SettingsRow(
                        "Model",
                        description: "OpenRouter model that writes the notes. Uses the OpenRouter key from the Providers page."
                    ) {
                        TextField("Required", text: $settings.openRouterNotesModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }

                    RowDivider()

                    SettingsRow(
                        "Privacy",
                        description: "The whole transcript is sent to OpenRouter to make notes. Nothing is generated on this Mac."
                    ) {
                        EmptyView()
                    }
                }

#if DEBUG
                TranscriptNotesSection(settings: settings, store: store)
#endif
            }
        }
    }
}
