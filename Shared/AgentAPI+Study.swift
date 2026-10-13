import Foundation

/// A study as an agent sees it: the subject and brief in the user's words,
/// the seeds and keeps on its moodboard, and every verdict and reason so far.
public struct PinaxAgentStudy: Codable, Equatable, Sendable {
    public let subject: String
    public let brief: String
    public let startedAt: Date
    public let stage: StudyStage
    /// Everything on the study's moodboard: the user's seeds and kept
    /// suggestions. Look at these before proposing anything.
    public let items: [PinaxAgentInspiration]
    public let suggestions: [StudySuggestion]
    public let reflections: [StudyReflection]

    public init(
        study: ProjectStudy,
        items: [PinaxAgentInspiration]
    ) {
        subject = study.subject
        brief = study.brief
        startedAt = study.startedAt
        stage = study.stage(itemCount: items.count)
        self.items = items
        suggestions = study.suggestions
        reflections = study.reflections
    }
}

public struct PinaxAgentStudyResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let project: PinaxAgentProject
    public let study: PinaxAgentStudy

    public init(project: PinaxAgentProject, study: PinaxAgentStudy) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        self.project = project
        self.study = study
    }
}

public struct PinaxAgentSuggestResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let project: PinaxAgentProject
    public let added: [StudySuggestion]
    public let skipped: [StudySuggestionSkip]

    public init(project: PinaxAgentProject, result: StudySuggestionBatchResult) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        self.project = project
        added = result.added
        skipped = result.skipped
    }
}

public struct PinaxAgentReflectResponse: Codable, Equatable, Sendable {
    public let apiVersion: Int
    public let ok: Bool
    public let project: PinaxAgentProject
    public let added: [StudyReflection]

    public init(project: PinaxAgentProject, added: [StudyReflection]) {
        apiVersion = PinaxAgentAPIVersion.current
        ok = true
        self.project = project
        self.added = added
    }
}

/// File body accepted by `suggest --file`.
public struct PinaxAgentSuggestInput: Codable, Equatable, Sendable {
    public var suggestions: [StudySuggestionDraft]

    public init(suggestions: [StudySuggestionDraft]) {
        self.suggestions = suggestions
    }
}

/// File body accepted by `reflect --file`.
public struct PinaxAgentReflectInput: Codable, Equatable, Sendable {
    public var reflections: [StudyReflectionDraft]

    public init(reflections: [StudyReflectionDraft]) {
        self.reflections = reflections
    }
}

/// Study commands. `study` reads; `suggest` and `reflect` only add proposals
/// that wait for the user. No command can keep, reject, confirm, or correct:
/// those decisions are made by the user in mood.
public extension PinaxAgentAPI {
    private static let maximumBatchCount = 50

    func study(project reference: String) async throws -> PinaxAgentStudyResponse {
        let snapshot = try await loadSnapshot()
        let project = try Self.resolveProject(reference: reference, in: snapshot.projects)
        guard let study = project.study else {
            throw PinaxAgentAPIError.notAStudy(project.name)
        }
        let items = LibraryRepository.filteredInspirations(in: snapshot, scope: .project(project.id))
            .map { PinaxAgentInspiration(inspiration: $0, projectID: project.id, repository: repository) }
        return PinaxAgentStudyResponse(
            project: PinaxAgentProject(project: project, inspirationCount: items.count),
            study: PinaxAgentStudy(study: study, items: items)
        )
    }

    func suggest(
        project reference: String,
        filePath: String,
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) async throws -> PinaxAgentSuggestResponse {
        let input: PinaxAgentSuggestInput = try Self.decodeStudyInput(
            filePath: filePath,
            currentDirectory: currentDirectory
        )
        guard !input.suggestions.isEmpty else {
            throw PinaxAgentAPIError.invalidStudyInput("`suggestions` is empty.")
        }
        guard input.suggestions.count <= Self.maximumBatchCount else {
            throw PinaxAgentAPIError.invalidStudyInput(
                "Propose at most \(Self.maximumBatchCount) suggestions at a time."
            )
        }

        let project = try await studyProject(reference)
        let result = try await performStudyWrite {
            try await repository.addStudySuggestions(
                projectID: project.id,
                drafts: input.suggestions
            )
        }
        return PinaxAgentSuggestResponse(
            project: try await projectRecord(project.id),
            result: result
        )
    }

    func reflect(
        project reference: String,
        filePath: String,
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) async throws -> PinaxAgentReflectResponse {
        let input: PinaxAgentReflectInput = try Self.decodeStudyInput(
            filePath: filePath,
            currentDirectory: currentDirectory
        )
        guard !input.reflections.isEmpty else {
            throw PinaxAgentAPIError.invalidStudyInput("`reflections` is empty.")
        }
        guard input.reflections.count <= Self.maximumBatchCount else {
            throw PinaxAgentAPIError.invalidStudyInput(
                "Propose at most \(Self.maximumBatchCount) patterns at a time."
            )
        }

        let project = try await studyProject(reference)
        let added = try await performStudyWrite {
            try await repository.addStudyReflections(
                projectID: project.id,
                drafts: input.reflections
            )
        }
        return PinaxAgentReflectResponse(
            project: try await projectRecord(project.id),
            added: added
        )
    }

    private func studyProject(_ reference: String) async throws -> Project {
        let snapshot = try await loadSnapshot()
        let project = try Self.resolveProject(reference: reference, in: snapshot.projects)
        guard project.study != nil else {
            throw PinaxAgentAPIError.notAStudy(project.name)
        }
        return project
    }

    private func projectRecord(_ id: Project.ID) async throws -> PinaxAgentProject {
        let snapshot = try await loadSnapshot()
        guard let project = snapshot.project(id: id) else {
            throw PinaxAgentAPIError.projectNotFound(id.uuidString)
        }
        return PinaxAgentProject(
            project: project,
            inspirationCount: LibraryRepository.counts(in: snapshot)[id]
        )
    }

    private func performStudyWrite<Value: Sendable>(
        _ body: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await body()
        } catch let error as LibraryStudyError {
            switch error {
            case .notAStudy(let id):
                throw PinaxAgentAPIError.notAStudy(id.uuidString)
            default:
                throw PinaxAgentAPIError.invalidStudyInput(error.localizedDescription)
            }
        } catch let error as LibraryRepositoryError {
            if case .projectNotFound(let id) = error {
                throw PinaxAgentAPIError.projectNotFound(id.uuidString)
            }
            throw PinaxAgentAPIError.storageUnavailable(error.localizedDescription)
        }
    }

    private static func decodeStudyInput<Input: Decodable>(
        filePath: String,
        currentDirectory: URL
    ) throws -> Input {
        let data = try readBoundedJSONFile(
            filePath: filePath,
            currentDirectory: currentDirectory,
            invalid: PinaxAgentAPIError.invalidStudyInput
        )
        do {
            return try JSONDecoder().decode(Input.self, from: data)
        } catch let error as DecodingError {
            throw PinaxAgentAPIError.invalidStudyInput(
                "The JSON does not match the expected shape (\(error.agentDescription))."
            )
        } catch {
            throw PinaxAgentAPIError.invalidStudyInput(
                "The JSON does not match the expected shape (\(error.localizedDescription))."
            )
        }
    }
}
