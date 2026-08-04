import XCTest
@testable import PinaxCloudSync

@MainActor
final class PinaxRemoteChangeHandlerTests: XCTestCase {
    func testMatchingNotificationSyncsThenReloads() async {
        let recorder = RemoteChangeRecorder(syncSucceeds: true)
        let handler = makeHandler(recorder: recorder)

        let result = await handler.handle(metadata: matchingMetadata())

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(recorder.events, ["sync", "reload"])
    }

    func testExplicitSubscriptionMismatchIsIgnored() async {
        let recorder = RemoteChangeRecorder(syncSucceeds: true)
        let handler = makeHandler(recorder: recorder)
        let metadata = PinaxRemoteChangeMetadata(
            isRecordZoneNotification: true,
            isPrivateDatabase: true,
            subscriptionID: "another.subscription",
            containerIdentifier: "iCloud.com.rikuwikman.Pinax",
            zoneName: "PinaxLibrary",
            isPruned: false
        )

        let result = await handler.handle(metadata: metadata)

        XCTAssertEqual(result, .ignored)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testPrunedMatchingZoneNotificationStillTriggersCatchUp() async {
        let recorder = RemoteChangeRecorder(syncSucceeds: true)
        let handler = makeHandler(recorder: recorder)
        let metadata = PinaxRemoteChangeMetadata(
            isRecordZoneNotification: true,
            isPrivateDatabase: true,
            subscriptionID: nil,
            containerIdentifier: nil,
            zoneName: nil,
            isPruned: true
        )

        let result = await handler.handle(metadata: metadata)

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(recorder.events, ["sync", "reload"])
    }

    func testSyncFailureStillReloadsLocalAppGroupState() async {
        let recorder = RemoteChangeRecorder(syncSucceeds: false)
        let handler = makeHandler(recorder: recorder)

        let result = await handler.handle(metadata: matchingMetadata())

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(recorder.events, ["sync", "reload"])
    }

    private func makeHandler(
        recorder: RemoteChangeRecorder
    ) -> PinaxRemoteChangeHandler {
        PinaxRemoteChangeHandler(
            containerIdentifier: "iCloud.com.rikuwikman.Pinax",
            sync: { recorder.sync() },
            reload: { recorder.reload() }
        )
    }

    private func matchingMetadata() -> PinaxRemoteChangeMetadata {
        PinaxRemoteChangeMetadata(
            isRecordZoneNotification: true,
            isPrivateDatabase: true,
            subscriptionID: CloudKitSyncBackend.remoteChangeSubscriptionID,
            containerIdentifier: "iCloud.com.rikuwikman.Pinax",
            zoneName: CloudKitSyncBackend.defaultZoneName,
            isPruned: false
        )
    }
}

@MainActor
private final class RemoteChangeRecorder {
    private let syncSucceeds: Bool
    private(set) var events: [String] = []

    init(syncSucceeds: Bool) {
        self.syncSucceeds = syncSucceeds
    }

    func sync() -> Bool {
        events.append("sync")
        return syncSucceeds
    }

    func reload() {
        events.append("reload")
    }
}
