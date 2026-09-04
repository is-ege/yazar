import AppKit
import Observation
import SwiftUI

@main
struct YazarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Yazar", systemImage: appDelegate.menuBarIcon) {
            Button("Open Yazar") {
                appDelegate.showApp()
            }

            if appDelegate.isMeetingsEnabled {
                Button(appDelegate.meetingActionTitle) {
                    appDelegate.toggleMeeting()
                }
                .disabled(appDelegate.isMeetingBusy)

                Button("Meetings") {
                    appDelegate.showMeetings()
                }
            }

            Divider()

            Button("Quit Yazar") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings: Settings
    private let permissions = Permissions()
    private let yazar: Yazar
    private let store: MeetingStore
    private let session: MeetingSession
    private let notesMaker: MeetingNotesMaker
    private let transcriptMaker: MeetingTranscriptMaker
    private let meetingsWindow: MeetingsWindowController
    private var selectedPage = AppPage.general
    private var overlayPanel: OverlayPanel?
    private var appWindow: NSWindow?

    override init() {
        let settings = Settings()
        self.settings = settings
        yazar = Yazar(settings: settings)
        let store = MeetingStore()
        self.store = store
        let notesMaker = MeetingNotesMaker(store: store, settings: settings)
        self.notesMaker = notesMaker
        let session = MeetingSession(store: store, settings: settings, notesMaker: notesMaker)
        self.session = session
        let transcriptMaker = MeetingTranscriptMaker(
            store: store,
            settings: settings,
            notesMaker: notesMaker
        )
        self.transcriptMaker = transcriptMaker
        meetingsWindow = MeetingsWindowController(
            store: store,
            session: session,
            notesMaker: notesMaker,
            transcriptMaker: transcriptMaker
        )
        super.init()
        permissions.refresh()
    }

    /// Dictation wins the icon while it is happening: it lasts seconds and the
    /// user is watching for it. A meeting runs for an hour underneath.
    var menuBarIcon: String {
        switch yazar.state {
        case .warmingUp, .recording: "waveform.circle.fill"
        case .transcribing: "ellipsis.circle"
        case .error: "exclamationmark.circle"
        case .idle, .noSpeech: meetingIcon
        }
    }

    /// A meeting outlives the icon states dictation uses, so it gets the icon
    /// whenever dictation is not using it, transcription included: the tail of a
    /// meeting is still work the user is waiting on.
    private var meetingIcon: String {
        switch session.state {
        case .starting, .recording, .stopping: "record.circle"
        case .transcribing: "ellipsis.circle"
        case .idle, .failed: "waveform"
        }
    }

    var meetingActionTitle: String {
        session.isRecording ? "Stop Meeting" : "Start Meeting"
    }

    var isMeetingsEnabled: Bool {
        settings.meetingsEnabled
    }

    /// Start and stop both await the stream, and the transcript is still being
    /// finished after that, so the menu item is held shut rather than letting a
    /// second press land mid-transition.
    var isMeetingBusy: Bool {
        switch session.state {
        case .starting, .stopping, .transcribing: true
        case .idle, .recording, .failed: false
        }
    }

    func toggleMeeting() {
        Task { @MainActor in
            if session.isRecording {
                await session.stop()
            } else {
                await session.start()
                if case .failed(let message) = session.state {
                    presentMeetingFailure(message)
                }
            }
        }
    }

    /// Meetings are started from the menu bar, where there is nowhere to show an
    /// error, and the dictation overlay belongs to dictation.
    private func presentMeetingFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Yazar could not start the meeting."
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    /// The system requirements for the trigger selected right now. Keeping this
    /// beside engine startup means polling only has to publish system state.
    private var isReadyToStart: Bool {
        permissions.allGranted &&
            (!settings.dictationTrigger.usesFn || permissions.fnConfigured)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !activateExistingInstance() else { return }

        // Safe only because a single instance is enforced above: with no other
        // process able to hold it, an open segment is orphaned rather than
        // merely unclaimed.
        store.closeOrphanedMeetings()

        if isReadyToStart {
            startEngine()
        } else {
            showApp(page: .systemAccess)
            permissions.startPolling()
            startEngineWhenReady()
        }
    }

    /// A meeting in flight is closed before the process goes, which is the
    /// graceful half of recovery. The scan on next launch is the other half, for
    /// the quits that never reach here.
    func applicationWillTerminate(_ notification: Notification) {
        yazar.stop()
        session.endForTermination()
    }

    func showMeetings() {
        meetingsWindow.show()
    }

    /// Hands off to the copy of Yazar already running and quits.
    ///
    /// Two instances would fight over the dictation trigger and, once meetings
    /// record, over the store. The exit is logged because a build launched from
    /// Xcode alongside the installed app disappears silently otherwise, and that
    /// is baffling rather than obviously deliberate.
    private func activateExistingInstance() -> Bool {
        // A test run hosts the app in order to load the test bundle into it, and
        // the developer's own copy is normally running at the same time. Quitting
        // here takes the test runner with it before it can connect, so the whole
        // suite fails with an early exit that says nothing about the tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != mine }
        guard let existing = others.first else { return false }

        NSLog("Yazar is already running (pid %d); activating it and quitting.", existing.processIdentifier)
        existing.activate()
        NSApp.terminate(nil)
        return true
    }

    func showApp(page: AppPage? = nil) {
        if let page {
            selectedPage = page
        }

        if let appWindow {
            appWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: YazarView.minimumSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Yazar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenDisallowsTiling)
        window.center()
        let hostingView = NSHostingView(
            rootView: YazarView(
                settings: settings,
                permissions: permissions,
                yazar: yazar,
                store: store,
                session: session,
                selection: Binding(
                    get: { [weak self] in self?.selectedPage ?? .general },
                    set: { [weak self] in self?.selectedPage = $0 }
                )
            )
        )
        hostingView.sizingOptions = [.minSize]
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.maxSize = maximumFrameSize(for: window)
        window.delegate = self
        appWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let maximumSize = maximumFrameSize(for: sender)
        return NSSize(
            width: min(frameSize.width, maximumSize.width),
            height: min(frameSize.height, maximumSize.height)
        )
    }

    private func maximumFrameSize(for window: NSWindow) -> NSSize {
        window.frameRect(
            forContentRect: NSRect(origin: .zero, size: YazarView.maximumSize)
        ).size
    }

    /// Builds the overlay once and claims the hot key. Safe to call again after a
    /// failed attempt, since HotKey.start() is a no-op once the tap exists.
    private func startEngine() {
        permissions.stopPolling()
        if overlayPanel == nil {
            overlayPanel = OverlayPanel(yazar: yazar, settings: settings)
        }
        do {
            try yazar.start()
        } catch {
            yazar.show(.hotKey(error))
        }
    }

    /// Grants can land while Yazar is already running, so the engine starts in
    /// place rather than making the user relaunch. The Relaunch button on the
    /// permissions screen stays as the fallback for when the tap still fails.
    private func startEngineWhenReady() {
        withObservationTracking {
            _ = isReadyToStart
        } onChange: { [weak self] in
            // onChange fires before the new value lands, so re-read on the main actor.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isReadyToStart {
                    startEngine()
                } else {
                    startEngineWhenReady()
                }
            }
        }
    }
}
