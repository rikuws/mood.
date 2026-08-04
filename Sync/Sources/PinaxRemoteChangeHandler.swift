import CloudKit
import Foundation

public enum PinaxRemoteChangeHandlingResult: Equatable, Sendable {
    case ignored
    case newData
    case failed
}

struct PinaxRemoteChangeMetadata: Equatable, Sendable {
    let isRecordZoneNotification: Bool
    let isPrivateDatabase: Bool
    let subscriptionID: String?
    let containerIdentifier: String?
    let zoneName: String?
    let isPruned: Bool
}

/// Validates CloudKit push hints and performs the same full reconciliation used
/// by foreground sync. A push contains no trusted data; it only tells Pinax to
/// ask the private database for the current zone contents.
@MainActor
public struct PinaxRemoteChangeHandler {
    private let expectedSubscriptionID: String
    private let expectedContainerIdentifier: String
    private let expectedZoneName: String
    private let sync: @MainActor @Sendable () async -> Bool
    private let reload: @MainActor @Sendable () async -> Void

    public init(
        subscriptionID: String = CloudKitSyncBackend.remoteChangeSubscriptionID,
        containerIdentifier: String,
        zoneName: String = CloudKitSyncBackend.defaultZoneName,
        sync: @escaping @MainActor @Sendable () async -> Bool,
        reload: @escaping @MainActor @Sendable () async -> Void
    ) {
        expectedSubscriptionID = subscriptionID
        expectedContainerIdentifier = containerIdentifier
        expectedZoneName = zoneName
        self.sync = sync
        self.reload = reload
    }

    public func handle(
        remoteNotification userInfo: [AnyHashable: Any]
    ) async -> PinaxRemoteChangeHandlingResult {
        guard let notification = CKNotification(
            fromRemoteNotificationDictionary: userInfo
        ) else {
            return .ignored
        }

        let zoneNotification = notification as? CKRecordZoneNotification
        let metadata = PinaxRemoteChangeMetadata(
            isRecordZoneNotification: notification.notificationType == .recordZone,
            isPrivateDatabase: zoneNotification?.databaseScope == .private,
            subscriptionID: notification.subscriptionID,
            containerIdentifier: notification.containerIdentifier,
            zoneName: zoneNotification?.recordZoneID?.zoneName,
            isPruned: notification.isPruned
        )
        return await handle(metadata: metadata)
    }

    func handle(
        metadata: PinaxRemoteChangeMetadata
    ) async -> PinaxRemoteChangeHandlingResult {
        guard Self.isRelevant(
            metadata,
            expectedSubscriptionID: expectedSubscriptionID,
            expectedContainerIdentifier: expectedContainerIdentifier,
            expectedZoneName: expectedZoneName
        ) else {
            return .ignored
        }

        let succeeded = await sync()
        await reload()
        return succeeded ? .newData : .failed
    }

    static func isRelevant(
        _ metadata: PinaxRemoteChangeMetadata,
        expectedSubscriptionID: String,
        expectedContainerIdentifier: String,
        expectedZoneName: String
    ) -> Bool {
        guard metadata.isRecordZoneNotification, metadata.isPrivateDatabase else {
            return false
        }
        guard matchesOrWasPruned(
            metadata.subscriptionID,
            expected: expectedSubscriptionID,
            isPruned: metadata.isPruned
        ) else {
            return false
        }
        guard matchesOrWasPruned(
            metadata.containerIdentifier,
            expected: expectedContainerIdentifier,
            isPruned: metadata.isPruned
        ) else {
            return false
        }
        return matchesOrWasPruned(
            metadata.zoneName,
            expected: expectedZoneName,
            isPruned: metadata.isPruned
        )
    }

    private static func matchesOrWasPruned(
        _ actual: String?,
        expected: String,
        isPruned: Bool
    ) -> Bool {
        if let actual { return actual == expected }
        return isPruned
    }
}
