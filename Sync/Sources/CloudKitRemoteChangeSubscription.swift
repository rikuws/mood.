import CloudKit
import Foundation

/// Optional capability implemented by sync transports that can arrange for
/// remote-change hints. Foreground synchronization remains the reliability
/// fallback because background pushes are best-effort.
public protocol PinaxRemoteChangeSubscriptionProviding: Sendable {
    func ensureRemoteChangeSubscription() async throws
}

protocol CloudKitSubscriptionDatabase: Sendable {
    func subscriptions(
        for ids: [CKSubscription.ID]
    ) async throws -> [CKSubscription.ID: Result<CKSubscription, any Error>]

    func modifySubscriptions(
        saving subscriptionsToSave: [CKSubscription],
        deleting subscriptionIDsToDelete: [CKSubscription.ID]
    ) async throws -> (
        saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>],
        deleteResults: [CKSubscription.ID: Result<Void, any Error>]
    )
}

extension CKDatabase: CloudKitSubscriptionDatabase {}

/// Installs one silent record-zone subscription under a deterministic ID.
/// The fixed ID makes setup idempotent across launches and devices.
actor CloudKitRemoteChangeSubscriptionRegistrar {
    private let database: any CloudKitSubscriptionDatabase
    private let zoneID: CKRecordZone.ID
    private let subscriptionID: CKSubscription.ID
    private var isReady = false
    private var activeTask: Task<Void, any Error>?

    init(
        database: any CloudKitSubscriptionDatabase,
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) {
        self.database = database
        self.zoneID = zoneID
        self.subscriptionID = subscriptionID
    }

    func ensure() async throws {
        if isReady { return }
        if let activeTask {
            return try await activeTask.value
        }

        let database = database
        let zoneID = zoneID
        let subscriptionID = subscriptionID
        let task = Task<Void, any Error> {
            try await Self.installIfNeeded(
                database: database,
                zoneID: zoneID,
                subscriptionID: subscriptionID
            )
        }
        activeTask = task

        do {
            try await task.value
            isReady = true
            activeTask = nil
        } catch {
            activeTask = nil
            throw error
        }
    }

    private static func installIfNeeded(
        database: any CloudKitSubscriptionDatabase,
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        let results: [CKSubscription.ID: Result<CKSubscription, any Error>]
        do {
            results = try await database.subscriptions(for: [subscriptionID])
        } catch {
            throw translated(error, operation: "checking the remote-change subscription")
        }

        guard let result = results[subscriptionID] else {
            throw PinaxSyncBackendError.operationFailed(
                "CloudKit returned no result while checking the remote-change subscription."
            )
        }

        switch result {
        case .success(let existing):
            guard let zoneSubscription = existing as? CKRecordZoneSubscription,
                  zoneSubscription.zoneID == zoneID else {
                throw PinaxSyncBackendError.operationFailed(
                    "The Pinax CloudKit subscription ID is already used by another subscription."
                )
            }
            if zoneSubscription.notificationInfo?.shouldSendContentAvailable == true,
               hasOnlySilentDelivery(zoneSubscription.notificationInfo) {
                return
            }
            try await saveDesiredSubscription(
                database: database,
                zoneID: zoneID,
                subscriptionID: subscriptionID
            )

        case .failure(let error):
            if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                try await saveDesiredSubscription(
                    database: database,
                    zoneID: zoneID,
                    subscriptionID: subscriptionID
                )
                return
            }
            throw translated(error, operation: "checking the remote-change subscription")
        }
    }

    private static func saveDesiredSubscription(
        database: any CloudKitSubscriptionDatabase,
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let results: (
            saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>],
            deleteResults: [CKSubscription.ID: Result<Void, any Error>]
        )
        do {
            results = try await database.modifySubscriptions(
                saving: [subscription],
                deleting: []
            )
        } catch {
            throw translated(error, operation: "saving the remote-change subscription")
        }

        guard let result = results.saveResults[subscriptionID] else {
            throw PinaxSyncBackendError.operationFailed(
                "CloudKit returned no result while saving the remote-change subscription."
            )
        }
        do {
            _ = try result.get()
        } catch {
            throw translated(error, operation: "saving the remote-change subscription")
        }
    }

    private static func hasOnlySilentDelivery(_ info: CKSubscription.NotificationInfo?) -> Bool {
        guard let info else { return false }
        return info.alertBody == nil
            && info.alertLocalizationKey == nil
            && info.title == nil
            && info.titleLocalizationKey == nil
            && info.subtitle == nil
            && info.subtitleLocalizationKey == nil
            && info.soundName == nil
            && info.category == nil
            && !info.shouldBadge
            && !info.shouldSendMutableContent
    }

    private static func translated(
        _ error: any Error,
        operation: String
    ) -> PinaxSyncBackendError {
        if let error = error as? PinaxSyncBackendError {
            return error
        }
        return .operationFailed("CloudKit failed while \(operation): \(error.localizedDescription)")
    }
}
