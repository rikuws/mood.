import Foundation

/// The read-only, machine-facing API exposed by the macOS app's bundled
/// `mood-agent` helper.
public enum PinaxAgentAPIVersion {
    public static let current = 1
}

/// Cross-target implementation detail shared with the bundled executable.
/// The versioned CLI JSON, not this Swift enum, is the compatibility surface.
public enum PinaxAgentAPIError: Error, Equatable, Sendable {
    case invalidArguments(String)
    case projectNotFound(String)
    case ambiguousProject(String)
    case inspirationNotFound(String)
    case invalidEssence(String)
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
        case .inspirationNotFound(let reference):
            "No mood. item matches \"\(reference)\". Use an item UUID returned by `inspirations`."
        case .invalidEssence(let message):
            "The DesignEssence document is invalid: \(message)"
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
        case .inspirationNotFound:
            "inspiration_not_found"
        case .invalidEssence:
            "invalid_essence"
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

/// General-capable representation used by the exact single-item command.
/// The existing project-list DTO above intentionally keeps its nonoptional
/// `projectID` source contract.
public struct PinaxAgentSavedInspiration: Codable, Equatable, Sendable {
    public let id: Inspiration.ID
    public let projectID: Project.ID?
    public let source: CaptureSource
    public let url: URL
    public let canonicalURL: URL
    public let title: String
    public let text: String
    public let authorName: String?
    public let authorHandle: String?
    public let imageURL: URL?
    public let localImagePath: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let lastCapturedAt: Date
    public let captureCount: Int

    public init(inspiration: Inspiration, repository: LibraryRepository) {
        id = inspiration.id
        projectID = inspiration.projectID
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

public struct PinaxAgentInspirationResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let project: PinaxAgentProject?
    public let inspiration: PinaxAgentSavedInspiration

    public init(project: PinaxAgentProject?, inspiration: PinaxAgentSavedInspiration) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        self.project = project
        self.inspiration = inspiration
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

public struct PinaxAgentEssenceValidationResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let valid: Bool
    public let schemaVersion: String
    public let sourceKind: DesignEssence.Source.Kind
    public let referenceCount: Int

    public init(essence: DesignEssence) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        valid = true
        schemaVersion = essence.schemaVersion
        sourceKind = essence.source.kind
        referenceCount = essence.source.references.count
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
    private static let maximumEssenceFileSize = 10 * 1_024 * 1_024

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

    public func inspiration(id reference: String) async throws -> PinaxAgentInspirationResponse {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: trimmedReference) else {
            throw PinaxAgentAPIError.invalidArguments("A valid mood. item UUID is required.")
        }

        let snapshot = try await loadSnapshot()
        guard let inspiration = snapshot.inspirations.first(where: { $0.id == id }) else {
            throw PinaxAgentAPIError.inspirationNotFound(trimmedReference)
        }

        let project = inspiration.projectID.flatMap { projectID in
            snapshot.projects.first(where: { $0.id == projectID })
        }
        let projectRecord = project.map { project in
            PinaxAgentProject(
                project: project,
                inspirationCount: snapshot.inspirations.filter { $0.projectID == project.id }.count
            )
        }
        let record = PinaxAgentSavedInspiration(
            inspiration: inspiration,
            repository: repository
        )
        return PinaxAgentInspirationResponse(
            project: projectRecord,
            inspiration: record
        )
    }

    /// Decodes and validates a generated DesignEssence document without reading
    /// or mutating the mood. library.
    public static func validateEssence(
        filePath: String
    ) throws -> PinaxAgentEssenceValidationResponse {
        try validateEssence(
            filePath: filePath,
            currentDirectory: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
        )
    }

    public static func validateEssence(
        filePath: String,
        currentDirectory: URL
    ) throws -> PinaxAgentEssenceValidationResponse {
        guard !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !filePath.contains("\0") else {
            throw PinaxAgentAPIError.invalidArguments("A readable JSON file path is required.")
        }

        let expandedPath = (filePath as NSString).expandingTildeInPath
        let fileURL = (expandedPath.hasPrefix("/")
            ? URL(fileURLWithPath: expandedPath, isDirectory: false)
            : currentDirectory.appendingPathComponent(expandedPath, isDirectory: false))
            .standardizedFileURL

        do {
            let resourceValues = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isReadableKey, .isRegularFileKey]
            )
            guard resourceValues.isRegularFile == true, resourceValues.isReadable == true else {
                throw PinaxAgentAPIError.invalidEssence("The path must identify a readable regular file.")
            }
            guard let fileSize = resourceValues.fileSize,
                  fileSize <= maximumEssenceFileSize else {
                throw PinaxAgentAPIError.invalidEssence("The JSON file exceeds the 10 MiB validation limit.")
            }

            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard data.count <= maximumEssenceFileSize else {
                throw PinaxAgentAPIError.invalidEssence("The JSON file exceeds the 10 MiB validation limit.")
            }
            let essence = try JSONDecoder().decode(DesignEssence.self, from: data)
            try DesignEssenceValidator.validate(essence)
            return PinaxAgentEssenceValidationResponse(essence: essence)
        } catch let error as PinaxAgentAPIError {
            throw error
        } catch let error as DesignEssenceValidationError {
            throw PinaxAgentAPIError.invalidEssence(error.localizedDescription)
        } catch let error as DecodingError {
            throw PinaxAgentAPIError.invalidEssence(
                "The JSON does not match DesignEssence 1.0 (\(error.localizedDescription))."
            )
        } catch {
            throw PinaxAgentAPIError.invalidEssence("The file could not be read (\(error.localizedDescription)).")
        }
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

/// Cross-target command model for `mood-agent`; not a source-stable client SDK.
public enum PinaxAgentCommand: Equatable, Sendable {
    case projects(prettyPrinted: Bool)
    case inspirations(project: String, prettyPrinted: Bool)
    case inspiration(id: String, prettyPrinted: Bool)
    case validateEssence(file: String, prettyPrinted: Bool)

    public var prettyPrinted: Bool {
        switch self {
        case .projects(let prettyPrinted),
             .inspirations(_, let prettyPrinted),
             .inspiration(_, let prettyPrinted),
             .validateEssence(_, let prettyPrinted):
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

        case "inspiration":
            guard remaining.count == 2, remaining[0] == "--id" else {
                throw PinaxAgentAPIError.invalidArguments(
                    "Use `inspiration --id <uuid>` with an optional `--pretty` flag."
                )
            }
            let reference = remaining[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard UUID(uuidString: reference) != nil else {
                throw PinaxAgentAPIError.invalidArguments("A valid mood. item UUID is required.")
            }
            return .inspiration(id: reference, prettyPrinted: prettyPrinted)

        case "validate-essence":
            guard remaining.count == 2, remaining[0] == "--file" else {
                throw PinaxAgentAPIError.invalidArguments(
                    "Use `validate-essence --file <path>` with an optional `--pretty` flag."
                )
            }
            let filePath = remaining[1]
            guard !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !filePath.contains("\0") else {
                throw PinaxAgentAPIError.invalidArguments("A readable JSON file path is required.")
            }
            return .validateEssence(file: filePath, prettyPrinted: prettyPrinted)

        default:
            throw PinaxAgentAPIError.invalidArguments(Self.usage)
        }
    }

    public static let usage = "Usage: mood-agent projects [--pretty] | mood-agent inspirations --project <name-or-uuid> [--pretty] | mood-agent inspiration --id <uuid> [--pretty] | mood-agent validate-essence --file <path> [--pretty]"
}
