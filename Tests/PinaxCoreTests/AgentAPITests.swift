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

    func testInspirationsExposeNoteAndVerdict() async throws {
        let repository = try makeRepository()
        var inspiration = makeInspiration(
            title: "Judged reference",
            createdAt: Date(timeIntervalSince1970: 300),
            localImageFilename: nil
        )
        inspiration.note = "Too decorative for this project."
        inspiration.verdict = .reject
        try await repository.save(LibrarySnapshot(inspirations: [inspiration]))

        let response = try await PinaxAgentAPI(repository: repository)
            .inspiration(id: inspiration.id.uuidString)
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(response.inspiration)) as? [String: Any]
        )

        XCTAssertEqual(response.inspiration.note, "Too decorative for this project.")
        XCTAssertEqual(response.inspiration.verdict, .reject)
        XCTAssertEqual(encoded["verdict"] as? String, "reject")
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

    func testCommandParserAcceptsEssenceStorageCommands() throws {
        XCTAssertEqual(
            try PinaxAgentCommand.parse(
                arguments: ["save-essence", "--file", "essence.json", "--pretty"]
            ),
            .saveEssence(file: "essence.json", prettyPrinted: true)
        )
        XCTAssertEqual(
            try PinaxAgentCommand.parse(arguments: ["essence", "--project", " Website "]),
            .essence(project: "Website", prettyPrinted: false)
        )
        XCTAssertThrowsError(try PinaxAgentCommand.parse(arguments: ["save-essence", "essence.json"]))
        XCTAssertThrowsError(try PinaxAgentCommand.parse(arguments: ["essence", "--project", " "]))
        XCTAssertTrue(PinaxAgentCommand.usage.contains("save-essence --file"))
        XCTAssertTrue(PinaxAgentCommand.usage.contains("essence --project"))
    }

    func testEssenceReturnsNoRevisionBeforeFirstSave() async throws {
        let repository = try makeRepository()
        let project = Project(id: UUID(), name: "Website")
        try await repository.save(LibrarySnapshot(projects: [project]))

        let response = try await PinaxAgentAPI(repository: repository).essence(project: "website")

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.project.id, project.id)
        XCTAssertEqual(response.revisionCount, 0)
        XCTAssertNil(response.revision)
        XCTAssertNil(response.stale)
        XCTAssertNil(response.essence)
    }

    func testSaveEssenceAppendsRevisionAndEssenceReturnsLatest() async throws {
        let repository = try makeRepository()
        let fixture = try await saveProjectFixture(in: repository)
        let api = PinaxAgentAPI(repository: repository)
        let libraryBefore = try Data(contentsOf: repository.libraryFileURL)

        let first = try await api.saveEssence(
            filePath: try writeEssence(fixture.essence(extractedAt: fixture.extractedAt), in: repository),
            currentDirectory: repository.storageDirectory
        )
        let again = try await api.saveEssence(
            filePath: try writeEssence(fixture.essence(extractedAt: fixture.extractedAt), in: repository),
            currentDirectory: repository.storageDirectory
        )
        let laterEssence = fixture.essence(extractedAt: fixture.extractedAt.addingTimeInterval(60))
        let second = try await api.saveEssence(
            filePath: try writeEssence(laterEssence, in: repository),
            currentDirectory: repository.storageDirectory
        )
        let latest = try await api.essence(project: fixture.project.id.uuidString)

        XCTAssertEqual(first.outcome, .saved)
        XCTAssertEqual(again.outcome, .alreadySaved)
        XCTAssertEqual(again.revision, first.revision)
        XCTAssertEqual(second.outcome, .saved)
        XCTAssertTrue(first.revision.id.hasPrefix("20231114T221320.000Z-"))
        XCTAssertEqual(
            URL(fileURLWithPath: first.revision.path).deletingLastPathComponent().path,
            repository.storageDirectory
                .appendingPathComponent("Essences/\(fixture.project.id.uuidString)", isDirectory: true)
                .path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.revision.path))
        XCTAssertEqual(try Data(contentsOf: repository.libraryFileURL), libraryBefore)

        XCTAssertEqual(latest.revisionCount, 2)
        XCTAssertEqual(latest.revision, second.revision)
        XCTAssertEqual(latest.essence, laterEssence)
        XCTAssertEqual(latest.stale, false)
    }

    func testEssenceReportsAddedRemovedAndChangedItemsAsStale() async throws {
        let repository = try makeRepository()
        let fixture = try await saveProjectFixture(in: repository)
        let api = PinaxAgentAPI(repository: repository)
        _ = try await api.saveEssence(
            filePath: try writeEssence(fixture.essence(extractedAt: fixture.extractedAt), in: repository),
            currentDirectory: repository.storageDirectory
        )

        let added = makeInspiration(
            title: "New",
            projectID: fixture.project.id,
            createdAt: fixture.extractedAt.addingTimeInterval(10)
        )
        var edited = fixture.first
        edited.text = "Changed my mind about the type."
        edited.updatedAt = fixture.extractedAt.addingTimeInterval(20)
        try await repository.save(
            LibrarySnapshot(projects: [fixture.project], inspirations: [edited, added])
        )

        let response = try await api.essence(project: "Website")

        XCTAssertEqual(response.stale, true)
        XCTAssertEqual(response.staleness?.addedAssetIDs, [added.id])
        XCTAssertEqual(response.staleness?.removedAssetIDs, [fixture.second.id])
        XCTAssertEqual(response.staleness?.changedAssetIDs, [fixture.first.id])
    }

    func testSaveEssenceAcceptsQuotesFromTheUsersOwnText() async throws {
        let repository = try makeRepository()
        let fixture = try await saveProjectFixture(in: repository)
        let quote = DesignEssence.Evidence(
            assetID: fixture.first.id,
            field: .text,
            quote: "  QUIET   spacing ",
            cue: "The user's note names spacing as the reason to keep it."
        )

        let response = try await PinaxAgentAPI(repository: repository).saveEssence(
            filePath: try writeEssence(
                fixture.essence(extractedAt: fixture.extractedAt, extraEvidence: [quote]),
                in: repository
            ),
            currentDirectory: repository.storageDirectory
        )

        XCTAssertEqual(response.outcome, .saved)
        XCTAssertEqual(response.referenceCount, 2)
    }

    func testSaveEssenceRejectsQuotesTheItemDoesNotContain() async throws {
        let repository = try makeRepository()
        let fixture = try await saveProjectFixture(in: repository)
        let invented = DesignEssence.Evidence(
            assetID: fixture.first.id,
            field: .text,
            quote: "bold neon gradients",
            cue: "Invented wording."
        )
        let note = DesignEssence.Evidence(
            assetID: fixture.first.id,
            field: .note,
            quote: "quiet spacing",
            cue: "Cites a note field the library does not store yet."
        )

        for evidence in [invented, note] {
            await XCTAssertThrowsErrorAsync(
                try await PinaxAgentAPI(repository: repository).saveEssence(
                    filePath: try self.writeEssence(
                        fixture.essence(extractedAt: fixture.extractedAt, extraEvidence: [evidence]),
                        in: repository
                    ),
                    currentDirectory: repository.storageDirectory
                )
            ) { error in
                XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "invalid_essence")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repository.storageDirectory.appendingPathComponent("Essences").path
            )
        )
    }

    func testSaveEssenceRejectsReferencesOutsideTheProjectAndImageEssences() async throws {
        let repository = try makeRepository()
        let fixture = try await saveProjectFixture(in: repository)
        let api = PinaxAgentAPI(repository: repository)
        let stranger = UUID()

        await XCTAssertThrowsErrorAsync(
            try await api.saveEssence(
                filePath: try self.writeEssence(
                    fixture.essence(extractedAt: fixture.extractedAt, extraReferenceIDs: [stranger]),
                    in: repository
                ),
                currentDirectory: repository.storageDirectory
            )
        ) { error in
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "invalid_essence")
            XCTAssertTrue(error.localizedDescription.contains(stranger.uuidString))
        }

        await XCTAssertThrowsErrorAsync(
            try await api.saveEssence(
                filePath: try self.writeEssence(self.makeValidEssence(), in: repository),
                currentDirectory: repository.storageDirectory
            )
        ) { error in
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "invalid_essence")
        }
    }

    private struct ProjectFixture {
        let project: Project
        let first: Inspiration
        let second: Inspiration
        let extractedAt: Date

        func essence(
            extractedAt: Date,
            extraEvidence: [DesignEssence.Evidence] = [],
            extraReferenceIDs: [Inspiration.ID] = []
        ) -> DesignEssence {
            let imageEvidence = DesignEssence.Evidence(
                assetID: first.id,
                cue: "Generous margins around a single column"
            )
            let referenceIDs = [first.id, second.id] + extraReferenceIDs
            return DesignEssence(
                source: DesignEssence.Source(
                    kind: .project,
                    projectID: project.id,
                    references: referenceIDs.map { DesignEssence.Source.Reference(assetID: $0) },
                    inputHash: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                ),
                provenance: DesignEssence.Provenance(
                    extractedAt: extractedAt,
                    model: "fixture-model",
                    pipelineVersion: "mood-distill/2.1"
                ),
                scope: DesignEssence.Scope(domain: .userInterface),
                summary: DesignEssence.Summary(
                    essence: DesignEssence.Claim(
                        value: "Quiet, spacious, single-column",
                        basis: .inferred,
                        confidence: 0.8,
                        evidence: [imageEvidence] + extraEvidence
                    )
                )
            )
        }
    }

    private func saveProjectFixture(in repository: LibraryRepository) async throws -> ProjectFixture {
        let project = Project(id: UUID(), name: "Website")
        var first = makeInspiration(
            title: "First",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        first.text = "Kept for the quiet spacing and the single column."
        let second = makeInspiration(
            title: "Second",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_600_000_100)
        )
        try await repository.save(
            LibrarySnapshot(projects: [project], inspirations: [first, second])
        )
        let saved = try await repository.load()
        return ProjectFixture(
            project: project,
            first: try XCTUnwrap(saved.inspirations.first { $0.id == first.id }),
            second: try XCTUnwrap(saved.inspirations.first { $0.id == second.id }),
            extractedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func writeEssence(_ essence: DesignEssence, in repository: LibraryRepository) throws -> String {
        let fileURL = repository.storageDirectory
            .appendingPathComponent("candidate-\(UUID().uuidString).json")
        try JSONEncoder().encode(essence).write(to: fileURL)
        return fileURL.lastPathComponent
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
