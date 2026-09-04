import Foundation
import XCTest
@testable import PinaxCore

final class LibraryRepositoryTests: XCTestCase, @unchecked Sendable {
    private let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    func testEmptyLibraryLoadsWithoutCreatingInvalidState() async throws {
        let repository = try makeRepository()

        let snapshot = try await repository.load()

        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertTrue(snapshot.inspirations.isEmpty)
        XCTAssertEqual(snapshot.schemaVersion, LibrarySnapshot.currentSchemaVersion)
    }

    func testCapturePersistsAndSecondRepositoryReadsSameFile() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory, clock: { self.fixedDate })
        let secondRepository = try LibraryRepository(storageDirectory: directory, clock: { self.fixedDate })
        let payload = CapturePayload(
            source: .web,
            url: URL(string: "https://example.com/design?utm_source=x")!,
            title: "Design system"
        )

        let result = try await repository.capture(payload)
        let loaded = try await secondRepository.load()

        XCTAssertTrue(result.inserted)
        XCTAssertEqual(loaded.inspirations, [result.inspiration])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path))
    }

    func testCanonicalDuplicateFillsMissingMetadataAndDoesNotDuplicate() async throws {
        let repository = try makeRepository()
        let first = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://twitter.com/artist/status/123?s=20")!
            )
        )

        let second = try await repository.capture(
            CapturePayload(
                source: .x,
                url: URL(string: "https://x.com/artist/status/123/photo/1")!,
                title: "Dashboard motion",
                text: "Great transition",
                authorName: "Artist",
                authorHandle: "@artist",
                imageURL: URL(string: "https://pbs.twimg.com/media/example.jpg")!
            )
        )
        let snapshot = try await repository.load()

        XCTAssertTrue(first.inserted)
        XCTAssertFalse(second.inserted)
        XCTAssertEqual(second.inspiration.id, first.inspiration.id)
        XCTAssertEqual(second.inspiration.source, .x)
        XCTAssertEqual(second.inspiration.title, "Dashboard motion")
        XCTAssertEqual(second.inspiration.text, "Great transition")
        XCTAssertEqual(second.inspiration.authorHandle, "artist")
        XCTAssertEqual(second.inspiration.captureCount, 2)
        XCTAssertEqual(snapshot.inspirations.count, 1)
    }

    func testExplicitGeneralCaptureMovesDuplicateOutOfProject() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "Website")
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        _ = try await repository.capture(
            CapturePayload(source: .web, url: url, projectID: project.id)
        )

        let duplicate = try await repository.capture(
            CapturePayload(
                source: .web,
                url: url,
                projectID: nil,
                assignProjectOnDuplicate: true
            )
        )

        XCTAssertFalse(duplicate.inserted)
        XCTAssertNil(duplicate.inspiration.projectID)
    }

    func testExplicitCaptureReplacesProvidedDuplicateMetadata() async throws {
        let repository = try makeRepository()
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        _ = try await repository.capture(
            CapturePayload(
                source: .web,
                url: url,
                title: "Original title",
                text: "Original note",
                authorName: "Original author"
            )
        )

        let duplicate = try await repository.capture(
            CapturePayload(
                source: .web,
                url: url,
                title: "Replacement title",
                text: "Replacement note",
                overwriteMetadataOnDuplicate: true
            )
        )

        XCTAssertFalse(duplicate.inserted)
        XCTAssertEqual(duplicate.inspiration.title, "Replacement title")
        XCTAssertEqual(duplicate.inspiration.text, "Replacement note")
        XCTAssertEqual(duplicate.inspiration.authorName, "Original author")
    }

    func testCaptureImageDataWritesRelativeMediaAsset() async throws {
        let repository = try makeRepository()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])

        let result = try await repository.capture(
            CapturePayload(
                source: .x,
                url: URL(string: "https://x.com/a/status/44")!,
                imageURL: URL(string: "https://pbs.twimg.com/media/a.jpg")!
            ),
            imageData: bytes,
            imageFileExtension: "PNG"
        )

        XCTAssertEqual(result.inspiration.localImageFilename?.hasSuffix(".png"), true)
        let localURL = repository.localImageURL(for: result.inspiration)
        let persistedBytes = try localURL.map { try Data(contentsOf: $0) }
        XCTAssertEqual(persistedBytes, bytes)
        XCTAssertEqual(localURL?.deletingLastPathComponent(), repository.mediaDirectory)
    }

    func testProjectCRUDMoveCountsAndDeleteReturnsItemsToGeneral() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "  Client site  ", colorHex: " #FF00AA ")
        let general = try await repository.capture(
            CapturePayload(source: .web, url: URL(string: "https://example.com/general")!)
        ).inspiration
        let assigned = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/project")!,
                projectID: project.id
            )
        ).inspiration

        XCTAssertEqual(project.name, "Client site")
        XCTAssertEqual(project.colorHex, "#FF00AA")
        var counts = try await repository.counts()
        XCTAssertEqual(counts.general, 1)
        XCTAssertEqual(counts[project.id], 1)

        _ = try await repository.moveInspiration(id: general.id, to: project.id)
        counts = try await repository.counts()
        XCTAssertEqual(counts.general, 0)
        XCTAssertEqual(counts[project.id], 2)

        let renamed = try await repository.updateProject(id: project.id, name: "Launch", colorHex: nil)
        XCTAssertEqual(renamed.name, "Launch")
        _ = try await repository.deleteProject(id: project.id)

        let snapshot = try await repository.load()
        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertEqual(Set(snapshot.inspirations.map(\.id)), [general.id, assigned.id])
        XCTAssertTrue(snapshot.inspirations.allSatisfy { $0.projectID == nil })
        counts = try await repository.counts()
        XCTAssertEqual(counts.general, 2)
    }

    func testProjectBackgroundPinsImageAndClearsWhenItemLeavesProject() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "Atmosphere")
        let background = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/background")!,
                imageURL: URL(string: "https://example.com/background.jpg"),
                projectID: project.id
            )
        ).inspiration

        let pinned = try await repository.setProjectBackground(
            id: project.id,
            inspirationID: background.id
        )
        XCTAssertEqual(pinned.backgroundInspirationID, background.id)

        _ = try await repository.moveInspiration(id: background.id, to: nil)
        let afterMove = try await repository.load()
        XCTAssertNil(afterMove.project(id: project.id)?.backgroundInspirationID)
    }

    func testProjectBackgroundRejectsTextOnlyAndOtherProjectImages() async throws {
        let repository = try makeRepository()
        let firstProject = try await repository.createProject(name: "First")
        let secondProject = try await repository.createProject(name: "Second")
        let textOnly = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/text")!,
                projectID: firstProject.id
            )
        ).inspiration
        let otherImage = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/other")!,
                imageURL: URL(string: "https://example.com/other.jpg"),
                projectID: secondProject.id
            )
        ).inspiration

        await XCTAssertThrowsErrorAsync(
            try await repository.setProjectBackground(
                id: firstProject.id,
                inspirationID: textOnly.id
            )
        ) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .invalidProjectBackground)
        }
        await XCTAssertThrowsErrorAsync(
            try await repository.setProjectBackground(
                id: firstProject.id,
                inspirationID: otherImage.id
            )
        ) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .invalidProjectBackground)
        }
    }

    func testSearchCoversMetadataDiacriticsAndScopes() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "Mobile")
        _ = try await repository.capture(
            CapturePayload(
                source: .x,
                url: URL(string: "https://x.com/mikko/status/77")!,
                title: "Café navigation",
                authorName: "Mikko Designer",
                projectID: project.id
            )
        )
        _ = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/cards")!,
                title: "Card grid"
            )
        )

        let cafeResults = try await repository.search(query: "CAFE")
        let projectResults = try await repository.search(query: "mikko", scope: .project(project.id))
        let generalResults = try await repository.search(query: "", scope: .general)
        let missingGeneralResults = try await repository.search(query: "mikko", scope: .general)
        XCTAssertEqual(cafeResults.count, 1)
        XCTAssertEqual(projectResults.count, 1)
        XCTAssertEqual(generalResults.count, 1)
        XCTAssertTrue(missingGeneralResults.isEmpty)
    }

    func testUpdateRecanonicalizesAndDeleteRemovesInspiration() async throws {
        let repository = try makeRepository()
        let captured = try await repository.capture(
            CapturePayload(source: .web, url: URL(string: "https://www.example.com/a?utm_source=x")!)
        ).inspiration
        var edited = captured
        edited.url = URL(string: "https://example.com/new/#detail")!
        edited.title = "  Edited  "

        let updated = try await repository.updateInspiration(edited)
        XCTAssertEqual(updated.title, "Edited")
        XCTAssertEqual(updated.canonicalURL.absoluteString, "https://example.com/new")

        let deleted = try await repository.deleteInspiration(id: captured.id)
        XCTAssertEqual(deleted.id, captured.id)
        let finalSnapshot = try await repository.load()
        XCTAssertTrue(finalSnapshot.inspirations.isEmpty)
    }

    func testDuplicateAndMissingProjectErrorsAreExplicit() async throws {
        let repository = try makeRepository()
        _ = try await repository.createProject(name: "Website")

        await XCTAssertThrowsErrorAsync(try await repository.createProject(name: " website ")) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .duplicateProjectName)
        }
        let missingID = UUID()
        await XCTAssertThrowsErrorAsync(
            try await repository.capture(
                CapturePayload(
                    source: .web,
                    url: URL(string: "https://example.com")!,
                    projectID: missingID
                )
            )
        ) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .projectNotFound(missingID))
        }
    }

    func testConcurrentRepositoriesDoNotLoseSameURLCapture() async throws {
        let directory = try makeTemporaryDirectory()
        let first = try LibraryRepository(storageDirectory: directory, clock: { self.fixedDate })
        let second = try LibraryRepository(storageDirectory: directory, clock: { self.fixedDate })
        let firstPayload = CapturePayload(
            source: .x,
            url: URL(string: "https://twitter.com/a/status/999?s=20")!,
            title: "First"
        )
        let secondPayload = CapturePayload(
            source: .x,
            url: URL(string: "https://x.com/a/status/999/photo/1")!,
            text: "Second metadata"
        )

        async let firstResult = first.capture(firstPayload)
        async let secondResult = second.capture(secondPayload)
        _ = try await (firstResult, secondResult)

        let snapshot = try await first.load()
        XCTAssertEqual(snapshot.inspirations.count, 1)
        XCTAssertEqual(snapshot.inspirations[0].captureCount, 2)
        XCTAssertEqual(snapshot.inspirations[0].title, "First")
        XCTAssertEqual(snapshot.inspirations[0].text, "Second metadata")
    }

    func testCorruptJSONIsSurfacedAndNotSilentlyReplaced() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent(PinaxStorage.libraryFilename)
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: fileURL)
        let repository = try LibraryRepository(storageDirectory: directory)

        await XCTAssertThrowsErrorAsync(try await repository.load())
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
    }

    func testPersistenceIsDeterministicForSameSnapshotAndClock() async throws {
        let repository = try makeRepository()
        let project = Project(id: UUID(), name: "One", createdAt: fixedDate)
        let snapshot = LibrarySnapshot(projects: [project], updatedAt: fixedDate)

        try await repository.save(snapshot)
        let first = try Data(contentsOf: repository.libraryFileURL)
        try await repository.save(snapshot)
        let second = try Data(contentsOf: repository.libraryFileURL)

        XCTAssertEqual(first, second)
    }

    private func makeRepository() throws -> LibraryRepository {
        let date = fixedDate
        return try LibraryRepository(storageDirectory: makeTemporaryDirectory(), clock: { date })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (any Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
