import Foundation

/// The machine-facing API exposed by the macOS app's bundled `mood-agent`
/// helper. It never mutates `library.json` or `Media/`; the only write is
/// `save-essence`, which appends a revision under `Essences/`.
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
    case essenceStorageFailed(String)
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
        case .essenceStorageFailed(let message):
            "The saved essences could not be accessed: \(message)"
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
        case .storageUnavailable, .essenceStorageFailed:
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
    /// The user's own words about the item, distinct from captured `text`.
    public let note: String?
    public let verdict: InspirationVerdict?
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
        note = inspiration.note
        verdict = inspiration.verdict
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
    /// The user's own words about the item, distinct from captured `text`.
    public let note: String?
    public let verdict: InspirationVerdict?
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
        note = inspiration.note
        verdict = inspiration.verdict
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

public struct PinaxAgentEssenceSaveResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let outcome: DesignEssenceSaveOutcome
    public let project: PinaxAgentProject
    public let revision: DesignEssenceRevision
    public let schemaVersion: String
    public let referenceCount: Int

    public init(
        outcome: DesignEssenceSaveOutcome,
        project: PinaxAgentProject,
        revision: DesignEssenceRevision,
        essence: DesignEssence
    ) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        self.outcome = outcome
        self.project = project
        self.revision = revision
        schemaVersion = essence.schemaVersion
        referenceCount = essence.source.references.count
    }
}

/// How the project's current items differ from the items a saved essence was
/// distilled from. Identifiers are sorted for deterministic output.
public struct PinaxAgentEssenceStaleness: Codable, Equatable, Sendable {
    /// Items now in the project that the essence did not consider.
    public let addedAssetIDs: [Inspiration.ID]
    /// Referenced items that were deleted or moved out of the project.
    public let removedAssetIDs: [Inspiration.ID]
    /// Referenced items edited after the essence was extracted.
    public let changedAssetIDs: [Inspiration.ID]

    public init(
        addedAssetIDs: [Inspiration.ID],
        removedAssetIDs: [Inspiration.ID],
        changedAssetIDs: [Inspiration.ID]
    ) {
        self.addedAssetIDs = addedAssetIDs.sorted(by: Self.idSort)
        self.removedAssetIDs = removedAssetIDs.sorted(by: Self.idSort)
        self.changedAssetIDs = changedAssetIDs.sorted(by: Self.idSort)
    }

    public var isStale: Bool {
        !addedAssetIDs.isEmpty || !removedAssetIDs.isEmpty || !changedAssetIDs.isEmpty
    }

    private static func idSort(_ lhs: Inspiration.ID, _ rhs: Inspiration.ID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

public struct PinaxAgentEssenceResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let project: PinaxAgentProject
    public let revisionCount: Int
    /// The latest revision, or absent when the project has no saved essence.
    public let revision: DesignEssenceRevision?
    public let stale: Bool?
    public let staleness: PinaxAgentEssenceStaleness?
    public let essence: DesignEssence?

    public init(
        project: PinaxAgentProject,
        revisionCount: Int,
        latest: (revision: DesignEssenceRevision, essence: DesignEssence, staleness: PinaxAgentEssenceStaleness)?
    ) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        self.project = project
        self.revisionCount = revisionCount
        revision = latest?.revision
        stale = latest?.staleness.isStale
        staleness = latest?.staleness
        essence = latest?.essence
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
        } else if let storeError = error as? DesignEssenceStoreError {
            self.init(
                code: "storage_error",
                message: storeError.localizedDescription
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

/// Facade over the same coordinated repository used by Pinax's UI. Library
/// data is read-only; essences are appended to a separate local store.
public struct PinaxAgentAPI: Sendable {
    private static let maximumEssenceFileSize = 10 * 1_024 * 1_024

    public let repository: LibraryRepository
    public let essenceStore: DesignEssenceStore

    public init(repository: LibraryRepository) {
        self.repository = repository
        essenceStore = DesignEssenceStore(storageDirectory: repository.storageDirectory)
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
        PinaxAgentEssenceValidationResponse(
            essence: try readValidatedEssence(filePath: filePath, currentDirectory: currentDirectory)
        )
    }

    /// Validates a project essence, checks that every reference and quoted
    /// word traces back to the user's saved items, then appends it as a new
    /// revision. The library itself is never modified.
    public func saveEssence(filePath: String) async throws -> PinaxAgentEssenceSaveResponse {
        try await saveEssence(
            filePath: filePath,
            currentDirectory: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
        )
    }

    public func saveEssence(
        filePath: String,
        currentDirectory: URL
    ) async throws -> PinaxAgentEssenceSaveResponse {
        let essence = try Self.readValidatedEssence(
            filePath: filePath,
            currentDirectory: currentDirectory
        )
        guard essence.source.kind == .project,
              let projectID = essence.source.projectID else {
            throw PinaxAgentAPIError.invalidEssence(
                "Only a project essence can be saved. Single-image essences stay with the request that produced them."
            )
        }

        let snapshot = try await loadSnapshot()
        guard let project = snapshot.projects.first(where: { $0.id == projectID }) else {
            throw PinaxAgentAPIError.projectNotFound(projectID.uuidString)
        }
        try Self.validateTraceability(of: essence, to: project, in: snapshot)

        let result: (revision: DesignEssenceRevision, outcome: DesignEssenceSaveOutcome)
        do {
            result = try await essenceStore.save(essence)
        } catch {
            throw PinaxAgentAPIError.essenceStorageFailed(error.localizedDescription)
        }

        return PinaxAgentEssenceSaveResponse(
            outcome: result.outcome,
            project: PinaxAgentProject(
                project: project,
                inspirationCount: Self.inspirations(in: project, snapshot: snapshot).count
            ),
            revision: result.revision,
            essence: essence
        )
    }

    /// Returns the project's latest saved essence and whether the project has
    /// changed since it was extracted.
    public func essence(project reference: String) async throws -> PinaxAgentEssenceResponse {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReference.isEmpty else {
            throw PinaxAgentAPIError.invalidArguments("A project name or UUID is required.")
        }

        let snapshot = try await loadSnapshot()
        let project = try Self.resolveProject(reference: trimmedReference, in: snapshot.projects)
        let items = Self.inspirations(in: project, snapshot: snapshot)
        let projectRecord = PinaxAgentProject(project: project, inspirationCount: items.count)

        let revisionCount: Int
        let stored: (revision: DesignEssenceRevision, essence: DesignEssence)?
        do {
            revisionCount = try await essenceStore.revisionIDs(projectID: project.id).count
            stored = try await essenceStore.latest(projectID: project.id)
        } catch {
            throw PinaxAgentAPIError.essenceStorageFailed(error.localizedDescription)
        }

        guard let latest = stored else {
            return PinaxAgentEssenceResponse(
                project: projectRecord,
                revisionCount: revisionCount,
                latest: nil
            )
        }

        let staleness = Self.staleness(of: latest.essence, against: items)
        return PinaxAgentEssenceResponse(
            project: projectRecord,
            revisionCount: revisionCount,
            latest: (revision: latest.revision, essence: latest.essence, staleness: staleness)
        )
    }

    static func staleness(
        of essence: DesignEssence,
        against items: [Inspiration]
    ) -> PinaxAgentEssenceStaleness {
        let referencedIDs = Set(essence.source.assetIDs)
        let currentIDs = Set(items.map(\.id))
        let extractedAt = essence.provenance.extractedAt
        return PinaxAgentEssenceStaleness(
            addedAssetIDs: Array(currentIDs.subtracting(referencedIDs)),
            removedAssetIDs: Array(referencedIDs.subtracting(currentIDs)),
            changedAssetIDs: items
                .filter { referencedIDs.contains($0.id) && $0.updatedAt > extractedAt }
                .map(\.id)
        )
    }

    /// Every reference must be a saved item in the essence's project, and
    /// every quote must be words that item actually holds, so no saved rule
    /// can cite a source the user did not choose.
    static func validateTraceability(
        of essence: DesignEssence,
        to project: Project,
        in snapshot: LibrarySnapshot
    ) throws {
        let itemsByID = Dictionary(
            snapshot.inspirations.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (index, reference) in essence.source.references.enumerated() {
            guard let item = itemsByID[reference.assetID],
                  item.projectID == project.id else {
                throw PinaxAgentAPIError.invalidEssence(
                    "source.references[\(index)].assetID: \(reference.assetID.uuidString) is not a saved item in the project \"\(project.name)\"."
                )
            }
        }

        for cited in essence.citedEvidence {
            let evidence = cited.evidence
            guard evidence.citedField.isTextual,
                  let quote = evidence.quote,
                  let item = itemsByID[evidence.assetID] else { continue }

            guard let fieldValue = citableText(evidence.citedField, of: item) else {
                throw PinaxAgentAPIError.invalidEssence(
                    "\(cited.path).field: This library does not store a separate \(evidence.citedField.rawValue) for items yet. Cite the item's `text` instead."
                )
            }
            guard normalizedQuoteText(fieldValue).contains(normalizedQuoteText(quote)) else {
                throw PinaxAgentAPIError.invalidEssence(
                    "\(cited.path).quote: The quote does not appear in the \(evidence.citedField.rawValue) of item \(evidence.assetID.uuidString)."
                )
            }
        }
    }

    private static func citableText(
        _ field: DesignEssence.Evidence.Field,
        of item: Inspiration
    ) -> String? {
        switch field {
        case .image:
            nil
        case .title:
            item.title
        case .text:
            item.text
        case .note:
            // A separate per-item note is being added to `Inspiration`; until
            // it lands, the user's typed note lives in `text`.
            nil
        }
    }

    private static func normalizedQuoteText(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func inspirations(in project: Project, snapshot: LibrarySnapshot) -> [Inspiration] {
        LibraryRepository.filteredInspirations(in: snapshot, scope: .project(project.id))
    }

    private static func readValidatedEssence(
        filePath: String,
        currentDirectory: URL
    ) throws -> DesignEssence {
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
            return essence
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
    case saveEssence(file: String, prettyPrinted: Bool)
    case essence(project: String, prettyPrinted: Bool)

    public var prettyPrinted: Bool {
        switch self {
        case .projects(let prettyPrinted),
             .inspirations(_, let prettyPrinted),
             .inspiration(_, let prettyPrinted),
             .validateEssence(_, let prettyPrinted),
             .saveEssence(_, let prettyPrinted),
             .essence(_, let prettyPrinted):
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

        case "validate-essence", "save-essence":
            guard remaining.count == 2, remaining[0] == "--file" else {
                throw PinaxAgentAPIError.invalidArguments(
                    "Use `\(command) --file <path>` with an optional `--pretty` flag."
                )
            }
            let filePath = remaining[1]
            guard !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !filePath.contains("\0") else {
                throw PinaxAgentAPIError.invalidArguments("A readable JSON file path is required.")
            }
            return command == "save-essence"
                ? .saveEssence(file: filePath, prettyPrinted: prettyPrinted)
                : .validateEssence(file: filePath, prettyPrinted: prettyPrinted)

        case "essence":
            guard remaining.count == 2, remaining[0] == "--project" else {
                throw PinaxAgentAPIError.invalidArguments(
                    "Use `essence --project <name-or-uuid>` with an optional `--pretty` flag."
                )
            }
            let reference = remaining[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reference.isEmpty else {
                throw PinaxAgentAPIError.invalidArguments("A project name or UUID is required.")
            }
            return .essence(project: reference, prettyPrinted: prettyPrinted)

        default:
            throw PinaxAgentAPIError.invalidArguments(Self.usage)
        }
    }

    public static let usage = "Usage: mood-agent projects [--pretty] | mood-agent inspirations --project <name-or-uuid> [--pretty] | mood-agent inspiration --id <uuid> [--pretty] | mood-agent validate-essence --file <path> [--pretty] | mood-agent save-essence --file <path> [--pretty] | mood-agent essence --project <name-or-uuid> [--pretty]"
}
