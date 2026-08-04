import Foundation
import PinaxCore
import XCTest
@testable import PinaxCloudSync

final class SyncMergerTests: XCTestCase, @unchecked Sendable {
    private let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let secondDate = Date(timeIntervalSince1970: 1_700_000_100)
    private let syncDate = Date(timeIntervalSince1970: 1_700_000_200)

    func testNewerUpdatedAtWinsForStableProjectID() {
        let id = UUID()
        let local = Project(id: id, name: "Local", createdAt: firstDate, updatedAt: firstDate)
        let remote = Project(id: id, name: "Remote", createdAt: firstDate, updatedAt: secondDate)

        let result = PinaxSyncMerger.merge(
            local: LibrarySnapshot(projects: [local], updatedAt: secondDate),
            remote: PinaxRemoteSnapshot(projects: [remote]),
            state: .empty,
            at: syncDate
        )

        XCTAssertEqual(result.snapshot.projects, [remote])
        XCTAssertTrue(result.mutations.projects.isEmpty)
    }

    func testEqualTimestampTieBreakIsIndependentOfLocalRemoteOrientation() {
        let id = UUID()
        let first = Project(
            id: id,
            name: "Alpha",
            createdAt: firstDate,
            updatedAt: secondDate
        )
        let second = Project(
            id: id,
            name: "Omega",
            createdAt: firstDate,
            updatedAt: secondDate
        )

        let forward = PinaxSyncMerger.merge(
            local: LibrarySnapshot(projects: [first], updatedAt: secondDate),
            remote: PinaxRemoteSnapshot(projects: [second]),
            state: .empty,
            at: syncDate
        )
        let reversed = PinaxSyncMerger.merge(
            local: LibrarySnapshot(projects: [second], updatedAt: secondDate),
            remote: PinaxRemoteSnapshot(projects: [first]),
            state: .empty,
            at: syncDate
        )

        XCTAssertEqual(forward.snapshot.projects, reversed.snapshot.projects)
    }

    func testPersistedBaselineTurnsMissingLocalRecordIntoTombstone() throws {
        let inspiration = try makeInspiration(updatedAt: firstDate)
        let state = PinaxSyncState(
            baselineInspirationIDs: [inspiration.id],
            lastSuccessfulSyncAt: secondDate
        )

        let result = PinaxSyncMerger.merge(
            local: .empty(at: secondDate),
            remote: PinaxRemoteSnapshot(inspirations: [inspiration]),
            state: state,
            at: syncDate
        )

        XCTAssertTrue(result.snapshot.inspirations.isEmpty)
        XCTAssertEqual(
            result.state.tombstones,
            [PinaxSyncTombstone(kind: .inspiration, id: inspiration.id, deletedAt: syncDate)]
        )
        XCTAssertEqual(result.mutations.tombstones, result.state.tombstones)
    }

    func testNewerTombstonePreventsStaleRecordResurrection() throws {
        let inspiration = try makeInspiration(updatedAt: firstDate)
        let tombstone = PinaxSyncTombstone(
            kind: .inspiration,
            id: inspiration.id,
            deletedAt: secondDate
        )

        let result = PinaxSyncMerger.merge(
            local: LibrarySnapshot(inspirations: [inspiration], updatedAt: secondDate),
            remote: PinaxRemoteSnapshot(tombstones: [tombstone]),
            state: .empty,
            at: syncDate
        )

        XCTAssertTrue(result.snapshot.inspirations.isEmpty)
        XCTAssertEqual(result.state.tombstones, [tombstone])
        XCTAssertTrue(result.mutations.isEmpty)
    }

    func testRecordEditedAfterOlderTombstoneWinsByUpdatedAt() throws {
        let inspiration = try makeInspiration(updatedAt: secondDate)
        let tombstone = PinaxSyncTombstone(
            kind: .inspiration,
            id: inspiration.id,
            deletedAt: firstDate
        )

        let result = PinaxSyncMerger.merge(
            local: LibrarySnapshot(inspirations: [inspiration], updatedAt: secondDate),
            remote: PinaxRemoteSnapshot(tombstones: [tombstone]),
            state: .empty,
            at: syncDate
        )

        XCTAssertEqual(result.snapshot.inspirations, [inspiration])
        XCTAssertTrue(result.state.tombstones.isEmpty)
        XCTAssertEqual(result.mutations.inspirations, [inspiration])
    }

    func testCanonicalURLDeduplicatesDifferentIDsAndTombstonesLoser() throws {
        let local = try makeInspiration(
            url: "https://twitter.com/designer/status/123?s=20",
            title: "Old",
            updatedAt: firstDate
        )
        let remote = try makeInspiration(
            url: "https://x.com/designer/status/123/photo/1",
            title: "New",
            updatedAt: secondDate
        )

        let result = PinaxSyncMerger.merge(
            local: LibrarySnapshot(inspirations: [local], updatedAt: secondDate),
            remote: PinaxRemoteSnapshot(inspirations: [remote]),
            state: .empty,
            at: syncDate
        )

        XCTAssertEqual(result.snapshot.inspirations.count, 1)
        XCTAssertEqual(result.snapshot.inspirations[0].id, remote.id)
        XCTAssertEqual(
            result.snapshot.inspirations[0].canonicalURL.absoluteString,
            "https://x.com/i/status/123"
        )
        XCTAssertEqual(result.canonicalDuplicatesRemoved, 1)
        XCTAssertEqual(
            result.state.tombstones,
            [PinaxSyncTombstone(kind: .inspiration, id: local.id, deletedAt: syncDate)]
        )
    }

    func testMissingProjectReferenceMovesInspirationToGeneral() throws {
        let missingProjectID = UUID()
        let inspiration = try makeInspiration(
            projectID: missingProjectID,
            updatedAt: firstDate
        )
        let deletion = PinaxSyncTombstone(
            kind: .project,
            id: missingProjectID,
            deletedAt: secondDate
        )

        let result = PinaxSyncMerger.merge(
            local: LibrarySnapshot(inspirations: [inspiration], updatedAt: secondDate),
            remote: PinaxRemoteSnapshot(tombstones: [deletion]),
            state: .empty,
            at: syncDate
        )

        XCTAssertNil(result.snapshot.inspirations[0].projectID)
        XCTAssertEqual(result.snapshot.inspirations[0].updatedAt, secondDate)
        XCTAssertEqual(result.mutations.inspirations.count, 1)
    }

    func testLocalImagePointerIsNotRemoteMetadataButMissingAssetQueuesUpload() throws {
        let inspiration = try makeInspiration(
            localImageFilename: "image.jpg",
            updatedAt: firstDate
        )
        var remoteCopy = inspiration
        remoteCopy.localImageFilename = nil

        let missingAsset = PinaxSyncMerger.merge(
            local: LibrarySnapshot(inspirations: [inspiration], updatedAt: firstDate),
            remote: PinaxRemoteSnapshot(inspirations: [remoteCopy]),
            state: .empty,
            at: syncDate
        )
        let existingAsset = PinaxSyncMerger.merge(
            local: LibrarySnapshot(inspirations: [inspiration], updatedAt: firstDate),
            remote: PinaxRemoteSnapshot(
                inspirations: [remoteCopy],
                assetBackedInspirationIDs: [inspiration.id]
            ),
            state: .empty,
            at: syncDate
        )

        XCTAssertEqual(missingAsset.mutations.inspirations.map(\.id), [inspiration.id])
        XCTAssertTrue(existingAsset.mutations.inspirations.isEmpty)
    }

    func testMaterializedRemoteAssetPointerSurvivesEqualMetadataMerge() throws {
        var local = try makeInspiration(updatedAt: firstDate)
        local.localImageFilename = nil
        var remote = local
        remote.localImageFilename = "downloaded.jpg"

        let result = PinaxSyncMerger.merge(
            local: LibrarySnapshot(inspirations: [local], updatedAt: firstDate),
            remote: PinaxRemoteSnapshot(
                inspirations: [remote],
                assetBackedInspirationIDs: [remote.id]
            ),
            state: .empty,
            at: syncDate
        )

        XCTAssertEqual(result.snapshot.inspirations[0].localImageFilename, "downloaded.jpg")
        XCTAssertTrue(result.mutations.inspirations.isEmpty)
    }

    private func makeInspiration(
        id: UUID = UUID(),
        url: String = "https://example.com/design",
        title: String = "Design",
        projectID: Project.ID? = nil,
        localImageFilename: String? = nil,
        updatedAt: Date
    ) throws -> Inspiration {
        let url = try XCTUnwrap(URL(string: url))
        return Inspiration(
            id: id,
            source: .web,
            url: url,
            canonicalURL: try CanonicalURL.canonicalize(url),
            title: title,
            localImageFilename: localImageFilename,
            projectID: projectID,
            createdAt: firstDate,
            updatedAt: updatedAt
        )
    }
}
