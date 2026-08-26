import Foundation

/// The read-only, machine-facing API exposed by the macOS app's bundled
/// `mood-agent` helper.
public enum PinaxAgentAPIVersion {
    public static let current = 1
}

public enum PinaxAgentAPIError: Error, Equatable, Sendable {
    case invalidArguments(String)
    case projectNotFound(String)
    case ambiguousProject(String)
    case storageUnavailable(String)
}

extension PinaxAgentAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            message
        case .projectNotFound(let reference):
            "No mood. project matches \"\(reference)\". Call `projects` to list available projects."
        case .ambiguousProject(let reference):
            "More than one mood. project matches \"\(reference)\". Use the project UUID instead."
        case .storageUnavailable(let message):
            "The mood. library could not be read: \(message)"
        }
    }

    public var code: String {
        switch self {
        case .invalidArguments:
            "invalid_arguments"
        case .projectNotFound:
            "project_not_found"
        case .ambiguousProject:
            "ambiguous_project"
        case .storageUnavailable:
            "storage_error"
        }
    }
}

public struct PinaxAgentProject: Codable, Equatable, Sendable {
    public let id: Project.ID
    public let name: String
    public let colorHex: String?
    public let inspirationCount: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(project: Project, inspirationCount: Int) {
        id = project.id
        name = project.name
        colorHex = project.colorHex
        self.inspirationCount = inspirationCount
        createdAt = project.createdAt
        updatedAt = project.updatedAt
    }
}

public struct PinaxAgentInspiration: Codable, Equatable, Sendable {
    public let id: Inspiration.ID
    public let projectID: Project.ID
    public let source: CaptureSource
    public let url: URL
    public let canonicalURL: URL
    public let title: String
    public let text: String
    public let authorName: String?
    public let authorHandle: String?
    public let imageURL: URL?
    /// Absolute path to media stored by Pinax, when the inspiration has a local image.
    public let localImagePath: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let lastCapturedAt: Date
    public let captureCount: Int

    public init(
        inspiration: Inspiration,
        projectID: Project.ID,
        repository: LibraryRepository
    ) {
        id = inspiration.id
        self.projectID = projectID
        source = inspiration.source
        url = inspiration.url
        canonicalURL = inspiration.canonicalURL
        title = inspiration.title
        text = inspiration.text
        authorName = inspiration.authorName
        authorHandle = inspiration.authorHandle
        imageURL = inspiration.imageURL
        localImagePath = repository.localImageURL(for: inspiration)?.path
        createdAt = inspiration.createdAt
        updatedAt = inspiration.updatedAt
        lastCapturedAt = inspiration.lastCapturedAt
        captureCount = inspiration.captureCount
    }
}

public struct PinaxAgentProjectsResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let count: Int
    public let projects: [PinaxAgentProject]

    public init(projects: [PinaxAgentProject]) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        count = projects.count
        self.projects = projects
    }
}

public struct PinaxAgentInspirationsResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let project: PinaxAgentProject
    public let count: Int
    public let inspirations: [PinaxAgentInspiration]

    public init(project: PinaxAgentProject, inspirations: [PinaxAgentInspiration]) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        self.project = project
        count = inspirations.count
        self.inspirations = inspirations
    }
}

public struct PinaxAgentErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct PinaxAgentErrorResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let error: PinaxAgentErrorPayload

    public init(code: String, message: String) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = false
        error = PinaxAgentErrorPayload(code: code, message: message)
    }

    public init(error: any Error) {
        if let apiError = error as? PinaxAgentAPIError {
            self.init(
                code: apiError.code,
                message: apiError.localizedDescription
            )
        } else if let repositoryError = error as? LibraryRepositoryError {
            self.init(
                code: "storage_error",
                message: repositoryError.localizedDescription
            )
        } else {
            self.init(
                code: "internal_error",
                message: error.localizedDescription
            )
        }
    }
}

/// Read-only facade over the same coordinated repository used by Pinax's UI.
public struct PinaxAgentAPI: Sendable {
    public let repository: LibraryRepository

    public init(repository: LibraryRepository) {
        self.repository = repository
    }

    public func projects() async throws -> PinaxAgentProjectsResponse {
        let snapshot = try await loadSnapshot()
        let counts = LibraryRepository.counts(in: snapshot)
        let projects = snapshot.projects
            .sorted(by: Self.projectSort)
            .map { project in
                PinaxAgentProject(
                    project: project,
                    inspirationCount: counts[project.id]
                )
            }
        return PinaxAgentProjectsResponse(projects: projects)
    }

    public func inspirations(project reference: String) async throws -> PinaxAgentInspirationsResponse {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReference.isEmpty else {
            throw PinaxAgentAPIError.invalidArguments("A project name or UUID is required.")
        }

        let snapshot = try await loadSnapshot()
        let project = try Self.resolveProject(reference: trimmedReference, in: snapshot.projects)
        let inspirations = LibraryRepository.filteredInspirations(
            in: snapshot,
            scope: .project(project.id)
        )
        let records = inspirations.map {
            PinaxAgentInspiration(
                inspiration: $0,
                projectID: project.id,
                repository: repository
            )
        }
        let projectRecord = PinaxAgentProject(
            project: project,
            inspirationCount: records.count
        )
        return PinaxAgentInspirationsResponse(
            project: projectRecord,
            inspirations: records
        )
    }

    private static func resolveProject(reference: String, in projects: [Project]) throws -> Project {
        if let id = UUID(uuidString: reference),
           let project = projects.first(where: { $0.id == id }) {
            return project
        }

        let normalizedReference = normalizedProjectName(reference)
        let matches = projects.filter {
            normalizedProjectName($0.name) == normalizedReference
        }
        guard !matches.isEmpty else {
            throw PinaxAgentAPIError.projectNotFound(reference)
        }
        guard matches.count == 1, let project = matches.first else {
            throw PinaxAgentAPIError.ambiguousProject(reference)
        }
        return project
    }

    private func loadSnapshot() async throws -> LibrarySnapshot {
        do {
            return try await repository.load()
        } catch {
            throw PinaxAgentAPIError.storageUnavailable(error.localizedDescription)
        }
    }

    private static func normalizedProjectName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static func projectSort(_ lhs: Project, _ rhs: Project) -> Bool {
        let leftName = normalizedProjectName(lhs.name)
        let rightName = normalizedProjectName(rhs.name)
        if leftName != rightName { return leftName < rightName }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum PinaxAgentCommand: Equatable, Sendable {
    case projects(prettyPrinted: Bool)
    case inspirations(project: String, prettyPrinted: Bool)

    public var prettyPrinted: Bool {
        switch self {
        case .projects(let prettyPrinted), .inspirations(_, let prettyPrinted):
            prettyPrinted
        }
    }

    public static func parse(arguments: [String]) throws -> PinaxAgentCommand {
        guard let command = arguments.first else {
            throw PinaxAgentAPIError.invalidArguments(Self.usage)
        }

        var remaining = Array(arguments.dropFirst())
        let prettyPrinted = remaining.contains("--pretty")
        remaining.removeAll(where: { $0 == "--pretty" })

        switch command {
        case "projects":
            guard remaining.isEmpty else {
                throw PinaxAgentAPIError.invalidArguments("`projects` accepts only the optional `--pretty` flag.")
            }
            return .projects(prettyPrinted: prettyPrinted)

        case "inspirations":
            guard remaining.count == 2, remaining[0] == "--project" else {
                throw PinaxAgentAPIError.invalidArguments(
                    "Use `inspirations --project <name-or-uuid>` with an optional `--pretty` flag."
                )
            }
            let reference = remaining[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reference.isEmpty else {
                throw PinaxAgentAPIError.invalidArguments("A project name or UUID is required.")
            }
            return .inspirations(project: reference, prettyPrinted: prettyPrinted)

        default:
            throw PinaxAgentAPIError.invalidArguments(Self.usage)
        }
    }

    public static let usage = "Usage: mood-agent projects [--pretty] | mood-agent inspirations --project <name-or-uuid> [--pretty]"
}
