import Foundation
import XCTest
@testable import PinaxCore

final class AgentAPITests: XCTestCase, @unchecked Sendable {
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
        XCTAssertThrowsError(
            try PinaxAgentCommand.parse(arguments: ["inspirations", "Mobile App"])
        )
        XCTAssertTrue(PinaxAgentCommand.usage.contains("mood-agent"))
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
