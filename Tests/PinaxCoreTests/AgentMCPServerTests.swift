import Foundation
import XCTest
@testable import PinaxCore

final class AgentMCPServerTests: XCTestCase, @unchecked Sendable {
    func testInitializeAgreesOnAVersionAndOffersTools() async throws {
        let server = try makeServer()

        let known = try await send(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26"]])
        let result = try XCTUnwrap(known["result"] as? [String: Any])
        XCTAssertEqual(known["id"] as? Int, 1)
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "mood")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertTrue((result["instructions"] as? String)?.contains("source of taste") == true)

        let unknown = try await send(server, ["jsonrpc": "2.0", "id": "a", "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        XCTAssertEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual(unknown["id"] as? String, "a")
    }

    func testListsReadAndProposalToolsWithSchemas() async throws {
        let server = try makeServer()
        let response = try await send(server, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])

        XCTAssertEqual(
            tools.compactMap { $0["name"] as? String },
            ["list_projects", "get_project_items", "get_item", "get_item_image", "get_essence", "get_study", "propose_sources", "propose_patterns"]
        )
        for tool in tools {
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object")
        }
    }

    func testCallingAToolReturnsTheSameJSONAsTheCommandLine() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "Calm tools")
        _ = try await repository.capture(
            CapturePayload(source: .web, url: URL(string: "https://example.com/list")!, title: "Today list", projectID: project.id)
        )
        let server = PinaxAgentMCPServer(api: PinaxAgentAPI(repository: repository))

        let projects = try await callText(server, "list_projects")
        XCTAssertTrue(projects.contains("\"name\":\"Calm tools\""))

        let items = try await callText(server, "get_project_items", ["project": "calm tools"])
        XCTAssertTrue(items.contains("\"title\":\"Today list\""))

        let noImage = try await callText(server, "get_item_image", ["id": try XCTUnwrap(itemID(in: items))])
        XCTAssertTrue(noImage.contains("no stored image"))
    }

    func testProposingIntoAStudyAddsPendingSourcesOnly() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "Calm tools")
        _ = try await repository.startStudy(projectID: project.id, subject: "Calm tools")
        let server = PinaxAgentMCPServer(api: PinaxAgentAPI(repository: repository))

        let added = try await callText(server, "propose_sources", [
            "project": "Calm tools",
            "suggestions": [[
                "url": "https://example.com/list",
                "title": "Today list",
                "creator": "Olm",
                "rationale": "One toggle, nothing around it.",
            ]],
        ])
        XCTAssertTrue(added.contains("\"added\""))
        let study = try await repository.load().projects.first?.study
        XCTAssertEqual(study?.suggestions.map(\.status), [.pending])
    }

    func testToolFailuresAreResultsAndProtocolMistakesAreErrors() async throws {
        let server = try makeServer()

        let missing = try await send(server, ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "get_essence", "arguments": [:]]])
        let failure = try XCTUnwrap(missing["result"] as? [String: Any])
        XCTAssertEqual(failure["isError"] as? Bool, true)

        let unknownTool = try await send(server, ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "delete_everything"]])
        XCTAssertEqual((unknownTool["error"] as? [String: Any])?["code"] as? Int, -32602)

        let unknownMethod = try await send(server, ["jsonrpc": "2.0", "id": 5, "method": "resources/list"])
        XCTAssertEqual((unknownMethod["error"] as? [String: Any])?["code"] as? Int, -32601)

        let garbage = await server.handle(Data("not json".utf8))
        let parsed = try XCTUnwrap(garbage.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual((parsed["error"] as? [String: Any])?["code"] as? Int, -32700)

        let notification = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        let answer = await server.handle(notification)
        XCTAssertNil(answer)
    }

    func testCommandLineAcceptsMCPWithoutOptions() throws {
        XCTAssertEqual(try PinaxAgentCommand.parse(arguments: ["mcp"]), .mcp)
        XCTAssertThrowsError(try PinaxAgentCommand.parse(arguments: ["mcp", "--pretty"]))
    }

    func testRecognizesTheImageFormatsMCPCanCarry() {
        XCTAssertEqual(PinaxAgentMCPServer.imageMIMEType(Data([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])), "image/png")
        XCTAssertEqual(PinaxAgentMCPServer.imageMIMEType(Data([0xFF, 0xD8, 0xFF, 0xE0])), "image/jpeg")
        XCTAssertNil(PinaxAgentMCPServer.imageMIMEType(Data([0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70])))
    }

    // MARK: - Helpers

    private func send(_ server: PinaxAgentMCPServer, _ message: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: message)
        let response = try await XCTUnwrapAsync(await server.handle(data))
        XCTAssertFalse(response.contains(0x0A), "One message per line")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
    }

    private func callText(
        _ server: PinaxAgentMCPServer,
        _ name: String,
        _ arguments: [String: Any] = [:]
    ) async throws -> String {
        let response = try await send(server, [
            "jsonrpc": "2.0",
            "id": 9,
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertNil(result["isError"], "\(result)")
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return try XCTUnwrap(content.first?["text"] as? String)
    }

    private func itemID(in itemsJSON: String) -> String? {
        let object = try? JSONSerialization.jsonObject(with: Data(itemsJSON.utf8)) as? [String: Any]
        let items = object?["inspirations"] as? [[String: Any]]
        return items?.first?["id"] as? String
    }

    private func makeServer() throws -> PinaxAgentMCPServer {
        PinaxAgentMCPServer(api: PinaxAgentAPI(repository: try makeRepository()))
    }

    private func makeRepository() throws -> LibraryRepository {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxAgentMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return try LibraryRepository(storageDirectory: directory)
    }
}

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
