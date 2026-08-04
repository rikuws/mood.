import AppKit
import OSLog
import PinaxCloudSync
import PinaxCore
import PinaxNativeMessaging
import Security
import SwiftUI

@main
struct PinaxMacApp: App {
    @NSApplicationDelegateAdaptor(PinaxAppDelegate.self) private var appDelegate

    init() {
        do {
            let repository = try LibraryRepository.appGroup()
            let store = LibraryStore(repository: repository)
            PinaxAppDelegate.libraryStore = store
            if Self.hasCloudKitEntitlement {
                let backend = CloudKitSyncBackend(
                    containerIdentifier: "iCloud.com.rikuwikman.Pinax",
                    mediaDirectory: repository.mediaDirectory
                )
                let engine = try PinaxSyncEngine(repository: repository, backend: backend)
                PinaxAppDelegate.syncCoordinator = PinaxSyncCoordinator(
                    engine: engine,
                    remoteChangeSubscriptionProvider: backend
                )
            }
        } catch {
            fatalError("Pinax could not initialize its library: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        Settings {
            BrowserSetupView()
        }
        .commands {
            PinaxCommands()
        }

    }

    private static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let containers = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-container-identifiers" as CFString,
                  nil
              ) as? [String] else {
            return false
        }
        return containers.contains("iCloud.com.rikuwikman.Pinax")
    }
}

@MainActor
final class PinaxAppDelegate: NSObject, NSApplicationDelegate {
    static var libraryStore: LibraryStore?
    static var syncCoordinator: PinaxSyncCoordinator?

    private var fallbackWindowController: NSWindowController?
    private let acknowledgementStore = FileCaptureAcknowledgementStore()
    private let cloudPushLogger = Logger(
        subsystem: "com.rikuwikman.Pinax",
        category: "cloud-push"
    )
    private var receivedCaptureURL = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = NSApplication.shared
        application.registerForRemoteNotifications()
        Task { @MainActor in
            guard let coordinator = Self.syncCoordinator else { return }
            if await coordinator.prepareForRemoteChanges() {
                cloudPushLogger.notice("Prepared CloudKit background updates")
            } else {
                cloudPushLogger.error("Could not prepare CloudKit background updates")
            }
        }

        Task { @MainActor in
            guard let store = Self.libraryStore else { return }
            let repairedCount = await store.enrichMissingXPreviews()
            guard repairedCount > 0 else { return }
            if let coordinator = Self.syncCoordinator {
                _ = await coordinator.sync()
            }
            await store.reload()
        }

        let changedPolicy = application.setActivationPolicy(.regular)
        Logger(subsystem: "com.rikuwikman.Pinax", category: "lifecycle").notice(
            "Finished launching; regular policy changed=\(changedPolicy), policy=\(application.activationPolicy().rawValue)"
        )

        let isDefaultLaunch =
            notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, !self.receivedCaptureURL else { return }
                self.ensureMainWindow()
                application.activate(ignoringOtherApps: true)
            }
        }
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        cloudPushLogger.notice("Registered for CloudKit background updates")
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        cloudPushLogger.error(
            "Could not register for CloudKit background updates: \(error.localizedDescription)"
        )
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        let payload = userInfo.reduce(into: [AnyHashable: Any]()) { result, entry in
            result[AnyHashable(entry.key)] = entry.value
        }
        Task { @MainActor in
            switch await remoteChangeHandler.handle(remoteNotification: payload) {
            case .ignored:
                cloudPushLogger.debug("Ignored unrelated remote notification")
            case .newData:
                cloudPushLogger.notice("Applied CloudKit background update")
            case .failed:
                cloudPushLogger.error("CloudKit background update failed")
            }
        }
    }

    private var remoteChangeHandler: PinaxRemoteChangeHandler {
        PinaxRemoteChangeHandler(
            containerIdentifier: "iCloud.com.rikuwikman.Pinax",
            sync: {
                guard let coordinator = Self.syncCoordinator else { return false }
                return await coordinator.syncAfterRemoteChange() != nil
            },
            reload: {
                await Self.libraryStore?.reload()
            }
        )
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { ensureMainWindow() }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedCaptureURL = true
        Task { @MainActor in
            var capturedAny = false
            for url in urls {
                let requestID = CaptureDeepLink.requestID(from: url)
                do {
                    guard let store = Self.libraryStore else { return }
                    let payload = try CaptureDeepLink.payload(from: url)
                    let result = try await store.capture(payload)
                    capturedAny = true
                    if let requestID {
                        do {
                            try acknowledgementStore.write(
                                .success(
                                    itemId: result.inspiration.id.uuidString.lowercased(),
                                    duplicate: !result.inserted
                                ),
                                for: requestID
                            )
                        } catch {
                            Logger(
                                subsystem: "com.rikuwikman.Pinax",
                                category: "browser-capture"
                            ).error("Could not write capture acknowledgement: \(error.localizedDescription)")
                        }
                    }
                    NotificationCenter.default.post(
                        name: .pinaxCaptureSucceeded,
                        object: result
                    )
                } catch {
                    if let requestID {
                        try? acknowledgementStore.write(
                            .failure(code: "capture_failed", message: error.localizedDescription),
                            for: requestID
                        )
                    }
                    NotificationCenter.default.post(
                        name: .pinaxCaptureFailed,
                        object: error.localizedDescription
                    )
                }
            }

            if capturedAny, let syncCoordinator = Self.syncCoordinator {
                _ = await syncCoordinator.sync()
                await Self.libraryStore?.reload()
            }
        }
    }

    private func ensureMainWindow() {
        let logger = Logger(subsystem: "com.rikuwikman.Pinax", category: "lifecycle")
        logger.notice(
            "Ensuring main window; windows=\(NSApplication.shared.windows.count), store=\(Self.libraryStore == nil ? "missing" : "ready")"
        )
        if let existing = fallbackWindowController?.window {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            logger.notice("Using existing app-owned main window")
            return
        }

        guard let store = Self.libraryStore else { return }
        let hostingController = NSHostingController(
            rootView: MacLibraryView(store: store, syncCoordinator: Self.syncCoordinator)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pinax"
        window.minSize = NSSize(width: 820, height: 560)
        window.toolbarStyle = .unified
        window.contentViewController = hostingController
        window.setFrameAutosaveName("PinaxLibraryWindow")
        window.center()

        let controller = NSWindowController(window: window)
        fallbackWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        logger.notice(
            "Created fallback main window; visible=\(window.isVisible), number=\(window.windowNumber, privacy: .public)"
        )
    }
}

private struct PinaxCommands: Commands {
    var body: some Commands {
        CommandMenu("Inspiration") {
            Button("Save a Link…") {
                NotificationCenter.default.post(name: .pinaxQuickCapture, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("New Project…") {
                NotificationCenter.default.post(name: .pinaxNewProject, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") {
                NotificationCenter.default.post(name: .pinaxCanvasZoomIn, object: nil)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .pinaxCanvasZoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Zoom") {
                NotificationCenter.default.post(name: .pinaxCanvasZoomReset, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
