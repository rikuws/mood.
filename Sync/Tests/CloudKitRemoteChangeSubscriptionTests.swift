import CloudKit
import XCTest
@testable import PinaxCloudSync

final class CloudKitRemoteChangeSubscriptionTests: XCTestCase, @unchecked Sendable {
    private let zoneID = CKRecordZone.ID(
        zoneName: CloudKitSyncBackend.defaultZoneName,
        ownerName: CKCurrentUserDefaultName
    )
    private let subscriptionID = CloudKitSyncBackend.remoteChangeSubscriptionID

    func testMissingSubscriptionCreatesSilentZoneSubscription() async throws {
        let database = FakeSubscriptionDatabase()
        let registrar = makeRegistrar(database: database)

        try await registrar.ensure()

        let state = await database.state()
        XCTAssertEqual(state.fetches, 1)
        XCTAssertEqual(state.saves, 1)
        XCTAssertEqual(state.subscriptionID, subscriptionID)
        XCTAssertEqual(state.zoneID, zoneID)
        XCTAssertTrue(state.sendsContentAvailable)
        XCTAssertFalse(state.hasVisibleDelivery)
    }

    func testCorrectExistingSubscriptionIsNotSavedAgain() async throws {
        let existing = desiredSubscription()
        let database = FakeSubscriptionDatabase(existing: existing)
        let registrar = makeRegistrar(database: database)

        try await registrar.ensure()
        try await registrar.ensure()

        let state = await database.state()
        XCTAssertEqual(state.fetches, 1)
        XCTAssertEqual(state.saves, 0)
    }

    func testExistingSubscriptionWithoutSilentDeliveryIsRepaired() async throws {
        let existing = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )
        existing.notificationInfo = CKSubscription.NotificationInfo()
        let database = FakeSubscriptionDatabase(existing: existing)
        let registrar = makeRegistrar(database: database)

        try await registrar.ensure()

        let state = await database.state()
        XCTAssertEqual(state.saves, 1)
        XCTAssertTrue(state.sendsContentAvailable)
        XCTAssertFalse(state.hasVisibleDelivery)
    }

    func testConcurrentEnsureCallsShareOneCloudKitRequest() async throws {
        let database = FakeSubscriptionDatabase(fetchDelay: .milliseconds(40))
        let registrar = makeRegistrar(database: database)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try await registrar.ensure()
                }
            }
            try await group.waitForAll()
        }

        let state = await database.state()
        XCTAssertEqual(state.fetches, 1)
        XCTAssertEqual(state.saves, 1)
    }

    func testPerSubscriptionFailureIsSurfaced() async {
        let database = FakeSubscriptionDatabase(fetchItemFailure: TestFailure.fetch)
        let registrar = makeRegistrar(database: database)

        do {
            try await registrar.ensure()
            XCTFail("Expected subscription preparation to throw")
        } catch let error as PinaxSyncBackendError {
            guard case .operationFailed(let message) = error else {
                return XCTFail("Expected operationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("checking the remote-change subscription"))
        } catch {
            XCTFail("Expected PinaxSyncBackendError, got \(error)")
        }
    }

    private func makeRegistrar(
        database: FakeSubscriptionDatabase
    ) -> CloudKitRemoteChangeSubscriptionRegistrar {
        CloudKitRemoteChangeSubscriptionRegistrar(
            database: database,
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )
    }

    private func desiredSubscription() -> CKRecordZoneSubscription {
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        return subscription
    }
}

private enum TestFailure: Error {
    case fetch
}

private actor FakeSubscriptionDatabase: CloudKitSubscriptionDatabase {
    struct State: Sendable {
        let fetches: Int
        let saves: Int
        let subscriptionID: String?
        let zoneID: CKRecordZone.ID?
        let sendsContentAvailable: Bool
        let hasVisibleDelivery: Bool
    }

    private var existing: CKSubscription?
    private let fetchDelay: Duration?
    private let fetchItemFailure: (any Error)?
    private var fetches = 0
    private var saves = 0

    init(
        existing: CKSubscription? = nil,
        fetchDelay: Duration? = nil,
        fetchItemFailure: (any Error)? = nil
    ) {
        self.existing = existing
        self.fetchDelay = fetchDelay
        self.fetchItemFailure = fetchItemFailure
    }

    func subscriptions(
        for ids: [CKSubscription.ID]
    ) async throws -> [CKSubscription.ID: Result<CKSubscription, any Error>] {
        fetches += 1
        if let fetchDelay {
            try await Task.sleep(for: fetchDelay)
        }
        return Dictionary(uniqueKeysWithValues: ids.map { id in
            if let fetchItemFailure {
                return (id, .failure(fetchItemFailure))
            }
            if let existing, existing.subscriptionID == id {
                return (id, .success(existing))
            }
            return (id, .failure(CKError(.unknownItem)))
        })
    }

    func modifySubscriptions(
        saving subscriptionsToSave: [CKSubscription],
        deleting subscriptionIDsToDelete: [CKSubscription.ID]
    ) async throws -> (
        saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>],
        deleteResults: [CKSubscription.ID: Result<Void, any Error>]
    ) {
        saves += subscriptionsToSave.count
        if let subscription = subscriptionsToSave.first {
            existing = subscription
        }
        return (
            saveResults: Dictionary(
                uniqueKeysWithValues: subscriptionsToSave.map {
                    ($0.subscriptionID, .success($0))
                }
            ),
            deleteResults: Dictionary(
                uniqueKeysWithValues: subscriptionIDsToDelete.map { ($0, .success(())) }
            )
        )
    }

    func state() -> State {
        let zoneSubscription = existing as? CKRecordZoneSubscription
        let info = existing?.notificationInfo
        return State(
            fetches: fetches,
            saves: saves,
            subscriptionID: existing?.subscriptionID,
            zoneID: zoneSubscription?.zoneID,
            sendsContentAvailable: info?.shouldSendContentAvailable == true,
            hasVisibleDelivery: info?.alertBody != nil
                || info?.soundName != nil
                || info?.shouldBadge == true
        )
    }
}
