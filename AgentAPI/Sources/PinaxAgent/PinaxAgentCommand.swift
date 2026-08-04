import Darwin
import Foundation
import PinaxCore

@main
private struct PinaxAgentExecutable {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        do {
            if arguments == ["--help"] || arguments == ["-h"] {
                FileHandle.standardOutput.write(Data((PinaxAgentCommand.usage + "\n").utf8))
                return
            }

            let command = try PinaxAgentCommand.parse(arguments: arguments)
            let repository = try LibraryRepository.appGroup()
            let api = PinaxAgentAPI(repository: repository)

            switch command {
            case .projects:
                try writeJSON(await api.projects(), prettyPrinted: command.prettyPrinted)
            case .inspirations(let project, _):
                try writeJSON(
                    await api.inspirations(project: project),
                    prettyPrinted: command.prettyPrinted
                )
            }
        } catch {
            let prettyPrinted = arguments.contains("--pretty")
            let response = PinaxAgentErrorResponse(error: error)
            try? writeJSON(response, prettyPrinted: prettyPrinted)
            exit(2)
        }
    }

    private static func writeJSON<Value: Encodable>(
        _ value: Value,
        prettyPrinted: Bool
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
