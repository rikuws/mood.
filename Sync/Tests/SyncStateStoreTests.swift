import Foundation
import XCTest
@testable import PinaxCloudSync

final class SyncStateStoreTests: XCTestCase, @unchecked Sendable {
    func testStateRoundTripsAcrossStoreInstancesAndKeepsNewestTombstone() async throws {
        let directory = try temporaryDirectory()
        let first = try PinaxSyncStateStore(storageDirectory: directory)
        let second = try PinaxSyncStateStore(storageDirectory: directory)
        let id = UUID()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_100)
        let state = PinaxSyncState(
            baselineInspirationIDs: [id],
            tombstones: [
                PinaxSyncTombstone(kind: .inspiration, id: id, deletedAt: oldDate),
                PinaxSyncTombstone(kind: .inspiration, id: id, deletedAt: newDate),
            ],
            lastSuccessfulSyncAt: newDate
        )

        try await first.save(state)
        let loaded = try await second.load()

        XCTAssertEqual(loaded.baselineInspirationIDs, [id])
        XCTAssertEqual(
            loaded.tombstones,
            [PinaxSyncTombstone(kind: .inspiration, id: id, deletedAt: newDate)]
        )
        XCTAssertEqual(loaded.lastSuccessfulSyncAt, newDate)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxSyncStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
