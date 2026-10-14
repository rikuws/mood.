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

    public static func proposalsFilename(for task: StudyAgentTask) -> String {
        switch task {
        case .findSources: suggestionsFilename
        case .reflect: reflectionsFilename
        }
    }

    /// Writes the study as `mood-agent study` prints it.
    public static func prepare(
        api: PinaxAgentAPI,
        projectID: Project.ID,
        in directory: URL
    ) async throws {
        let response = try await api.study(project: projectID.uuidString)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(response).write(
            to: directory.appendingPathComponent(studyFilename, isDirectory: false),
            options: .atomic
        )
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
