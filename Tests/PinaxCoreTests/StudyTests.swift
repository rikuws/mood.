import Foundation
import XCTest
@testable import PinaxCore

final class StudyTests: XCTestCase, @unchecked Sendable {
    private let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - Model

    func testProjectWithoutStudyKeyDecodesAsOrdinaryProject() throws {
        let json = """
        {"id":"7D3C9A51-1D1B-4F3E-9C7B-0B9A3D0E2F11","name":"Launch","createdAt":0,"updatedAt":0}
        """
        let project = try decoder().decode(Project.self, from: Data(json.utf8))

        XCTAssertNil(project.study)
        XCTAssertFalse(project.isStudy)
    }

    func testStudyRoundTripsAndUnknownStatusReadsAsPending() throws {
        let suggestion = StudySuggestion(
            url: URL(string: "https://example.com/still")!,
            canonicalURL: URL(string: "https://example.com/still")!,
            title: "Still",
            creator: "Geoffrey Unsworth",
            rationale: "Shares the empty white frame you noted.",
            suggestedAt: fixedDate
        )
        let project = Project(
            name: "2001",
            study: ProjectStudy(subject: "2001: A Space Odyssey", startedAt: fixedDate, suggestions: [suggestion]),
            createdAt: fixedDate
        )

        let data = try encoder().encode(project)
        XCTAssertEqual(try decoder().decode(Project.self, from: data), project)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var study = try XCTUnwrap(object["study"] as? [String: Any])
        var suggestions = try XCTUnwrap(study["suggestions"] as? [[String: Any]])
        suggestions[0]["status"] = "maybe_later"
        study["suggestions"] = suggestions
        object["study"] = study
        let future = try JSONSerialization.data(withJSONObject: object)

        let decoded = try decoder().decode(Project.self, from: future)
        XCTAssertEqual(decoded.study?.suggestions.first?.status, .pending)
    }

    func testStageFollowsSeedsDecisionsAndConfirmedPatterns() {
        var study = ProjectStudy(subject: "Brutalism", startedAt: fixedDate)
        XCTAssertEqual(study.stage(itemCount: 2), .seed)
        XCTAssertEqual(study.stage(itemCount: 3), .explore)

        study.suggestions = (0..<ProjectStudy.decisionsBeforeReflection).map { index in
            StudySuggestion(
                url: URL(string: "https://example.com/\(index)")!,
                canonicalURL: URL(string: "https://example.com/\(index)")!,
                title: "Work \(index)",
                creator: "Maker",
                rationale: "Why",
                status: index.isMultiple(of: 2) ? .kept : .rejected
            )
        }
        XCTAssertEqual(study.stage(itemCount: 3), .reflect)

        study.reflections = [StudyReflection(statement: "Concrete mass", status: .corrected, correction: "Raw mass, warm light")]
        XCTAssertEqual(study.stage(itemCount: 3), .distill)
    }

    func testGeneratedImageryHostsAreRecognizedIncludingSubdomainsAndPaths() {
        XCTAssertTrue(StudySourcePolicy.isGeneratedImageryHost(URL(string: "https://cdn.midjourney.com/a.png")))
        XCTAssertTrue(StudySourcePolicy.isGeneratedImageryHost(URL(string: "https://lexica.art/prompt/1")))
        XCTAssertTrue(StudySourcePolicy.isGeneratedImageryHost(URL(string: "https://www.freepik.com/ai/image")))
        XCTAssertFalse(StudySourcePolicy.isGeneratedImageryHost(URL(string: "https://www.freepik.com/photos/still")))
        XCTAssertFalse(StudySourcePolicy.isGeneratedImageryHost(URL(string: "https://www.criterion.com/films/2001")))
        XCTAssertFalse(StudySourcePolicy.isGeneratedImageryHost(URL(string: "https://notmidjourney.com/a")))
        XCTAssertFalse(StudySourcePolicy.isGeneratedImageryHost(nil))
    }

    func testMergingStudiesKeepsEachItemsStrongestDecision() {
        let base = Date(timeIntervalSince1970: 1_000)
        func suggestion(
            _ id: UUID,
            _ status: StudySuggestion.Status,
            decidedAt: TimeInterval? = nil,
            reason: String? = nil
        ) -> StudySuggestion {
            StudySuggestion(
                id: id,
                url: URL(string: "https://example.com/\(id.uuidString)")!,
                canonicalURL: URL(string: "https://example.com/\(id.uuidString)")!,
                title: "Work",
                creator: "Maker",
                rationale: "Why",
                suggestedAt: base,
                status: status,
                reason: reason,
                decidedAt: decidedAt.map { base.addingTimeInterval($0) }
            )
        }
        let keptVsLaterReject = UUID()
        let decidedVsPending = UUID()
        let laterReason = UUID()
        let onlyOther = UUID()
        let reflection = UUID()

        let preferred = ProjectStudy(
            subject: "Preferred",
            startedAt: base,
            suggestions: [
                suggestion(keptVsLaterReject, .kept, decidedAt: 1),
                suggestion(decidedVsPending, .pending),
                suggestion(laterReason, .rejected, decidedAt: 1, reason: "old"),
            ],
            reflections: [StudyReflection(id: reflection, statement: "A", proposedAt: base)]
        )
        let other = ProjectStudy(
            subject: "Other",
            startedAt: base,
            suggestions: [
                suggestion(keptVsLaterReject, .rejected, decidedAt: 5),
                suggestion(decidedVsPending, .rejected, decidedAt: 2, reason: "no"),
                suggestion(laterReason, .rejected, decidedAt: 3, reason: "new"),
                suggestion(onlyOther, .pending),
            ],
            reflections: [
                StudyReflection(
                    id: reflection,
                    statement: "A",
                    proposedAt: base,
                    status: .corrected,
                    correction: "B",
                    respondedAt: base.addingTimeInterval(4)
                ),
            ]
        )

        let merged = ProjectStudy.merged(preferring: preferred, with: other)
        let byID = Dictionary(uniqueKeysWithValues: (merged?.suggestions ?? []).map { ($0.id, $0) })

        XCTAssertEqual(merged?.subject, "Preferred")
        XCTAssertEqual(byID.count, 4)
        XCTAssertEqual(byID[keptVsLaterReject]?.status, .kept)
        XCTAssertEqual(byID[decidedVsPending]?.reason, "no")
        XCTAssertEqual(byID[laterReason]?.reason, "new")
        XCTAssertEqual(byID[onlyOther]?.status, .pending)
        XCTAssertEqual(merged?.reflections.first?.acceptedStatement, "B")
        XCTAssertEqual(ProjectStudy.merged(preferring: nil, with: other), other)
        XCTAssertEqual(ProjectStudy.merged(preferring: preferred, with: nil), preferred)
    }

    // MARK: - Repository

    func testCreateStudyMakesProjectWithSubjectAndBrief() async throws {
        let repository = try makeRepository()

        let project = try await repository.createStudy(
            subject: "  2001: A Space Odyssey ",
            brief: "the coldness of the white"
        )
        let snapshot = try await repository.load()

        XCTAssertEqual(project.name, "2001: A Space Odyssey")
        XCTAssertEqual(project.study?.subject, "2001: A Space Odyssey")
        XCTAssertEqual(project.study?.brief, "the coldness of the white")
        XCTAssertEqual(project.study?.startedAt, fixedDate)
        XCTAssertEqual(snapshot.projects, [project])
    }

    func testCreateStudyRejectsEmptySubjectAndDuplicateName() async throws {
        let repository = try makeRepository()
        _ = try await repository.createProject(name: "Brutalism")

        await XCTAssertThrowsErrorAsync(try await repository.createStudy(subject: "  ")) { error in
            XCTAssertEqual(error as? LibraryStudyError, .invalidSubject)
        }
        await XCTAssertThrowsErrorAsync(try await repository.createStudy(subject: "brutalism")) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .duplicateProjectName)
        }
    }

    func testStartStudyKeepsExistingItemsAsSeedsAndPreservesHistory() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "Kubrick")
        let seed = try await capture("https://example.com/seed", into: project.id, repository)

        let started = try await repository.startStudy(projectID: project.id, subject: "Kubrick interiors")
        let batch = try await repository.addStudySuggestions(
            projectID: project.id,
            drafts: [draft("https://example.com/a", basedOn: [seed.id])]
        )
        let renamed = try await repository.startStudy(
            projectID: project.id,
            subject: "Kubrick sets",
            brief: "symmetry"
        )

        XCTAssertEqual(started.study?.subject, "Kubrick interiors")
        XCTAssertEqual(batch.added.count, 1)
        XCTAssertEqual(renamed.study?.subject, "Kubrick sets")
        XCTAssertEqual(renamed.study?.brief, "symmetry")
        XCTAssertEqual(renamed.study?.suggestions.map(\.id), batch.added.map(\.id))
    }

    func testSuggestionsRequireAttributionRationaleAndRealSources() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")
        let seed = try await capture("https://example.com/seed", into: study.id, repository)

        let result = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [
                draft("https://www.criterion.com/2001?utm_source=x", basedOn: [seed.id]),
                draft("https://www.midjourney.com/jobs/1"),
                draft("https://example.com/real", imageURL: "https://cdn.midjourney.com/x.png"),
                draft("https://example.com/no-creator", creator: " "),
                draft("https://example.com/no-why", rationale: ""),
                draft("https://example.com/no-title", title: ""),
                draft("ftp://example.com/file"),
                draft("https://example.com/other-basis", basedOn: [UUID()]),
                draft("https://www.criterion.com/2001"),
            ]
        )

        XCTAssertEqual(result.added.map(\.canonicalURL.absoluteString), ["https://criterion.com/2001"])
        XCTAssertEqual(result.added.first?.basedOnInspirationIDs, [seed.id])
        XCTAssertEqual(result.added.first?.status, .pending)
        XCTAssertEqual(result.skipped.map(\.reason), [
            .generatedImagery,
            .generatedImagery,
            .missingCreator,
            .missingRationale,
            .missingTitle,
            .invalidURL,
            .unknownBasis,
            .duplicateInBatch,
        ])
    }

    func testSuggestInputWithMissingFieldsSkipsOnlyThoseEntries() async throws {
        let json = """
        {"suggestions":[
          {"url":"https://example.com/credited","title":"Credited","creator":"Studio","rationale":"Matches your seed."},
          {"url":"https://example.com/no-creator","title":"Uncredited","rationale":"Matches your seed."},
          {"url":"https://example.com/no-why","title":"No reason","creator":"Studio"},
          {"url":"https://example.com/no-title","creator":"Studio","rationale":"Matches your seed."}
        ]}
        """
        let input = try JSONDecoder().decode(PinaxAgentSuggestInput.self, from: Data(json.utf8))
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")

        let result = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: input.suggestions
        )

        XCTAssertEqual(result.added.map(\.title), ["Credited"])
        XCTAssertEqual(result.skipped.map(\.reason), [
            .missingCreator,
            .missingRationale,
            .missingTitle,
        ])
    }

    func testRejectedSavedAndPendingURLsAreNeverProposedAgain() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")
        _ = try await capture("https://example.com/seed", into: study.id, repository)
        let first = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [draft("https://example.com/rejected"), draft("https://example.com/pending")]
        )
        _ = try await repository.decideStudySuggestion(
            projectID: study.id,
            suggestionID: first.added[0].id,
            verdict: .reject,
            reason: "too warm"
        )

        let second = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [
                draft("https://example.com/rejected"),
                draft("https://example.com/pending"),
                draft("https://example.com/seed"),
            ]
        )

        XCTAssertTrue(second.added.isEmpty)
        XCTAssertEqual(second.skipped.map(\.reason), [.previouslyRejected, .alreadySuggested, .alreadySaved])
    }

    func testKeepingSavesSourceToStudyAndRecordsReason() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")
        let batch = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [draft("https://example.com/pod-bay", imageURL: "https://example.com/pod-bay.jpg")]
        )

        let kept = try await repository.decideStudySuggestion(
            projectID: study.id,
            suggestionID: batch.added[0].id,
            verdict: .keep,
            reason: "  how empty the frame is  "
        )
        let snapshot = try await repository.load()
        let item = try XCTUnwrap(snapshot.inspirations.first)

        XCTAssertEqual(kept.status, .kept)
        XCTAssertEqual(kept.reason, "how empty the frame is")
        XCTAssertEqual(kept.decidedAt, fixedDate)
        XCTAssertEqual(kept.savedInspirationID, item.id)
        XCTAssertEqual(item.projectID, study.id)
        XCTAssertEqual(item.title, "Pod bay")
        XCTAssertEqual(item.authorName, "Geoffrey Unsworth")
        XCTAssertEqual(item.imageURL, URL(string: "https://example.com/pod-bay.jpg"))
        XCTAssertEqual(item.verdict, .keep)
        XCTAssertEqual(item.note, "how empty the frame is")
        XCTAssertEqual(snapshot.project(id: study.id)?.study?.suggestions, [kept])
    }

    func testKeepingAnAlreadySavedURLMovesItIntoTheStudyWithoutDuplicating() async throws {
        let repository = try makeRepository()
        let general = try await repository.capture(
            CapturePayload(source: .web, url: URL(string: "https://example.com/still")!, title: "Mine")
        )
        let study = try await repository.createStudy(subject: "2001")
        let batch = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [draft("https://example.com/still")]
        )

        let kept = try await repository.decideStudySuggestion(
            projectID: study.id,
            suggestionID: batch.added[0].id,
            verdict: .keep,
            reason: nil
        )
        let snapshot = try await repository.load()

        XCTAssertEqual(snapshot.inspirations.count, 1)
        XCTAssertEqual(kept.savedInspirationID, general.inspiration.id)
        XCTAssertEqual(snapshot.inspirations.first?.projectID, study.id)
        XCTAssertEqual(snapshot.inspirations.first?.title, "Mine")
        XCTAssertEqual(snapshot.inspirations.first?.verdict, .keep)
        XCTAssertNil(snapshot.inspirations.first?.note)
    }

    func testKeepingAnItemWithANoteKeepsTheUsersOwnNote() async throws {
        let repository = try makeRepository()
        var general = try await repository.capture(
            CapturePayload(source: .web, url: URL(string: "https://example.com/still")!, title: "Mine")
        ).inspiration
        general.note = "The grain I keep coming back to."
        _ = try await repository.updateInspiration(general)
        let study = try await repository.createStudy(subject: "2001")
        let batch = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [draft("https://example.com/still")]
        )

        _ = try await repository.decideStudySuggestion(
            projectID: study.id,
            suggestionID: batch.added[0].id,
            verdict: .keep,
            reason: "the symmetry"
        )
        let snapshot = try await repository.load()
        let item = try XCTUnwrap(snapshot.inspirations.first)

        XCTAssertEqual(item.note, "The grain I keep coming back to.")
        XCTAssertEqual(item.verdict, .keep)
        XCTAssertEqual(item.projectID, study.id)
    }

    func testRejectedSuggestionCanBeKeptLaterButKeptCannotBeRejected() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")
        let batch = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [draft("https://example.com/a")]
        )
        let id = batch.added[0].id

        let rejected = try await repository.decideStudySuggestion(
            projectID: study.id, suggestionID: id, verdict: .reject, reason: "too busy"
        )
        let reconsidered = try await repository.decideStudySuggestion(
            projectID: study.id, suggestionID: id, verdict: .keep, reason: "the red accent"
        )

        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertNil(rejected.savedInspirationID)
        XCTAssertEqual(reconsidered.status, .kept)
        XCTAssertEqual(reconsidered.reason, "the red accent")
        XCTAssertNotNil(reconsidered.savedInspirationID)
        await XCTAssertThrowsErrorAsync(
            try await repository.decideStudySuggestion(
                projectID: study.id, suggestionID: id, verdict: .reject, reason: nil
            )
        ) { error in
            XCTAssertEqual(error as? LibraryStudyError, .suggestionAlreadyKept(id))
        }
    }

    func testRejectingThePendingFindsLeavesDecidedOnesAlone() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")
        let batch = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [
                draft("https://example.com/kept"),
                draft("https://example.com/rejected"),
                draft("https://example.com/pending-a"),
                draft("https://example.com/pending-b"),
            ]
        )
        _ = try await repository.decideStudySuggestion(
            projectID: study.id, suggestionID: batch.added[0].id, verdict: .keep, reason: "the floor"
        )
        _ = try await repository.decideStudySuggestion(
            projectID: study.id, suggestionID: batch.added[1].id, verdict: .reject, reason: "too warm"
        )

        let passed = try await repository.rejectPendingStudySuggestions(projectID: study.id)
        let suggestions = try await repository.load().project(id: study.id)?.study?.suggestions ?? []

        XCTAssertEqual(passed.map(\.id), [batch.added[2].id, batch.added[3].id])
        XCTAssertEqual(suggestions.map(\.status), [.kept, .rejected, .rejected, .rejected])
        XCTAssertEqual(suggestions.map(\.reason), ["the floor", "too warm", nil, nil])
        XCTAssertEqual(suggestions[2].decidedAt, fixedDate)
        let again = try await repository.rejectPendingStudySuggestions(projectID: study.id)
        XCTAssertTrue(again.isEmpty)

        let retry = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [draft("https://example.com/pending-a")]
        )
        XCTAssertEqual(retry.skipped.map(\.reason), [.previouslyRejected])
    }

    func testSuggestionsRequireAStudy() async throws {
        let repository = try makeRepository()
        let project = try await repository.createProject(name: "Plain")

        await XCTAssertThrowsErrorAsync(
            try await repository.addStudySuggestions(projectID: project.id, drafts: [draft("https://example.com")])
        ) { error in
            XCTAssertEqual(error as? LibraryStudyError, .notAStudy(project.id))
        }
    }

    func testReflectionsMustCiteStudyEvidence() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")
        let seed = try await capture("https://example.com/seed", into: study.id, repository)
        let elsewhere = try await repository.capture(
            CapturePayload(source: .web, url: URL(string: "https://example.com/general")!)
        )
        let batch = try await repository.addStudySuggestions(
            projectID: study.id,
            drafts: [draft("https://example.com/pending"), draft("https://example.com/rejected")]
        )
        _ = try await repository.decideStudySuggestion(
            projectID: study.id, suggestionID: batch.added[1].id, verdict: .reject, reason: "too warm"
        )

        let added = try await repository.addStudyReflections(
            projectID: study.id,
            drafts: [
                StudyReflectionDraft(
                    statement: "You keep picking cold white space",
                    inspirationIDs: [seed.id, seed.id],
                    rejectedSuggestionIDs: [batch.added[1].id]
                ),
            ]
        )
        XCTAssertEqual(added.first?.inspirationIDs, [seed.id])
        XCTAssertEqual(added.first?.status, .pending)

        for invalid in [
            StudyReflectionDraft(statement: "No evidence"),
            StudyReflectionDraft(statement: "Outside", inspirationIDs: [elsewhere.inspiration.id]),
            StudyReflectionDraft(statement: "Still pending", rejectedSuggestionIDs: [batch.added[0].id]),
            StudyReflectionDraft(statement: "  ", inspirationIDs: [seed.id]),
        ] {
            await XCTAssertThrowsErrorAsync(
                try await repository.addStudyReflections(projectID: study.id, drafts: [invalid])
            ) { error in
                guard case .invalidReflection = error as? LibraryStudyError else {
                    return XCTFail("Unexpected error \(error)")
                }
            }
        }
        let reflections = try await repository.load().project(id: study.id)?.study?.reflections
        XCTAssertEqual(reflections?.count, 1)
    }

    func testUserConfirmsCorrectsOrDismissesReflections() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001")
        let seed = try await capture("https://example.com/seed", into: study.id, repository)
        let reflection = try await repository.addStudyReflections(
            projectID: study.id,
            drafts: [StudyReflectionDraft(statement: "One saturated accent", inspirationIDs: [seed.id])]
        )[0]

        let confirmed = try await repository.respondToStudyReflection(
            projectID: study.id, reflectionID: reflection.id, response: .confirm
        )
        XCTAssertEqual(confirmed.acceptedStatement, "One saturated accent")

        let corrected = try await repository.respondToStudyReflection(
            projectID: study.id, reflectionID: reflection.id, response: .correct(" One red accent, never two ")
        )
        XCTAssertEqual(corrected.status, .corrected)
        XCTAssertEqual(corrected.acceptedStatement, "One red accent, never two")
        XCTAssertEqual(corrected.statement, "One saturated accent")

        await XCTAssertThrowsErrorAsync(
            try await repository.respondToStudyReflection(
                projectID: study.id, reflectionID: reflection.id, response: .correct(" ")
            )
        ) { error in
            XCTAssertEqual(error as? LibraryStudyError, .emptyCorrection)
        }

        let dismissed = try await repository.respondToStudyReflection(
            projectID: study.id, reflectionID: reflection.id, response: .dismiss
        )
        XCTAssertNil(dismissed.acceptedStatement)
        XCTAssertNil(dismissed.correction)
    }

    // MARK: - Agent API

    func testAgentCommandsParseStudyReadsAndProposals() throws {
        XCTAssertEqual(
            try PinaxAgentCommand.parse(arguments: ["study", "--project", " 2001 ", "--pretty"]),
            .study(project: "2001", prettyPrinted: true)
        )
        XCTAssertEqual(
            try PinaxAgentCommand.parse(arguments: ["suggest", "--file", "s.json", "--project", "2001"]),
            .suggest(project: "2001", file: "s.json", prettyPrinted: false)
        )
        XCTAssertEqual(
            try PinaxAgentCommand.parse(arguments: ["reflect", "--project", "2001", "--file", "r.json"]),
            .reflect(project: "2001", file: "r.json", prettyPrinted: false)
        )
        XCTAssertThrowsError(try PinaxAgentCommand.parse(arguments: ["suggest", "--project", "2001"]))
        XCTAssertThrowsError(try PinaxAgentCommand.parse(arguments: ["suggest", "--project", "a", "--project", "b"]))
        XCTAssertThrowsError(try PinaxAgentCommand.parse(arguments: ["study", "2001"]))
        XCTAssertTrue(PinaxAgentCommand.usage.contains("inspiration --id"))
        XCTAssertTrue(PinaxAgentCommand.usage.contains("validate-essence --file"))
        XCTAssertTrue(PinaxAgentCommand.usage.contains("suggest --project"))
    }

    func testAgentReadsStudyAndProposesSuggestionsAndReflections() async throws {
        let repository = try makeRepository()
        let study = try await repository.createStudy(subject: "2001", brief: "cold white")
        let seed = try await capture("https://example.com/seed", into: study.id, repository)
        let api = PinaxAgentAPI(repository: repository)
        let directory = try makeTemporaryDirectory()

        let suggestions = PinaxAgentSuggestInput(suggestions: [
            draft("https://example.com/a", basedOn: [seed.id]),
            draft("https://lexica.art/x"),
        ])
        try JSONEncoder().encode(suggestions).write(to: directory.appendingPathComponent("s.json"))
        let suggested = try await api.suggest(project: "2001", filePath: "s.json", currentDirectory: directory)

        XCTAssertTrue(suggested.ok)
        XCTAssertEqual(suggested.added.count, 1)
        XCTAssertEqual(suggested.skipped.map(\.reason), [.generatedImagery])

        let reflections = PinaxAgentReflectInput(reflections: [
            StudyReflectionDraft(statement: "Negative space dominates", inspirationIDs: [seed.id]),
        ])
        try JSONEncoder().encode(reflections).write(to: directory.appendingPathComponent("r.json"))
        let reflected = try await api.reflect(project: study.id.uuidString, filePath: "r.json", currentDirectory: directory)
        XCTAssertEqual(reflected.added.map(\.statement), ["Negative space dominates"])

        let read = try await api.study(project: "2001")
        XCTAssertEqual(read.study.subject, "2001")
        XCTAssertEqual(read.study.brief, "cold white")
        XCTAssertEqual(read.study.items.map(\.id), [seed.id])
        XCTAssertEqual(read.study.suggestions.map(\.status), [.pending])
        XCTAssertEqual(read.study.reflections.count, 1)
        XCTAssertEqual(read.study.stage, .seed)
    }

    func testAgentCannotProposeIntoAPlainProjectOrWithInvalidFiles() async throws {
        let repository = try makeRepository()
        _ = try await repository.createProject(name: "Plain")
        _ = try await repository.createStudy(subject: "2001")
        let api = PinaxAgentAPI(repository: repository)
        let directory = try makeTemporaryDirectory()
        try Data(#"{"suggestions":[]}"#.utf8).write(to: directory.appendingPathComponent("empty.json"))
        try Data(#"{"nope":true}"#.utf8).write(to: directory.appendingPathComponent("bad.json"))

        await XCTAssertThrowsErrorAsync(try await api.study(project: "Plain")) { error in
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "not_a_study")
        }
        await XCTAssertThrowsErrorAsync(
            try await api.suggest(project: "2001", filePath: "empty.json", currentDirectory: directory)
        ) { error in
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "invalid_study_input")
        }
        await XCTAssertThrowsErrorAsync(
            try await api.suggest(project: "2001", filePath: "bad.json", currentDirectory: directory)
        ) { error in
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "invalid_study_input")
        }
        await XCTAssertThrowsErrorAsync(
            try await api.reflect(project: "2001", filePath: "missing.json", currentDirectory: directory)
        ) { error in
            XCTAssertEqual(PinaxAgentErrorResponse(error: error).error.code, "invalid_study_input")
        }
    }

    // MARK: - Helpers

    private func draft(
        _ url: String,
        title: String = "Pod bay",
        creator: String = "Geoffrey Unsworth",
        imageURL: String? = nil,
        rationale: String = "Shares the empty white frame you noted.",
        basedOn: [Inspiration.ID]? = nil
    ) -> StudySuggestionDraft {
        StudySuggestionDraft(
            url: URL(string: url)!,
            title: title,
            creator: creator,
            sourceName: "Criterion",
            imageURL: imageURL.flatMap(URL.init(string:)),
            rationale: rationale,
            basedOnInspirationIDs: basedOn
        )
    }

    private func capture(
        _ url: String,
        into projectID: Project.ID,
        _ repository: LibraryRepository
    ) async throws -> Inspiration {
        try await repository.capture(
            CapturePayload(source: .web, url: URL(string: url)!, title: "Seed", projectID: projectID)
        ).inspiration
    }

    private func makeRepository() throws -> LibraryRepository {
        let date = fixedDate
        return try LibraryRepository(storageDirectory: makeTemporaryDirectory(), clock: { date })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxStudyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ handler: (any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
