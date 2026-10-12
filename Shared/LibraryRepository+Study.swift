import Foundation

public enum LibraryStudyError: Error, Equatable, Sendable {
    case invalidSubject
    case notAStudy(Project.ID)
    case suggestionNotFound(StudySuggestion.ID)
    case reflectionNotFound(StudyReflection.ID)
    case suggestionAlreadyKept(StudySuggestion.ID)
    case invalidReflection(String)
    case emptyCorrection
}

extension LibraryStudyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSubject:
            "A study needs a subject."
        case .notAStudy:
            "This project is not a visual study."
        case .suggestionNotFound:
            "That suggestion is no longer part of the study."
        case .reflectionNotFound:
            "That pattern is no longer part of the study."
        case .suggestionAlreadyKept:
            "This suggestion is already on the moodboard. Delete the item to remove it."
        case .invalidReflection(let message):
            "The pattern can't be added: \(message)"
        case .emptyCorrection:
            "Write how the pattern should read instead."
        }
    }
}

public extension LibraryRepository {
    /// Creates a new project that starts as a guided visual study.
    @discardableResult
    func createStudy(
        subject: String,
        brief: String = "",
        name: String? = nil,
        colorHex: String? = nil
    ) throws -> Project {
        try mutate { snapshot, now in
            let subject = Self.cleaned(subject)
            guard !subject.isEmpty else { throw LibraryStudyError.invalidSubject }
            let name = Self.cleaned(name ?? subject)
            guard !name.isEmpty else { throw LibraryRepositoryError.invalidProjectName }
            guard !Self.hasProject(named: name, in: snapshot) else {
                throw LibraryRepositoryError.duplicateProjectName
            }

            let project = Project(
                name: name,
                colorHex: Self.cleanedOptional(colorHex),
                study: ProjectStudy(
                    subject: subject,
                    brief: Self.cleaned(brief),
                    startedAt: now
                ),
                createdAt: now
            )
            snapshot.projects.append(project)
            return project
        }
    }

    /// Turns an existing project into a study, or updates the subject and
    /// brief of one that already is. Its items become the study's seeds.
    @discardableResult
    func startStudy(
        projectID: Project.ID,
        subject: String,
        brief: String = ""
    ) throws -> Project {
        try mutate { snapshot, now in
            guard let index = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
                throw LibraryRepositoryError.projectNotFound(projectID)
            }
            let subject = Self.cleaned(subject)
            guard !subject.isEmpty else { throw LibraryStudyError.invalidSubject }

            var study = snapshot.projects[index].study
                ?? ProjectStudy(subject: subject, startedAt: now)
            study.subject = subject
            study.brief = Self.cleaned(brief)
            snapshot.projects[index].study = study
            snapshot.projects[index].updatedAt = now
            return snapshot.projects[index]
        }
    }

    /// Adds agent-proposed sources as pending suggestions. Each draft is
    /// checked on its own; refused drafts are reported, not stored. URLs the
    /// user already saved, is still judging, or rejected are never re-added.
    @discardableResult
    func addStudySuggestions(
        projectID: Project.ID,
        drafts: [StudySuggestionDraft]
    ) throws -> StudySuggestionBatchResult {
        try mutate { snapshot, now in
            let index = try Self.studyProjectIndex(projectID, in: snapshot)
            guard var study = snapshot.projects[index].study else {
                throw LibraryStudyError.notAStudy(projectID)
            }

            let projectItems = snapshot.inspirations.filter { $0.projectID == projectID }
            let projectItemIDs = Set(projectItems.map(\.id))
            let savedURLs = Set(projectItems.map(\.canonicalURL.absoluteString))
            var rejectedURLs = Set<String>()
            var pendingURLs = Set<String>()
            for suggestion in study.suggestions {
                switch suggestion.status {
                case .rejected: rejectedURLs.insert(suggestion.canonicalURL.absoluteString)
                case .pending: pendingURLs.insert(suggestion.canonicalURL.absoluteString)
                case .kept: break
                }
            }

            var added: [StudySuggestion] = []
            var skipped: [StudySuggestionSkip] = []
            var batchURLs = Set<String>()

            for draft in drafts {
                let reported = draft.url.absoluteString
                guard let canonicalURL = try? CanonicalURL.canonicalize(draft.url) else {
                    skipped.append(StudySuggestionSkip(url: reported, reason: .invalidURL))
                    continue
                }
                if let imageURL = draft.imageURL,
                   (try? CanonicalURL.canonicalize(imageURL)) == nil {
                    skipped.append(StudySuggestionSkip(url: reported, reason: .invalidURL))
                    continue
                }
                if StudySourcePolicy.isGeneratedImageryHost(draft.url)
                    || StudySourcePolicy.isGeneratedImageryHost(draft.imageURL) {
                    skipped.append(StudySuggestionSkip(url: reported, reason: .generatedImagery))
                    continue
                }

                let title = Self.cleaned(draft.title)
                let creator = Self.cleaned(draft.creator)
                let rationale = Self.cleaned(draft.rationale)
                let basis = Self.orderedUnique(draft.basedOnInspirationIDs ?? [])
                let key = canonicalURL.absoluteString

                let skipReason: StudySuggestionSkipReason? =
                    if title.isEmpty { .missingTitle }
                    else if creator.isEmpty { .missingCreator }
                    else if rationale.isEmpty { .missingRationale }
                    else if !basis.allSatisfy(projectItemIDs.contains) { .unknownBasis }
                    else if rejectedURLs.contains(key) { .previouslyRejected }
                    else if savedURLs.contains(key) { .alreadySaved }
                    else if pendingURLs.contains(key) { .alreadySuggested }
                    else if batchURLs.contains(key) { .duplicateInBatch }
                    else { nil }
                if let skipReason {
                    skipped.append(StudySuggestionSkip(url: reported, reason: skipReason))
                    continue
                }

                batchURLs.insert(key)
                added.append(
                    StudySuggestion(
                        url: draft.url,
                        canonicalURL: canonicalURL,
                        title: title,
                        creator: creator,
                        sourceName: Self.cleanedOptional(draft.sourceName),
                        imageURL: draft.imageURL,
                        rationale: rationale,
                        basedOnInspirationIDs: basis,
                        suggestedAt: now
                    )
                )
            }

            if !added.isEmpty {
                study.suggestions.append(contentsOf: added)
                snapshot.projects[index].study = study
                snapshot.projects[index].updatedAt = now
            }
            return StudySuggestionBatchResult(added: added, skipped: skipped)
        }
    }

    /// Records the user's verdict and reason. Keeping saves the source to the
    /// study's moodboard; rejecting keeps it in the study as contrast. A
    /// rejected suggestion can be reconsidered and kept later.
    @discardableResult
    func decideStudySuggestion(
        projectID: Project.ID,
        suggestionID: StudySuggestion.ID,
        verdict: StudyVerdict,
        reason: String?
    ) throws -> StudySuggestion {
        try mutate { snapshot, now in
            let projectIndex = try Self.studyProjectIndex(projectID, in: snapshot)
            guard var study = snapshot.projects[projectIndex].study else {
                throw LibraryStudyError.notAStudy(projectID)
            }
            guard let index = study.suggestions.firstIndex(where: { $0.id == suggestionID }) else {
                throw LibraryStudyError.suggestionNotFound(suggestionID)
            }

            var suggestion = study.suggestions[index]
            suggestion.reason = Self.cleanedOptional(reason)
            suggestion.decidedAt = now

            switch verdict {
            case .reject:
                guard suggestion.status != .kept else {
                    throw LibraryStudyError.suggestionAlreadyKept(suggestionID)
                }
                suggestion.status = .rejected

            case .keep:
                if suggestion.status != .kept {
                    suggestion.savedInspirationID = Self.saveKeptSuggestion(
                        suggestion,
                        to: projectID,
                        in: &snapshot,
                        at: now
                    )
                }
                suggestion.status = .kept
            }

            study.suggestions[index] = suggestion
            snapshot.projects[projectIndex].study = study
            snapshot.projects[projectIndex].updatedAt = now
            return suggestion
        }
    }

    /// Adds agent-noticed patterns for the user to confirm or correct. Every
    /// pattern must cite at least one study item or rejected suggestion.
    @discardableResult
    func addStudyReflections(
        projectID: Project.ID,
        drafts: [StudyReflectionDraft]
    ) throws -> [StudyReflection] {
        try mutate { snapshot, now in
            let index = try Self.studyProjectIndex(projectID, in: snapshot)
            guard var study = snapshot.projects[index].study else {
                throw LibraryStudyError.notAStudy(projectID)
            }

            let projectItemIDs = Set(
                snapshot.inspirations.filter { $0.projectID == projectID }.map(\.id)
            )
            let rejectedIDs = Set(
                study.suggestions.filter { $0.status == .rejected }.map(\.id)
            )

            var added: [StudyReflection] = []
            for draft in drafts {
                let statement = Self.cleaned(draft.statement)
                guard !statement.isEmpty else {
                    throw LibraryStudyError.invalidReflection("a pattern needs a statement.")
                }
                let itemIDs = Self.orderedUnique(draft.inspirationIDs ?? [])
                let rejectIDs = Self.orderedUnique(draft.rejectedSuggestionIDs ?? [])
                guard !itemIDs.isEmpty || !rejectIDs.isEmpty else {
                    throw LibraryStudyError.invalidReflection(
                        "\"\(statement)\" cites no study items or rejected suggestions."
                    )
                }
                if let unknown = itemIDs.first(where: { !projectItemIDs.contains($0) }) {
                    throw LibraryStudyError.invalidReflection(
                        "\(unknown.uuidString) is not an item in this study."
                    )
                }
                if let unknown = rejectIDs.first(where: { !rejectedIDs.contains($0) }) {
                    throw LibraryStudyError.invalidReflection(
                        "\(unknown.uuidString) is not a rejected suggestion in this study."
                    )
                }
                added.append(
                    StudyReflection(
                        statement: statement,
                        inspirationIDs: itemIDs,
                        rejectedSuggestionIDs: rejectIDs,
                        proposedAt: now
                    )
                )
            }

            if !added.isEmpty {
                study.reflections.append(contentsOf: added)
                snapshot.projects[index].study = study
                snapshot.projects[index].updatedAt = now
            }
            return added
        }
    }

    /// Records whether the user agrees with a reflected pattern. A response
    /// can be changed later.
    @discardableResult
    func respondToStudyReflection(
        projectID: Project.ID,
        reflectionID: StudyReflection.ID,
        response: StudyReflectionResponse
    ) throws -> StudyReflection {
        try mutate { snapshot, now in
            let projectIndex = try Self.studyProjectIndex(projectID, in: snapshot)
            guard var study = snapshot.projects[projectIndex].study else {
                throw LibraryStudyError.notAStudy(projectID)
            }
            guard let index = study.reflections.firstIndex(where: { $0.id == reflectionID }) else {
                throw LibraryStudyError.reflectionNotFound(reflectionID)
            }

            var reflection = study.reflections[index]
            switch response {
            case .confirm:
                reflection.status = .confirmed
                reflection.correction = nil
            case .correct(let text):
                let correction = Self.cleaned(text)
                guard !correction.isEmpty else { throw LibraryStudyError.emptyCorrection }
                reflection.status = .corrected
                reflection.correction = correction
            case .dismiss:
                reflection.status = .dismissed
                reflection.correction = nil
            }
            reflection.respondedAt = now

            study.reflections[index] = reflection
            snapshot.projects[projectIndex].study = study
            snapshot.projects[projectIndex].updatedAt = now
            return reflection
        }
    }

    // MARK: - Helpers

    /// Saves a kept suggestion as a library item in the study, following the
    /// same rule as an explicit capture into a project: an existing item with
    /// the same canonical URL moves into the study instead of duplicating.
    private nonisolated static func saveKeptSuggestion(
        _ suggestion: StudySuggestion,
        to projectID: Project.ID,
        in snapshot: inout LibrarySnapshot,
        at now: Date
    ) -> Inspiration.ID {
        if let existingIndex = snapshot.inspirations.firstIndex(where: {
            $0.canonicalURL.absoluteString == suggestion.canonicalURL.absoluteString
        }) {
            if snapshot.inspirations[existingIndex].projectID != projectID {
                snapshot.inspirations[existingIndex].projectID = projectID
                snapshot.inspirations[existingIndex].updatedAt = now
            }
            return snapshot.inspirations[existingIndex].id
        }

        let inspiration = Inspiration(
            source: .web,
            url: suggestion.url,
            canonicalURL: suggestion.canonicalURL,
            title: suggestion.title,
            authorName: suggestion.creator,
            imageURL: suggestion.imageURL,
            projectID: projectID,
            createdAt: now
        )
        snapshot.inspirations.append(inspiration)
        return inspiration.id
    }

    private nonisolated static func studyProjectIndex(
        _ projectID: Project.ID,
        in snapshot: LibrarySnapshot
    ) throws -> Int {
        guard let index = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
            throw LibraryRepositoryError.projectNotFound(projectID)
        }
        return index
    }

    private nonisolated static func orderedUnique<Element: Hashable>(_ values: [Element]) -> [Element] {
        var seen = Set<Element>()
        return values.filter { seen.insert($0).inserted }
    }
}
