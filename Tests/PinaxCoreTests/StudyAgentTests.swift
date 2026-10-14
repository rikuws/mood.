import Foundation
import XCTest
@testable import PinaxCore

final class StudyAgentTests: XCTestCase {
    private let context = StudyAgentContext(
        projectID: UUID(uuidString: "7D3C9A51-1D1B-4F3E-9C7B-0B9A3D0E2F11")!,
        projectName: "2001",
        subject: "2001: A Space Odyssey",
        moodAgentPath: "/Applications/mood.app/Contents/Helpers/mood-agent",
        skillDirectory: "/Applications/mood.app/Contents/Resources/Skills/mood-study",
        workingDirectory: "/tmp/mood-study-run"
    )

    func testClaudeCodePresetRunsUnattendedWithOnlyTheHelperAsShell() throws {
        let invocation = try StudyAgentConfiguration.claudeCode.invocation(task: .findSources, context: context)

        XCTAssertEqual(invocation.executable, "claude")
        XCTAssertEqual(invocation.arguments.first, "-p")
        XCTAssertEqual(invocation.arguments[1], StudyAgentPrompt.make(task: .findSources, context: context))
        XCTAssertEqual(
            Array(invocation.arguments.dropFirst(2)),
            [
                "--permission-mode", "acceptEdits",
                "--allowedTools",
                "Read,Glob,Grep,WebSearch,WebFetch,Bash(/Applications/mood.app/Contents/Helpers/mood-agent:*)",
            ]
        )
        XCTAssertFalse(invocation.arguments.contains("Bash"))
        XCTAssertEqual(invocation.workingDirectory, "/tmp/mood-study-run")
        XCTAssertNil(invocation.standardInput)
        XCTAssertEqual(invocation.environment["MOOD_AGENT"], context.moodAgentPath)
        XCTAssertEqual(invocation.environment["MOOD_STUDY_TASK"], "findSources")
    }

    func testCustomAgentSubstitutesPlaceholdersInQuotedArguments() throws {
        let configuration = StudyAgentConfiguration(
            preset: .custom,
            executable: "  /opt/homebrew/bin/codex ",
            arguments: #"exec --cd "{workdir}" --note 'project {project}' {prompt}"#
        )

        let invocation = try configuration.invocation(task: .reflect, context: context)

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

        let invocation = try configuration.invocation(task: .findSources, context: context)

        XCTAssertEqual(invocation.arguments, ["run", "-"])
        XCTAssertEqual(invocation.standardInput, StudyAgentPrompt.make(task: .findSources, context: context))
    }

    func testIncompleteOrMalformedConfigurationIsRefused() {
        XCTAssertThrowsError(
            try StudyAgentConfiguration(preset: .custom, executable: "  ").invocation(task: .findSources, context: context)
        ) { XCTAssertEqual($0 as? StudyAgentConfigurationError, .missingExecutable) }

        XCTAssertThrowsError(
            try StudyAgentConfiguration(preset: .custom, executable: "agent", arguments: "say \"hi")
                .invocation(task: .findSources, context: context)
        ) { XCTAssertEqual($0 as? StudyAgentConfigurationError, .unbalancedQuote) }
    }

    func testSplitArgumentsKeepsEmptyQuotedTokensAndEscapes() throws {
        XCTAssertEqual(
            try StudyAgentConfiguration.splitArguments(#"a "" 'b c' d\ e "f\"g""#),
            ["a", "", "b c", "d e", "f\"g"]
        )
        XCTAssertEqual(try StudyAgentConfiguration.splitArguments("   "), [])
    }

    func testPromptPointsAtBundledSkillAndHelperAndKeepsUserAsDecider() {
        let find = StudyAgentPrompt.make(task: .findSources, context: context)
        XCTAssertTrue(find.contains("/Applications/mood.app/Contents/Resources/Skills/mood-study/SKILL.md"))
        XCTAssertTrue(find.contains("mood-agent suggest --project 7D3C9A51-1D1B-4F3E-9C7B-0B9A3D0E2F11"))
        XCTAssertTrue(find.contains("never generated imagery"))
        XCTAssertTrue(find.contains("The user keeps, rejects, confirms or corrects everything"))
        XCTAssertFalse(find.contains("mood-agent reflect"))

        let reflect = StudyAgentPrompt.make(task: .reflect, context: context)
        XCTAssertTrue(reflect.contains("mood-agent reflect --project 7D3C9A51-1D1B-4F3E-9C7B-0B9A3D0E2F11"))
        XCTAssertFalse(reflect.contains("mood-agent suggest"))
    }

    func testConfigurationRoundTripsThroughJSON() throws {
        let configuration = StudyAgentConfiguration(preset: .custom, executable: "agent", arguments: "{prompt}")
        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(StudyAgentConfiguration.self, from: data), configuration)
    }
}
