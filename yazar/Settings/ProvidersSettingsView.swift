import SwiftUI

/// The API keys Yazar stores, one card per service.
struct ProvidersSettingsView: View {
    let credentials: Credentials

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(APIProvider.allCases) { provider in
                SettingsSection(provider.displayName) {
                    SettingsRow("API key", description: provider.keyDescription) {
                        SecureField("Required", text: key(for: provider))
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .frame(width: 220)
                    }
                }
            }

            if let error = credentials.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func key(for provider: APIProvider) -> Binding<String> {
        Binding {
            credentials.key(for: provider)
        } set: { key in
            credentials.setKey(key, for: provider)
        }
    }
}
