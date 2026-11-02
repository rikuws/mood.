import Foundation

/// `mood-agent mcp`: the same reads and pending proposals as the command line,
/// served to a coding agent over the Model Context Protocol, one JSON-RPC
/// message per line on stdin and stdout. Any MCP client (Claude Code, Codex,
/// Cursor) can then read the person's projects, saved items and essences
/// while it builds, without the skills or the command line.
///
/// It only reads, and adds proposals that wait for the person, exactly as
/// `suggest` and `reflect` do. Nothing is kept, rejected or edited here.
public struct PinaxAgentMCPServer: Sendable {
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    /// Larger images are left for the client to open from `localImagePath`.
    static let maximumImageBytes = 4 * 1_024 * 1_024

    private let api: PinaxAgentAPI
    private let version: String

    public init(api: PinaxAgentAPI, version: String = "1.0") {
        self.api = api
        self.version = version
    }

    /// Reads messages until stdin closes, answering each one in turn.
    public func run(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) async throws {
        for try await line in input.bytes.lines {
            guard let response = await handle(Data(line.utf8)) else { continue }
            var data = response
            data.append(0x0A)
            try output.write(contentsOf: data)
        }
    }

    /// Answers one message. Notifications get no answer.
    public func handle(_ message: Data) async -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: message),
              let request = object as? [String: Any] else {
            return Self.error(id: NSNull(), code: -32700, message: "Parse error: send one JSON-RPC object per line.")
        }
        guard let method = request["method"] as? String else {
            return Self.error(id: request["id"] ?? NSNull(), code: -32600, message: "Invalid request: `method` is required.")
        }
        // A message without an id is a notification, such as
        // `notifications/initialized`; it is never answered.
        guard let id = request["id"], !(id is NSNull) else { return nil }
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
                ?? Self.supportedProtocolVersions[0]
            return Self.result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "mood", "version": self.version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.error(id: id, code: -32602, message: "Invalid params: `name` is required.")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(name).")
            }
            return Self.result(id: id, await call(name, arguments: arguments))
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method).")
        }
    }

    // MARK: Tools

    private func call(_ name: String, arguments: [String: Any]) async -> [String: Any] {
        do {
            switch name {
            case "list_projects":
                return try Self.json(await api.projects())
            case "get_project_items":
                return try Self.json(await api.inspirations(project: Self.string("project", in: arguments)))
            case "get_item":
                return try Self.json(await api.inspiration(id: Self.string("id", in: arguments)))
            case "get_item_image":
                return try await image(id: Self.string("id", in: arguments))
            case "get_essence":
                return try Self.json(await api.essence(project: Self.string("project", in: arguments)))
            case "get_study":
                return try Self.json(await api.study(project: Self.string("project", in: arguments)))
            case "propose_sources":
                let drafts: [StudySuggestionDraft] = try Self.decode("suggestions", in: arguments)
                return try Self.json(await api.suggest(project: Self.string("project", in: arguments), drafts: drafts))
            case "propose_patterns":
                let drafts: [StudyReflectionDraft] = try Self.decode("reflections", in: arguments)
                return try Self.json(await api.reflect(project: Self.string("project", in: arguments), drafts: drafts))
            default:
                throw PinaxAgentAPIError.invalidArguments("Unknown tool: \(name).")
            }
        } catch {
            let response = PinaxAgentErrorResponse(error: error)
            let text = (try? Self.encoded(response)) ?? error.localizedDescription
            return ["content": [["type": "text", "text": text]], "isError": true]
        }
    }

    /// A saved item's stored image, so clients that can't open files still
    /// see it.
    private func image(id: String) async throws -> [String: Any] {
        let response = try await api.inspiration(id: id)
        guard let path = response.inspiration.localImagePath else {
            let remote = response.inspiration.imageURL.map { " Its image is at \($0.absoluteString)." } ?? ""
            return Self.text("This item has no stored image.\(remote)")
        }
        let url = URL(fileURLWithPath: path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= Self.maximumImageBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let mimeType = Self.imageMIMEType(data) else {
            return Self.text("The image is too large or in a format MCP can't carry. Open it at \(path).")
        }
        return ["content": [
            ["type": "image", "data": data.base64EncodedString(), "mimeType": mimeType],
            ["type": "text", "text": "\(response.inspiration.title) (\(path))"],
        ]]
    }

    static func imageMIMEType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        if bytes.count >= 12, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        return nil
    }

    static let instructions = """
    mood. is the user's own design-direction library: what they saved, why, and the direction \
    distilled from it. Before building UI, call list_projects, then get_essence for the project \
    you're building (its rules trace to saved items) and get_project_items to look at the \
    references themselves (get_item_image shows one). The user is the source of taste: follow \
    their saved items, notes and confirmed patterns rather than generic defaults, and don't \
    invent rules they didn't save. propose_sources and propose_patterns only add proposals the \
    user keeps or rejects in mood.; nothing you send is kept on its own.
    """

    // Computed, since `[String: Any]` isn't Sendable and can't be a shared constant.
    static var tools: [[String: Any]] { [
        tool(
            "list_projects",
            "Lists the user's mood. projects with how many items each holds, and which are studies.",
            [:]
        ),
        tool(
            "get_project_items",
            "Returns every item saved in a project, newest first: title, text, author, source URL, the user's note and verdict, image URL and local image path.",
            ["project": projectProperty],
            required: ["project"]
        ),
        tool(
            "get_item",
            "Returns one saved item by its UUID.",
            ["id": ["type": "string", "description": "The item's UUID."]],
            required: ["id"]
        ),
        tool(
            "get_item_image",
            "Shows a saved item's stored image.",
            ["id": ["type": "string", "description": "The item's UUID."]],
            required: ["id"]
        ),
        tool(
            "get_essence",
            "Returns the project's latest saved design essence: the direction distilled from its items, every rule citing the items it came from.",
            ["project": projectProperty],
            required: ["project"]
        ),
        tool(
            "get_study",
            "Returns a study: its subject and brief, its items, every proposed source and move with the user's verdict and reason, and its patterns.",
            ["project": projectProperty],
            required: ["project"]
        ),
        tool(
            "propose_sources",
            "Adds real, credited sources (or moves, with move, lens and forInspirationID) to a study as pending proposals for the user to keep or reject in mood. Same fields and checks as `mood-agent suggest`.",
            [
                "project": projectProperty,
                "suggestions": [
                    "type": "array",
                    "description": "1 to 50 entries: url, title, creator, rationale, and optionally sourceName, imageURL, basedOnInspirationIDs, move, lens, forInspirationID.",
                    "items": ["type": "object"],
                ],
            ],
            required: ["project", "suggestions"]
        ),
        tool(
            "propose_patterns",
            "Adds patterns noticed in a study's keeps and rejects, for the user to confirm, correct or dismiss in mood. Same fields and checks as `mood-agent reflect`.",
            [
                "project": projectProperty,
                "reflections": [
                    "type": "array",
                    "description": "1 to 50 entries: statement, and the inspirationIDs and rejectedSuggestionIDs it cites.",
                    "items": ["type": "object"],
                ],
            ],
            required: ["project", "reflections"]
        ),
    ] }

    private static var projectProperty: [String: Any] {
        [
            "type": "string",
            "description": "The project's name or UUID, as list_projects returns it.",
        ]
    }

    private static func tool(
        _ name: String,
        _ description: String,
        _ properties: [String: Any],
        required: [String] = []
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
        ]
    }

    // MARK: Encoding

    private static func string(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw PinaxAgentAPIError.invalidArguments("`\(key)` is required.")
        }
        return value
    }

    private static func decode<Value: Decodable>(_ key: String, in arguments: [String: Any]) throws -> Value {
        guard let value = arguments[key], JSONSerialization.isValidJSONObject([value]) else {
            throw PinaxAgentAPIError.invalidStudyInput("`\(key)` is required.")
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw PinaxAgentAPIError.invalidStudyInput("`\(key)` doesn't match the expected shape.")
        }
    }

    private static func json<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        text(try encoded(value))
    }

    private static func text(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    private static func encoded<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func result(id: Any, _ result: [String: Any]) -> Data {
        message(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func error(id: Any, code: Int, message text: String) -> Data {
        message(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]])
    }

    private static func message(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]))
            ?? Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#.utf8)
    }
}
