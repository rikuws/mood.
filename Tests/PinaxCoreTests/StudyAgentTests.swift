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
        XCTAssertTrue(find.contains("./suggestions.json"))
        XCTAssertFalse(find.contains("./reflections.json"))
        XCTAssertFalse(find.contains(context.moodAgentPath))
        XCTAssertTrue(find.contains("never generated imagery"))
        XCTAssertTrue(find.contains("the user keeps, rejects, confirms or corrects everything"))

        let reflect = StudyAgentPrompt.make(task: .reflect, context: context)
        XCTAssertTrue(reflect.contains("./reflections.json"))
        XCTAssertFalse(reflect.contains("./suggestions.json"))
    }

    func testHandoffWritesTheStudyAndAddsOnlyWhatPassesTheChecks() async throws {
        let library = try makeDirectory("library")
        let scratch = try makeDirectory("scratch")
        let repository = try LibraryRepository(storageDirectory: library)
        let api = PinaxAgentAPI(repository: repository)
        let study = try await repository.createStudy(subject: "Apple + Artek", brief: "wood meets aluminium")

        try await StudyAgentHandoff.prepare(api: api, projectID: study.id, in: scratch)
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
}
