import Foundation
import XCTest
@testable import PinaxCore

final class ProductIdentityTests: XCTestCase, @unchecked Sendable {
    func testVisibleAndSpokenProductNames() {
        XCTAssertEqual(ProductIdentity.displayName, "mood.")
        XCTAssertEqual(ProductIdentity.spokenName, "mood")
        XCTAssertEqual(ProductIdentity.saveActionTitle, "Save to mood.")
        XCTAssertEqual(ProductIdentity.saveActionSpokenLabel, "Save to mood")
    }

    func testLegacyStorageContractRemainsStable() {
        XCTAssertEqual(PinaxStorage.appGroupIdentifier, "group.com.rikuwikman.pinax")
        XCTAssertEqual(PinaxStorage.libraryFilename, "library.json")
        XCTAssertEqual(PinaxStorage.mediaDirectoryName, "Media")
    }

    func testPopulatedLegacyLibraryKeepsItemsAndProjectMembership() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoodUpgradeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyData = Data(
            #"{"schemaVersion":1,"projects":[{"id":"11111111-1111-1111-1111-111111111111","name":"Kitchen textures","colorHex":"\u0023A36E55","createdAt":1700000000000,"updatedAt":1700000000000}],"inspirations":[{"id":"22222222-2222-2222-2222-222222222222","source":"web","url":"https://example.com/travertine","canonicalURL":"https://example.com/travertine","title":"Warm travertine","text":"Stone, light, and quiet geometry","projectID":"11111111-1111-1111-1111-111111111111","createdAt":1700000000000,"updatedAt":1700000000000,"lastCapturedAt":1700000000000,"captureCount":1}],"updatedAt":1700000000000}"#.utf8
        )
        try legacyData.write(
            to: directory.appendingPathComponent(PinaxStorage.libraryFilename),
            options: .atomic
        )

        let repository = try LibraryRepository(storageDirectory: directory)
        let loaded = try await repository.load()

        XCTAssertEqual(loaded.projects.map(\.name), ["Kitchen textures"])
        XCTAssertEqual(loaded.inspirations.map(\.title), ["Warm travertine"])
        XCTAssertEqual(loaded.inspirations.first?.projectID, loaded.projects.first?.id)

        try await repository.save(loaded)
        let reopened = try await LibraryRepository(storageDirectory: directory).load()
        XCTAssertEqual(reopened.projects.map(\.id), loaded.projects.map(\.id))
        XCTAssertEqual(reopened.inspirations.map(\.id), loaded.inspirations.map(\.id))
        XCTAssertEqual(reopened.inspirations.first?.projectID, reopened.projects.first?.id)
    }
}
