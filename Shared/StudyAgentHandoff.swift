import Foundation

/// How a study agent exchanges data with mood. without touching the library.
/// mood. writes the study into the agent's scratch folder before the run, and
/// afterwards reads the proposals the agent wrote there and adds them through
/// the same checks as `mood-agent suggest`/`reflect`. The agent needs no
/// library access, so sandboxed agents work and only mood. writes the library.
public enum StudyAgentHandoff {
    public static let studyFilename = "study.json"
    public static let suggestionsFilename = "suggestions.json"
    public static let reflectionsFilename = "reflections.json"
    /// Every study item's image, copied in as `<item id>.<ext>` so an agent
    /// can look at it without network or library access.
    public static let imagesDirectoryName = "images"
    private static let maximumImageBytes = 25 * 1_024 * 1_024

    /// Downloads one remote image. Injected so tests stay offline.
    public typealias ImageFetcher = @Sendable (URL) async -> Data?

    public static let urlSessionFetcher: ImageFetcher = { url in
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return result.0
    }

    public static func proposalsFilename(for task: StudyAgentTask) -> String {
        switch task {
        case .findSources: suggestionsFilename
        case .reflect: reflectionsFilename
        }
    }

    /// Writes the study as `mood-agent study` prints it, and copies each
    /// item's image into `images/`: the stored file when there is one,
    /// otherwise a best-effort download of its `imageURL`. Returns how many
    /// images were staged.
    @discardableResult
    public static func prepare(
        api: PinaxAgentAPI,
        projectID: Project.ID,
        in directory: URL,
        fetchImage: @escaping ImageFetcher = urlSessionFetcher
    ) async throws -> Int {
        let response = try await api.study(project: projectID.uuidString)
        let staged = await stageImages(for: response.study.items, in: directory, fetchImage: fetchImage)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(response).write(
            to: directory.appendingPathComponent(studyFilename, isDirectory: false),
            options: .atomic
        )
        return staged
    }

    private static func stageImages(
        for items: [PinaxAgentInspiration],
        in directory: URL,
        fetchImage: @escaping ImageFetcher
    ) async -> Int {
        let imagesDirectory = directory.appendingPathComponent(imagesDirectoryName, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)) != nil else {
            return 0
        }
        return await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for item in items {
                group.addTask {
                    let data: Data?
                    var fileExtension: String?
                    if let path = item.localImagePath {
                        data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                        fileExtension = URL(fileURLWithPath: path).pathExtension
                    } else if let remote = item.imageURL {
                        data = await fetchImage(remote)
                        fileExtension = remote.pathExtension
                    } else {
                        data = nil
                    }
                    guard let data, !data.isEmpty, data.count <= maximumImageBytes else { return false }
                    let name = item.id.uuidString.lowercased()
                        + "." + imageExtension(for: data, fallback: fileExtension)
                    return (try? data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)) != nil
                }
            }
            var count = 0
            for await staged in group where staged { count += 1 }
            return count
        }
    }

    /// Names files by their bytes, so an agent's image viewer accepts them.
    private static func imageExtension(for data: Data, fallback: String?) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "gif" }
        if bytes.count >= 12, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x45, 0x42, 0x50] {
            return "webp"
        }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) { return "heic" }
        let fallback = fallback?.lowercased() ?? ""
        return fallback.isEmpty || fallback.count > 5 ? "img" : fallback
    }

    /// Adds what the agent proposed for `task`, if it wrote anything.
    public static func collect(
        api: PinaxAgentAPI,
        projectID: Project.ID,
        task: StudyAgentTask,
        from directory: URL
    ) async throws -> StudyAgentHandoffResult {
        let file = directory.appendingPathComponent(proposalsFilename(for: task), isDirectory: false)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return StudyAgentHandoffResult(foundProposals: false)
        }
        switch task {
        case .findSources:
            let response = try await api.suggest(project: projectID.uuidString, filePath: file.path)
            return StudyAgentHandoffResult(
                foundProposals: true,
                addedSuggestions: response.added.count,
                skipped: response.skipped
            )
        case .reflect:
            let response = try await api.reflect(project: projectID.uuidString, filePath: file.path)
            return StudyAgentHandoffResult(foundProposals: true, addedReflections: response.added.count)
        }
    }
}

public struct StudyAgentHandoffResult: Equatable, Sendable {
    public var foundProposals: Bool
    public var addedSuggestions: Int
    public var addedReflections: Int
    public var skipped: [StudySuggestionSkip]

    public init(
        foundProposals: Bool,
        addedSuggestions: Int = 0,
        addedReflections: Int = 0,
        skipped: [StudySuggestionSkip] = []
    ) {
        self.foundProposals = foundProposals
        self.addedSuggestions = addedSuggestions
        self.addedReflections = addedReflections
        self.skipped = skipped
    }

    /// One plain sentence for the study panel.
    public var summary: String {
        guard foundProposals else { return "It didn't propose anything." }
        var parts: [String] = []
        if addedSuggestions > 0 {
            parts.append("Added \(addedSuggestions) source\(addedSuggestions == 1 ? "" : "s") for you to judge.")
        }
        if addedReflections > 0 {
            parts.append("Added \(addedReflections) pattern\(addedReflections == 1 ? "" : "s") for you to check.")
        }
        if !skipped.isEmpty {
            let reasons = Set(skipped.map { $0.reason.rawValue.replacingOccurrences(of: "_", with: " ") })
                .sorted()
                .joined(separator: ", ")
            parts.append("Skipped \(skipped.count) (\(reasons)).")
        }
        return parts.isEmpty ? "Nothing new was added." : parts.joined(separator: " ")
    }
}
