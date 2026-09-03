import SwiftUI

/// The settings window: a page list on the left, the selected page on the right.
struct YazarView: View {
    static let minimumSize = CGSize(width: 680, height: 420)
    static let maximumSize = CGSize(width: 800, height: 520)

    @Bindable var settings: Settings
    @Bindable var permissions: Permissions
    let yazar: Yazar
    let store: MeetingStore
    let session: MeetingSession
    @Binding private var selection: AppPage

    init(
        settings: Settings,
        permissions: Permissions,
        yazar: Yazar,
        store: MeetingStore,
        session: MeetingSession,
        selection: Binding<AppPage> = .constant(.dictation)
    ) {
        self.settings = settings
        self.permissions = permissions
        self.yazar = yazar
        self.store = store
        self.session = session
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            List(AppPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .safeAreaPadding(.top, 30)
            .frame(width: 160)

            Divider()

            ScrollView {
                Group {
                    switch selection {
                    case .dictation:
                        DictationSettingsView(settings: settings, yazar: yazar)
                    case .transcription:
                        TranscriptionSettingsView(settings: settings.transcription)
                    case .formatting:
                        FormattingSettingsView(formatting: settings.formatting)
                    case .meetings:
                        MeetingsSettingsView(
                            settings: settings,
                            store: store,
                            session: session
                        )
                    case .systemAccess:
                        SystemAccessSettingsView(
                            permissions: permissions,
                            settings: settings,
                            yazar: yazar
                        )
                    }
                }
                .frame(maxWidth: 620, alignment: .topLeading)
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: Self.minimumSize.width,
            maxWidth: .infinity,
            minHeight: Self.minimumSize.height,
            maxHeight: .infinity
        )
        .ignoresSafeArea(.container)
    }
}

#Preview {
    let settings = Settings()
    let store = MeetingStore()
    let notesMaker = MeetingNotesMaker(store: store, settings: settings)
    YazarView(
        settings: settings,
        permissions: Permissions(),
        yazar: Yazar(settings: settings),
        store: store,
        session: MeetingSession(store: store, settings: settings, notesMaker: notesMaker)
    )
}
