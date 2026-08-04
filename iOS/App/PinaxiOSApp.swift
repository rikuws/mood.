import OSLog
import PinaxCloudSync
import PinaxCore
import SwiftUI
import UIKit

@main
struct PinaxiOSApp: App {
    @UIApplicationDelegateAdaptor(PinaxiOSAppDelegate.self) private var appDelegate
    @State private var store: LibraryStore?
    @State private var syncCoordinator: PinaxSyncCoordinator?
    private let initializationError: String?

    init() {
        do {
            let repository = try LibraryRepository.appGroup()
            let store = LibraryStore(repository: repository)
            _store = State(initialValue: store)
            PinaxiOSAppDelegate.libraryStore = store
            let backend = CloudKitSyncBackend(
                containerIdentifier: "iCloud.com.rikuwikman.Pinax",
                mediaDirectory: repository.mediaDirectory
            )
            let engine = try PinaxSyncEngine(repository: repository, backend: backend)
            let syncCoordinator = PinaxSyncCoordinator(
                engine: engine,
                remoteChangeSubscriptionProvider: backend
            )
            _syncCoordinator = State(initialValue: syncCoordinator)
            PinaxiOSAppDelegate.syncCoordinator = syncCoordinator
            initializationError = nil
        } catch {
            _store = State(initialValue: nil)
            _syncCoordinator = State(initialValue: nil)
            PinaxiOSAppDelegate.libraryStore = nil
            PinaxiOSAppDelegate.syncCoordinator = nil
            initializationError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let store, let syncCoordinator {
                IOSLibraryView(store: store, syncCoordinator: syncCoordinator)
                    .task {
                        let repairedCount = await store.enrichMissingXPreviews()
                        guard repairedCount > 0 else { return }
                        _ = await syncCoordinator.sync()
                        await store.reload()
                    }
            } else {
                StorageUnavailableView(
                    message: initializationError
                        ?? "Pinax couldn't open its shared library."
                )
            }
        }
    }
}

@MainActor
final class PinaxiOSAppDelegate: NSObject, UIApplicationDelegate {
    static var libraryStore: LibraryStore?
    static var syncCoordinator: PinaxSyncCoordinator?

    private let logger = Logger(
        subsystem: "com.rikuwikman.Pinax",
        category: "cloud-push"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        Task { @MainActor in
            guard let coordinator = Self.syncCoordinator else { return }
            if await coordinator.prepareForRemoteChanges() {
                logger.notice("Prepared CloudKit background updates")
            } else {
                logger.error("Could not prepare CloudKit background updates")
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        logger.notice("Registered for CloudKit background updates")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        logger.error(
            "Could not register for CloudKit background updates: \(error.localizedDescription)"
        )
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let result = await remoteChangeHandler.handle(remoteNotification: userInfo)
        switch result {
        case .ignored:
            logger.debug("Ignored unrelated remote notification")
            return .noData
        case .newData:
            logger.notice("Applied CloudKit background update")
            return .newData
        case .failed:
            logger.error("CloudKit background update failed")
            return .failed
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
}

private struct StorageUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Library unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
            Text("Pinax and Save to Pinax must both use the App Group \(PinaxStorage.appGroupIdentifier).")
        }
        .padding(24)
    }
}
