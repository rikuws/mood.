import Foundation

public extension LibraryStore {
    func study(for projectID: Project.ID) -> ProjectStudy? {
        snapshot.project(id: projectID)?.study
    }

    func studyItems(for projectID: Project.ID) -> [Inspiration] {
        LibraryRepository.filteredInspirations(in: snapshot, scope: .project(projectID))
    }

    func studyStage(for projectID: Project.ID) -> StudyStage? {
        study(for: projectID)?.stage(itemCount: studyItems(for: projectID).count)
    }

    @discardableResult
    func createStudy(
        subject: String,
        brief: String = "",
        name: String? = nil,
        colorHex: String? = nil
    ) async throws -> Project {
        try await performStudyChange {
            try await self.repository.createStudy(
                subject: subject,
                brief: brief,
                name: name,
                colorHex: colorHex
            )
        }
    }

    @discardableResult
    func startStudy(
        projectID: Project.ID,
        subject: String,
        brief: String = ""
    ) async throws -> Project {
        try await performStudyChange {
            try await self.repository.startStudy(
                projectID: projectID,
                subject: subject,
                brief: brief
            )
        }
    }

    @discardableResult
    func decideStudySuggestion(
        projectID: Project.ID,
        suggestionID: StudySuggestion.ID,
        verdict: StudyVerdict,
        reason: String?
    ) async throws -> StudySuggestion {
        let suggestion = try await performStudyChange {
            try await self.repository.decideStudySuggestion(
                projectID: projectID,
                suggestionID: suggestionID,
                verdict: verdict,
                reason: reason
            )
        }
        if verdict == .keep, let savedID = suggestion.savedInspirationID {
            _ = await fillMissingPreview(for: savedID)
        }
        return suggestion
    }

    @discardableResult
    func respondToStudyReflection(
        projectID: Project.ID,
        reflectionID: StudyReflection.ID,
        response: StudyReflectionResponse
    ) async throws -> StudyReflection {
        try await performStudyChange {
            try await self.repository.respondToStudyReflection(
                projectID: projectID,
                reflectionID: reflectionID,
                response: response
            )
        }
    }

    private func performStudyChange<Value: Sendable>(
        _ body: () async throws -> Value
    ) async throws -> Value {
        do {
            let value = try await body()
            try await refreshSnapshot()
            return value
        } catch {
            record(error)
            throw error
        }
    }
}
