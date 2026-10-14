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

            if case .validateEssence(let file, _) = command {
                try writeJSON(
                    PinaxAgentAPI.validateEssence(filePath: file),
                    prettyPrinted: command.prettyPrinted
                )
                return
            }

            let repository = try PinaxAgentLibraryLocation.repository()
            let api = PinaxAgentAPI(repository: repository)

            switch command {
            case .projects:
                try writeJSON(await api.projects(), prettyPrinted: command.prettyPrinted)
            case .inspirations(let project, _):
                try writeJSON(
                    await api.inspirations(project: project),
                    prettyPrinted: command.prettyPrinted
                )
            case .inspiration(let id, _):
                try writeJSON(
                    await api.inspiration(id: id),
                    prettyPrinted: command.prettyPrinted
                )
            case .saveEssence(let file, _):
                try writeJSON(
                    await api.saveEssence(filePath: file),
                    prettyPrinted: command.prettyPrinted
                )
            case .essence(let project, _):
                try writeJSON(
                    await api.essence(project: project),
                    prettyPrinted: command.prettyPrinted
                )
            case .study(let project, _):
                try writeJSON(
                    await api.study(project: project),
                    prettyPrinted: command.prettyPrinted
                )
            case .suggest(let project, let file, _):
                try writeJSON(
                    await api.suggest(project: project, filePath: file),
                    prettyPrinted: command.prettyPrinted
                )
            case .reflect(let project, let file, _):
                try writeJSON(
                    await api.reflect(project: project, filePath: file),
                    prettyPrinted: command.prettyPrinted
                )
            case .validateEssence:
                return
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
