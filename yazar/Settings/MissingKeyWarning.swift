import SwiftUI

/// A settings row saying the chosen provider has no API key stored yet, with a
/// link to the page that stores one.
///
/// It draws nothing — not even its divider — when no key is needed or one is
/// already stored, so it can sit unconditionally at the bottom of a section.
struct MissingKeyWarning: View {
    private let provider: APIProvider?
    private let credentials: Credentials
    @Binding private var page: AppPage

    init(needs provider: APIProvider?, credentials: Credentials, page: Binding<AppPage>) {
        self.provider = provider
        self.credentials = credentials
        _page = page
    }

    var body: some View {
        if let provider, credentials.key(for: provider).isEmpty {
            RowDivider()

            HStack(spacing: 6) {
                Label(
                    "\(provider.displayName) needs an API key.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

                Button("Providers") { page = .providers }
                    .buttonStyle(.link)

                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
