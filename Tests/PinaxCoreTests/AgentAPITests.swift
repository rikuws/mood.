import Foundation
import XCTest
@testable import PinaxCore

final class AgentAPITests: XCTestCase, @unchecked Sendable {
    func testProjectsReturnsEmptyResponseBeforeFirstLibraryWrite() async throws {
        let repository = try makeRepository()

        let response = try await PinaxAgentAPI(repository: repository).projects()

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.count, 0)
        XCTAssertTrue(response.projects.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.libraryFileURL.path))
    }

    func testProjectsAreSortedAndIncludeInspirationCounts() async throws {
        let repository = try makeRepository()
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        let alpha = Project(id: UUID(), name: "Älpha", createdAt: later)
        let zeta = Project(id: UUID(), name: "Zeta", createdAt: later)
        let inspiration = makeInspiration(projectID: zeta.id, createdAt: later)
        try await repository.save(
            LibrarySnapshot(projects: [zeta, alpha], inspirations: [inspiration])
        )

        let response = try await PinaxAgentAPI(repository: repository).projects()

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.apiVersion, 1)
        XCTAssertEqual(response.projects.map(\.name), ["Älpha", "Zeta"])
        XCTAssertEqual(response.projects.map(\.inspirationCount), [0, 1])
    }

    func testInspirationsResolveProjectByFoldedNameAndReturnNewestFirst() async throws {
        let repository = try makeRepository()
        let project = Project(id: UUID(), name: "Café Launch")
        let older = makeInspiration(
            title: "Older",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 100),
            localImageFilename: "reference.png"
        )
        let newer = makeInspiration(
            title: "Newer",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let general = makeInspiration(title: "General", createdAt: Date(timeIntervalSince1970: 300))
        try await repository.save(
            LibrarySnapshot(
                projects: [project],
                inspirations: [older, newer, general]
            )
        )

        let response = try await PinaxAgentAPI(repository: repository)
            .inspirations(project: "  CAFE LAUNCH ")

        XCTAssertEqual(response.project.id, project.id)
        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.inspirations.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(response.inspirations[1].projectID, project.id)
        XCTAssertEqual(
            response.inspirations[1].localImagePath,
            repository.mediaDirectory.appendingPathComponent("reference.png").path
        )
    }

    func testInspirationsResolveProjectByUUID() async throws {
        let repository = try makeRepository()
        let project = Project(id: UUID(), name: "Website")
        try await repository.save(LibrarySnapshot(projects: [project]))

        let response = try await PinaxAgentAPI(repository: repository)
            .inspirations(project: project.id.uuidString.lowercased())

        XCTAssertEqual(response.project.id, project.id)
        XCTAssertTrue(response.inspirations.isEmpty)
    }

    func testInspirationReturnsSingleGeneralItemAndSafeLocalPath() async throws {
        let repository = try makeRepository()
        let inspiration = makeInspiration(
            title: "Single reference",
            createdAt: Date(timeIntervalSince1970: 200),
            localImageFilename: "single-reference.png"
        )
        try await repository.save(LibrarySnapshot(inspirations: [inspiration]))

        let response = try await PinaxAgentAPI(repository: repository)
            .inspiration(id: inspiration.id.uuidString.lowercased())

        XCTAssertTrue(response.ok)
        XCTAssertNil(response.project)
        XCTAssertNil(response.inspiration.projectID)
        XCTAssertEqual(response.inspiration.id, inspiration.id)
        XCTAssertEqual(
            response.inspiration.localImagePath,
            repository.mediaDirectory.appendingPathComponent("single-reference.png").path
        )
    }

    func testMissingInspirationReturnsStableAgentError() async throws {
        let repository = try makeRepository()
        let missingID = UUID().uuidString

        await XCTAssertThrowsErrorAsync(
            try await PinaxAgentAPI(repository: repository).inspiration(id: missingID)
        ) { error in
            XCTAssertEqual(error as? PinaxAgentAPIError, .inspirationNotFound(missingID))
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "inspiration_not_found")
        }
    }

    func testMissingProjectReturnsStableAgentError() async throws {
        let repository = try makeRepository()

        await XCTAssertThrowsErrorAsync(
            try await PinaxAgentAPI(repository: repository).inspirations(project: "Unknown")
        ) { error in
            XCTAssertEqual(error as? PinaxAgentAPIError, .projectNotFound("Unknown"))
            let response = PinaxAgentErrorResponse(error: error)
            XCTAssertEqual(response.error.code, "project_not_found")
            XCTAssertFalse(response.ok)
        }
    }

    func testUnreadableLibraryReturnsStableStorageError() async throws {
        let repository = try makeRepository()
        try Data("not-json".utf8).write(to: repository.libraryFileURL)

        await XCTAssertThrowsErrorAsync(
            try await PinaxAgentAPI(repository: repository).projects()
        ) { error in
            guard let apiError = error as? PinaxAgentAPIError,
                  case .storageUnavailable = apiError else {
                return XCTFail("Expected storageUnavailable, got \(error)")
            }
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "storage_error")
        }
    }

    func testCommandParserAcceptsMachineFacingCommands() throws {
        XCTAssertEqual(
            try PinaxAgentCommand.parse(arguments: ["projects", "--pretty"]),
            .projects(prettyPrinted: true)
        )
        XCTAssertEqual(
            try PinaxAgentCommand.parse(
                arguments: ["inspirations", "--pretty", "--project", "Mobile App"]
            ),
            .inspirations(project: "Mobile App", prettyPrinted: true)
        )
        let itemID = UUID().uuidString
        XCTAssertEqual(
            try PinaxAgentCommand.parse(
                arguments: ["inspiration", "--id", itemID, "--pretty"]
            ),
            .inspiration(id: itemID, prettyPrinted: true)
        )
        XCTAssertEqual(
            try PinaxAgentCommand.parse(
                arguments: ["validate-essence", "--file", "essence.json", "--pretty"]
            ),
            .validateEssence(file: "essence.json", prettyPrinted: true)
        )
        XCTAssertThrowsError(
            try PinaxAgentCommand.parse(arguments: ["inspirations", "Mobile App"])
        )
        XCTAssertThrowsError(
            try PinaxAgentCommand.parse(arguments: ["inspiration", "--id", "not-a-uuid"])
        )
        XCTAssertThrowsError(
            try PinaxAgentCommand.parse(arguments: ["validate-essence", "essence.json"])
        )
        XCTAssertTrue(PinaxAgentCommand.usage.contains("mood-agent"))
    }

    func testEssenceCommandPreservesFilePathWhitespaceAndRejectsInvalidPaths() throws {
        let path = " essence.json "

        XCTAssertEqual(
            try PinaxAgentCommand.parse(
                arguments: ["validate-essence", "--file", path]
            ),
            .validateEssence(file: path, prettyPrinted: false)
        )
        XCTAssertThrowsError(
            try PinaxAgentCommand.parse(
                arguments: ["validate-essence", "--file", " \n\t"]
            )
        )
        XCTAssertThrowsError(
            try PinaxAgentCommand.parse(
                arguments: ["validate-essence", "--file", "essence\0.json"]
            )
        )
    }

    func testEssenceFileValidatorAcceptsCanonicalJSON() throws {
        let repository = try makeRepository()
        let essence = makeValidEssence()
        let fileURL = repository.storageDirectory.appendingPathComponent("essence.json")
        try JSONEncoder().encode(essence).write(to: fileURL)

        let response = try PinaxAgentAPI.validateEssence(
            filePath: "essence.json",
            currentDirectory: repository.storageDirectory
        )

        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.valid)
        XCTAssertEqual(response.schemaVersion, DesignEssence.currentSchemaVersion)
        XCTAssertEqual(response.sourceKind, .image)
        XCTAssertEqual(response.referenceCount, 1)
    }

    func testEssenceFileValidatorPreservesWhitespaceInFileName() throws {
        let repository = try makeRepository()
        let fileName = " essence.json "
        let fileURL = repository.storageDirectory.appendingPathComponent(fileName)
        try JSONEncoder().encode(makeValidEssence()).write(to: fileURL)

        let response = try PinaxAgentAPI.validateEssence(
            filePath: fileName,
            currentDirectory: repository.storageDirectory
        )

        XCTAssertTrue(response.valid)
    }

    func testEssenceFileValidatorReturnsStableErrorForMalformedJSON() throws {
        let repository = try makeRepository()
        let fileURL = repository.storageDirectory.appendingPathComponent("invalid.json")
        try Data("{}".utf8).write(to: fileURL)

        XCTAssertThrowsError(
            try PinaxAgentAPI.validateEssence(
                filePath: fileURL.path,
                currentDirectory: repository.storageDirectory
            )
        ) { error in
            guard let apiError = error as? PinaxAgentAPIError,
                  case .invalidEssence = apiError else {
                return XCTFail("Expected invalidEssence, got \(error)")
            }
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "invalid_essence")
        }
    }

    private func makeRepository() throws -> LibraryRepository {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxAgentAPITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return try LibraryRepository(storageDirectory: directory)
    }

    private func makeInspiration(
        title: String = "Reference",
        projectID: Project.ID? = nil,
        createdAt: Date,
        localImageFilename: String? = nil
    ) -> Inspiration {
        Inspiration(
            source: .web,
            url: URL(string: "https://example.com/\(UUID().uuidString)")!,
            canonicalURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
            title: title,
            localImageFilename: localImageFilename,
            projectID: projectID,
            createdAt: createdAt
        )
    }

    private func makeValidEssence() -> DesignEssence {
        let assetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let evidence = DesignEssence.Evidence(
            assetID: assetID,
            cue: "A restrained grid with generous negative space"
        )
        return DesignEssence(
            source: DesignEssence.Source(
                kind: .image,
                references: [.init(assetID: assetID)],
                inputHash: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ),
            provenance: DesignEssence.Provenance(
                extractedAt: Date(timeIntervalSince1970: 1_700_000_000),
                model: "fixture-model",
                pipelineVersion: "mood-distill/2.0"
            ),
            scope: DesignEssence.Scope(domain: .userInterface),
            summary: DesignEssence.Summary(
                essence: DesignEssence.Claim(
                    value: "Quiet editorial precision",
                    basis: .inferred,
                    confidence: 0.8,
                    evidence: [evidence]
                )
            )
        )
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
