import Foundation
import XCTest
@testable import PinaxCore

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testStoreMutationsRefreshObservableSnapshotAndFiltering() async throws {
        let repository = try makeRepository()
        let store = LibraryStore(repository: repository)
        await store.reload()
        let project = try await store.createProject(name: "iOS")
        _ = try await store.capture(
            CapturePayload(
                source: .x,
                url: URL(string: "https://x.com/a/status/1")!,
                title: "Settings animation",
                projectID: project.id
            )
        )
        _ = try await store.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/grid")!,
                title: "Editorial grid"
            )
        )

        XCTAssertEqual(store.counts.total, 2)
        store.scope = .project(project.id)
        XCTAssertEqual(store.visibleInspirations.map(\.title), ["Settings animation"])
        store.searchText = "missing"
        XCTAssertTrue(store.visibleInspirations.isEmpty)
        XCTAssertNil(store.lastError)
    }

    func testReloadObservesCaptureWrittenByExternalRepositoryInstance() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory)
        let externalRepository = try LibraryRepository(storageDirectory: directory)
        let store = LibraryStore(repository: repository)
        await store.reload()
        XCTAssertTrue(store.inspirations.isEmpty)

        _ = try await externalRepository.capture(
            CapturePayload(source: .web, url: URL(string: "https://example.com/external")!)
        )
        await store.reload()

        XCTAssertEqual(store.inspirations.count, 1)
    }

    func testReloadKeepsLastGoodSnapshotAndPublishesError() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory)
        let store = LibraryStore(
            repository: repository,
            initialSnapshot: LibrarySnapshot(
                projects: [Project(name: "Last good")]
            )
        )
        try Data("broken".utf8).write(to: repository.libraryFileURL)

        await store.reload()

        XCTAssertEqual(store.projects.map(\.name), ["Last good"])
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isLoading)
        store.clearError()
        XCTAssertNil(store.lastError)
    }

    private func makeRepository() throws -> LibraryRepository {
        try LibraryRepository(storageDirectory: makeTemporaryDirectory())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
