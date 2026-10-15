import Foundation
import XCTest
@testable import PinaxCore

final class StudyAgentTests: XCTestCase, @unchecked Sendable {
    private let context = StudyAgentContext(
        projectID: UUID(uuidString: "7D3C9A51-1D1B-4F3E-9C7B-0B9A3D0E2F11")!,
        projectName: "2001",
        subject: "2001: A Space Odyssey",
        moodAgentPath: "/Applications/mood.app/Contents/Helpers/mood-agent",
        skillDirectory: "/Applications/mood.app/Contents/Resources/Skills/mood-study",
        workingDirectory: "/tmp/mood-study-run",
        storageDirectory: "/Users/me/Library/Group Containers/group.com.rikuwikman.pinax"
    )

    func testClaudeCodePresetRunsUnattendedWithoutAnyShell() throws {
        let invocation = try StudyAgentConfiguration.automatic.invocation(
            task: .findSources,
            context: context,
            agent: .claudeCode,
            executable: "/Users/me/.local/bin/claude"
        )

        XCTAssertEqual(invocation.executable, "/Users/me/.local/bin/claude")
        XCTAssertEqual(invocation.arguments.first, "-p")
        XCTAssertEqual(invocation.arguments[1], StudyAgentPrompt.make(task: .findSources, context: context))
        XCTAssertEqual(
            Array(invocation.arguments.dropFirst(2)),
            [
                "--permission-mode", "acceptEdits",
                "--allowedTools",
                "Read,Glob,Grep,WebSearch,WebFetch",
            ]
        )
        XCTAssertFalse(invocation.arguments.contains { $0.contains("Bash") })
        XCTAssertEqual(invocation.workingDirectory, "/tmp/mood-study-run")
        XCTAssertNil(invocation.standardInput)
        XCTAssertEqual(invocation.environment["MOOD_AGENT"], context.moodAgentPath)
        XCTAssertEqual(invocation.environment["MOOD_STUDY_TASK"], "findSources")
        XCTAssertEqual(invocation.environment["MOOD_LIBRARY_DIRECTORY"], context.storageDirectory)
    }

    func testCustomAgentSubstitutesPlaceholdersInQuotedArguments() throws {
        let configuration = StudyAgentConfiguration(
            preset: .custom,
            executable: "  /opt/homebrew/bin/codex ",
            arguments: #"exec --cd "{workdir}" --note 'project {project}' {prompt}"#
        )

        let invocation = try configuration.invocation(
            task: .reflect,
            context: context,
            agent: .custom,
            executable: configuration.trimmedExecutable
        )

        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/codex")
        XCTAssertEqual(
            invocation.arguments,
            [
                "exec", "--cd", "/tmp/mood-study-run",
                "--note", "project 7D3C9A51-1D1B-4F3E-9C7B-0B9A3D0E2F11",
                StudyAgentPrompt.make(task: .reflect, context: context),
            ]
        )
        XCTAssertNil(invocation.standardInput)
    }

    func testCustomAgentWithoutPromptPlaceholderReadsPromptFromStdin() throws {
        let configuration = StudyAgentConfiguration(preset: .custom, executable: "my-agent", arguments: "run -")

        let invocation = try configuration.invocation(
            task: .findSources,
            context: context,
            agent: .custom,
            executable: "my-agent"
        )

        XCTAssertEqual(invocation.arguments, ["run", "-"])
        XCTAssertEqual(invocation.standardInput, StudyAgentPrompt.make(task: .findSources, context: context))
    }

    func testCodexPresetRunsInItsWorkspaceSandboxWithoutLibraryAccess() throws {
        let invocation = try StudyAgentConfiguration.automatic.invocation(
            task: .findSources,
            context: context,
            agent: .codex,
            executable: "/opt/homebrew/bin/codex"
        )

        XCTAssertEqual(
            invocation.arguments,
            [
                "exec", "--skip-git-repo-check", "--ephemeral",
                "--sandbox", "workspace-write",
                "-c", #"web_search="live""#,
                StudyAgentPrompt.make(task: .findSources, context: context),
            ]
        )
        XCTAssertFalse(invocation.arguments.contains("danger-full-access"))
        XCTAssertFalse(invocation.arguments.contains("--add-dir"))
    }

    func testAutomaticLooksForKnownAgentsInOrderAndCustomUsesItsCommand() {
        XCTAssertEqual(StudyAgentConfiguration.automatic.candidates.map(\.command), ["claude", "codex"])
        XCTAssertEqual(StudyAgentConfiguration(preset: .codex).candidates.map(\.preset), [.codex])
        XCTAssertEqual(
            StudyAgentConfiguration(preset: .custom, executable: " my-agent ").candidates.map(\.command),
            ["my-agent"]
        )
        XCTAssertTrue(StudyAgentConfiguration(preset: .custom).candidates.isEmpty)
    }

    func testIncompleteOrMalformedConfigurationIsRefused() {
        XCTAssertThrowsError(
            try StudyAgentConfiguration(preset: .custom).invocation(
                task: .findSources, context: context, agent: .custom, executable: "  "
            )
        ) { XCTAssertEqual($0 as? StudyAgentConfigurationError, .missingExecutable) }

        XCTAssertThrowsError(
            try StudyAgentConfiguration.automatic.invocation(
                task: .findSources, context: context, agent: .automatic, executable: "claude"
            )
        ) { XCTAssertEqual($0 as? StudyAgentConfigurationError, .missingExecutable) }

        XCTAssertThrowsError(
            try StudyAgentConfiguration(preset: .custom, executable: "agent", arguments: "say \"hi")
                .invocation(task: .findSources, context: context, agent: .custom, executable: "agent")
        ) { XCTAssertEqual($0 as? StudyAgentConfigurationError, .unbalancedQuote) }
    }

    func testSplitArgumentsKeepsEmptyQuotedTokensAndEscapes() throws {
        XCTAssertEqual(
            try StudyAgentConfiguration.splitArguments(#"a "" 'b c' d\ e "f\"g""#),
            ["a", "", "b c", "d e", "f\"g"]
        )
        XCTAssertEqual(try StudyAgentConfiguration.splitArguments("   "), [])
    }

    func testPromptHandsOffThroughFilesAndKeepsUserAsDecider() {
        let find = StudyAgentPrompt.make(task: .findSources, context: context)
        XCTAssertTrue(find.contains("/Applications/mood.app/Contents/Resources/Skills/mood-study/SKILL.md"))
        XCTAssertTrue(find.contains("./study.json"))
        XCTAssertTrue(find.contains("./images/<item id>.<ext>"))
        XCTAssertTrue(find.contains("./suggestions/01.json"))
        XCTAssertTrue(find.contains("the moment you have confirmed its credit"))
        XCTAssertFalse(find.contains("./reflections/"))
        XCTAssertFalse(find.contains(context.moodAgentPath))
        XCTAssertTrue(find.contains("never generated imagery"))
        XCTAssertTrue(find.contains("the user keeps, rejects, confirms or corrects everything"))

        let reflect = StudyAgentPrompt.make(task: .reflect, context: context)
        XCTAssertTrue(reflect.contains("./reflections/01.json"))
        XCTAssertFalse(reflect.contains("./suggestions/"))
    }

    func testNudgeSteersTheRunAsOneCleanLine() throws {
        XCTAssertNil(StudyAgentNudge.cleaned("  \n "))
        XCTAssertNil(StudyAgentNudge.cleaned(nil))
        XCTAssertEqual(
            StudyAgentNudge.cleaned("  more \"interiors\",\n\n  less   type "),
            "more 'interiors', less type"
        )
        XCTAssertEqual(
            StudyAgentNudge.cleaned(String(repeating: "a", count: 400))?.count,
            StudyAgentNudge.maximumLength
        )

        var nudged = context
        nudged.nudge = StudyAgentNudge.cleaned("warmer light, more interiors")
        let invocation = try StudyAgentConfiguration.automatic.invocation(
            task: .findSources,
            context: nudged,
            agent: .claudeCode,
            executable: "/Users/me/.local/bin/claude"
        )
        XCTAssertTrue(invocation.arguments[1].contains("The user nudged this run: \"warmer light, more interiors\"."))
        XCTAssertEqual(invocation.environment["MOOD_STUDY_NUDGE"], "warmer light, more interiors")

        let plain = StudyAgentPrompt.make(task: .findSources, context: context)
        XCTAssertFalse(plain.contains("nudged"))
        XCTAssertTrue(plain.contains("not near-copies of those"))
        let unnudged = try StudyAgentConfiguration.automatic.invocation(
            task: .findSources,
            context: context,
            agent: .claudeCode,
            executable: "/Users/me/.local/bin/claude"
        )
        XCTAssertNil(unnudged.environment["MOOD_STUDY_NUDGE"])
    }

    func testHandoffWritesTheStudyAndAddsOnlyWhatPassesTheChecks() async throws {
        let library = try makeDirectory("library")
        let scratch = try makeDirectory("scratch")
        let repository = try LibraryRepository(storageDirectory: library)
        let api = PinaxAgentAPI(repository: repository)
        let study = try await repository.createStudy(subject: "Apple + Artek", brief: "wood meets aluminium")
        let seed = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/seed")!,
                title: "Seed",
                imageURL: URL(string: "https://i.example.com/seed")!,
                projectID: study.id
            )
        ).inspiration
        _ = try await repository.capture(
            CapturePayload(source: .web, url: URL(string: "https://example.com/no-image")!, title: "Text only", projectID: study.id)
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])

        let staged = try await StudyAgentHandoff.prepare(
            api: api,
            projectID: study.id,
            in: scratch,
            fetchImage: { url in url.host() == "i.example.com" ? png : nil }
        )
        XCTAssertEqual(staged, 1)
        XCTAssertEqual(
            try Data(contentsOf: scratch.appendingPathComponent("images/\(seed.id.uuidString.lowercased()).png")),
            png
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let handed = try decoder.decode(
            PinaxAgentStudyResponse.self,
            from: Data(contentsOf: scratch.appendingPathComponent("study.json"))
        )
        XCTAssertEqual(handed.study.subject, "Apple + Artek")
        XCTAssertEqual(handed.project.id, study.id)

        let nothing = try await StudyAgentHandoff.collect(api: api, projectID: study.id, task: .findSources, from: scratch)
        XCTAssertEqual(nothing, StudyAgentHandoffResult(foundProposals: false))

        let proposals = """
        {"suggestions":[
          {"url":"https://www.vam.ac.uk/item/sk55","title":"SK55","creator":"Dieter Rams","rationale":"Wood and metal, like your brief."},
          {"url":"https://www.midjourney.com/jobs/1","title":"Generated","creator":"Someone","rationale":"Looks right."}
        ]}
        """
        try Data(proposals.utf8).write(to: scratch.appendingPathComponent("suggestions.json"))

        let result = try await StudyAgentHandoff.collect(api: api, projectID: study.id, task: .findSources, from: scratch)
        XCTAssertEqual(result.addedSuggestions, 1)
        XCTAssertEqual(result.skipped.map(\.reason), [.generatedImagery])
        XCTAssertEqual(result.summary, "Added 1 source for you to judge. Skipped 1 (generated imagery).")

        let stored = try await repository.load().project(id: study.id)?.study?.suggestions
        XCTAssertEqual(stored?.map(\.status), [.pending])

        let reflectResult = try await StudyAgentHandoff.collect(api: api, projectID: study.id, task: .reflect, from: scratch)
        XCTAssertFalse(reflectResult.foundProposals)
    }

    func testCollectorAddsEachFindingAsTheAgentSavesIt() async throws {
        let (repository, api, study) = try await makeSeededStudy()
        let scratch = try makeDirectory("streaming")
        try await StudyAgentHandoff.prepare(api: api, projectID: study.id, in: scratch, fetchImage: { _ in nil })
        let folder = scratch.appendingPathComponent("suggestions", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("reflections").path))

        let collector = StudyAgentProposalCollector(api: api, projectID: study.id, task: .findSources, directory: scratch)
        let quiet = try await collector.collect()
        XCTAssertEqual(quiet, StudyAgentHandoffResult(foundProposals: false))

        try Data(Self.suggestionJSON("https://www.vam.ac.uk/item/sk4", title: "SK4").utf8)
            .write(to: folder.appendingPathComponent("01.json"))
        // The agent is still writing its second find.
        try Data(#"{"url":"https://www.vam.ac.uk/item/sk55","title":"SK"#.utf8)
            .write(to: folder.appendingPathComponent("02.json"))

        let first = try await collector.collect()
        XCTAssertEqual(first.addedSuggestions, 1)
        XCTAssertTrue(first.unusableFiles.isEmpty)
        var stored = try await repository.load().project(id: study.id)?.study?.suggestions
        XCTAssertEqual(stored?.map(\.title), ["SK4"])

        try Data(Self.suggestionJSON("https://www.vam.ac.uk/item/sk55", title: "SK55").utf8)
            .write(to: folder.appendingPathComponent("02.json"))
        try Data(Self.suggestionJSON("https://www.midjourney.com/jobs/1", title: "Generated").utf8)
            .write(to: folder.appendingPathComponent("10.json"))

        let second = try await collector.collect()
        XCTAssertEqual(second.addedSuggestions, 1)
        XCTAssertEqual(second.skipped.map(\.reason), [.generatedImagery])
        stored = try await repository.load().project(id: study.id)?.study?.suggestions
        XCTAssertEqual(stored?.map(\.title), ["SK4", "SK55"])

        // Files already added are never added twice.
        let again = try await collector.collect(final: true)
        XCTAssertEqual(again.addedSuggestions, 0)
        XCTAssertTrue(again.skipped.isEmpty)

        let total = await collector.total
        XCTAssertEqual(total.addedSuggestions, 2)
        XCTAssertEqual(total.summary, "Added 2 sources for you to judge. Skipped 1 (generated imagery).")
    }

    func testFinalCollectReportsFilesItCannotUseAndKeepsTheRest() async throws {
        let (_, api, study) = try await makeSeededStudy()
        let scratch = try makeDirectory("unusable")
        try await StudyAgentHandoff.prepare(api: api, projectID: study.id, in: scratch, fetchImage: { _ in nil })
        let folder = scratch.appendingPathComponent("suggestions", isDirectory: true)
        try Data(#"{"url":"https://example.org/cut-off","#.utf8).write(to: folder.appendingPathComponent("01.json"))
        try Data(#"{"note":"not a proposal"}"#.utf8).write(to: folder.appendingPathComponent("02.json"))
        try Data(Self.suggestionJSON("https://www.vam.ac.uk/item/sk4", title: "SK4").utf8)
            .write(to: folder.appendingPathComponent("03.json"))

        let collector = StudyAgentProposalCollector(api: api, projectID: study.id, task: .findSources, directory: scratch)
        let running = try await collector.collect()
        XCTAssertEqual(running.addedSuggestions, 1)
        XCTAssertEqual(running.unusableFiles.map(\.name), ["suggestions/02.json"])

        let final = try await collector.collect(final: true)
        XCTAssertEqual(final.unusableFiles.map(\.name), ["suggestions/01.json"])
        let total = await collector.total
        XCTAssertEqual(total.addedSuggestions, 1)
        XCTAssertTrue(total.summary.hasPrefix("Added 1 source for you to judge. Couldn't use 2 files it wrote"))
    }

    func testOnePatternCitingSomethingElseDoesNotDropTheOthers() async throws {
        let (repository, api, study) = try await makeSeededStudy()
        let seedID = try await repository.load().inspirations.first { $0.projectID == study.id }!.id
        let scratch = try makeDirectory("reflections")
        try await StudyAgentHandoff.prepare(api: api, projectID: study.id, in: scratch, fetchImage: { _ in nil })
        let folder = scratch.appendingPathComponent("reflections", isDirectory: true)
        try Data(#"{"statement":"You keep warm wood against cold metal.","inspirationIDs":["\#(seedID.uuidString)"]}"#.utf8)
            .write(to: folder.appendingPathComponent("01.json"))
        try Data(#"{"statement":"Cites a stranger.","inspirationIDs":["\#(UUID().uuidString)"]}"#.utf8)
            .write(to: folder.appendingPathComponent("02.json"))

        let result = try await StudyAgentHandoff.collect(api: api, projectID: study.id, task: .reflect, from: scratch)
        XCTAssertEqual(result.addedReflections, 1)
        XCTAssertEqual(result.unusableFiles.map(\.name), ["reflections/02.json"])
        let stored = try await repository.load().project(id: study.id)?.study?.reflections
        XCTAssertEqual(stored?.map(\.statement), ["You keep warm wood against cold metal."])
    }

    func testBatchFileStillWorksAndAddsOnlyNewEntriesAsItGrows() async throws {
        let (repository, api, study) = try await makeSeededStudy()
        let scratch = try makeDirectory("batch")
        let batch = scratch.appendingPathComponent("suggestions.json")
        let collector = StudyAgentProposalCollector(api: api, projectID: study.id, task: .findSources, directory: scratch)

        try Data(#"{"suggestions":[\#(Self.suggestionJSON("https://www.vam.ac.uk/item/sk4", title: "SK4"))]}"#.utf8)
            .write(to: batch)
        let first = try await collector.collect()
        XCTAssertEqual(first.addedSuggestions, 1)

        try Data(
            #"{"suggestions":[\#(Self.suggestionJSON("https://www.vam.ac.uk/item/sk4", title: "SK4")),\#(Self.suggestionJSON("https://www.vam.ac.uk/item/sk55", title: "SK55"))]}"#.utf8
        ).write(to: batch)
        let second = try await collector.collect(final: true)
        XCTAssertEqual(second.addedSuggestions, 1)
        XCTAssertTrue(second.skipped.isEmpty)
        let stored = try await repository.load().project(id: study.id)?.study?.suggestions
        XCTAssertEqual(stored?.map(\.title), ["SK4", "SK55"])
    }

    func testARunStopsAddingAtTheLimit() async throws {
        let (_, api, study) = try await makeSeededStudy()
        let scratch = try makeDirectory("limit")
        try await StudyAgentHandoff.prepare(api: api, projectID: study.id, in: scratch, fetchImage: { _ in nil })
        let folder = scratch.appendingPathComponent("suggestions", isDirectory: true)
        let limit = StudyAgentProposalCollector.maximumProposalsPerRun
        let entries = (0..<(limit + 3)).map {
            Self.suggestionJSON("https://www.vam.ac.uk/item/\($0)", title: "Item \($0)")
        }
        try Data("[\(entries.joined(separator: ","))]".utf8).write(to: folder.appendingPathComponent("all.json"))

        let result = try await StudyAgentHandoff.collect(api: api, projectID: study.id, task: .findSources, from: scratch)
        XCTAssertEqual(result.addedSuggestions, limit)
        XCTAssertEqual(result.overLimit, 3)
    }

    private static func suggestionJSON(_ url: String, title: String) -> String {
        #"{"url":"\#(url)","title":"\#(title)","creator":"Dieter Rams","rationale":"Wood and metal, like your brief."}"#
    }

    private func makeSeededStudy() async throws -> (LibraryRepository, PinaxAgentAPI, Project) {
        let repository = try LibraryRepository(storageDirectory: try makeDirectory("library"))
        let study = try await repository.createStudy(subject: "Apple + Artek", brief: "wood meets aluminium")
        _ = try await repository.capture(
            CapturePayload(
                source: .web,
                url: URL(string: "https://example.com/seed")!,
                title: "Seed",
                projectID: study.id
            )
        )
        return (repository, PinaxAgentAPI(repository: repository), study)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyAgentTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testConfigurationRoundTripsThroughJSON() throws {
        let configuration = StudyAgentConfiguration(preset: .custom, executable: "agent", arguments: "{prompt}")
        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(StudyAgentConfiguration.self, from: data), configuration)
    }

    func testAgentOpensTheLibraryFolderItIsGiven() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mood-agent-location-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = try PinaxAgentLibraryLocation.repository(
            environment: ["MOOD_LIBRARY_DIRECTORY": directory.path]
        )

        XCTAssertEqual(repository.storageDirectory.standardizedFileURL, directory.standardizedFileURL)
    }

    func testAgentRefusesAMissingOrRelativeLibraryFolderInsteadOfAnEmptyLibrary() {
        let missing = "/tmp/mood-agent-missing-\(UUID().uuidString)"
        XCTAssertThrowsError(
            try PinaxAgentLibraryLocation.repository(environment: ["MOOD_LIBRARY_DIRECTORY": missing])
        ) { XCTAssertEqual($0 as? PinaxAgentLibraryLocationError, .missingDirectory(missing)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing))

        XCTAssertThrowsError(
            try PinaxAgentLibraryLocation.repository(environment: ["MOOD_LIBRARY_DIRECTORY": "library"])
        ) { XCTAssertEqual($0 as? PinaxAgentLibraryLocationError, .invalidPath("library")) }

        XCTAssertEqual(
            PinaxAgentErrorResponse(error: PinaxAgentLibraryLocationError.invalidPath("library")).error.code,
            "storage_error"
        )
    }

    func testAgentRefusesAnEmptyFallbackWhileTheSharedLibraryExists() throws {
        let shared = try makeDirectory("shared")
        let fallback = try makeDirectory("fallback")
        try Data("{}".utf8).write(to: shared.appendingPathComponent(PinaxStorage.libraryFilename))

        XCTAssertThrowsError(
            try PinaxAgentLibraryLocation.refuseFallback(from: fallback, whileSharedLibraryIsAt: shared)
        ) { XCTAssertEqual($0 as? PinaxAgentLibraryLocationError, .sharedLibraryUnreachable(shared.path)) }
        XCTAssertEqual(
            PinaxAgentErrorResponse(error: PinaxAgentLibraryLocationError.sharedLibraryUnreachable(shared.path)).error.code,
            "storage_error"
        )

        // The shared folder itself, a fallback that has its own library (an
        // unsigned development build), and a Mac without a shared library
        // all open normally.
        XCTAssertNoThrow(try PinaxAgentLibraryLocation.refuseFallback(from: shared, whileSharedLibraryIsAt: shared))
        try Data("{}".utf8).write(to: fallback.appendingPathComponent(PinaxStorage.libraryFilename))
        XCTAssertNoThrow(try PinaxAgentLibraryLocation.refuseFallback(from: fallback, whileSharedLibraryIsAt: shared))
        let empty = try makeDirectory("empty")
        let noShared = try makeDirectory("no-shared")
        XCTAssertNoThrow(try PinaxAgentLibraryLocation.refuseFallback(from: empty, whileSharedLibraryIsAt: noShared))
        XCTAssertNoThrow(try PinaxAgentLibraryLocation.refuseFallback(from: empty, whileSharedLibraryIsAt: nil))
    }
}
