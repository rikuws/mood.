import AppKit
import Darwin
import Foundation
import PinaxNativeMessaging

private struct WorkspaceCaptureURLOpener: CaptureURLOpening {
    func open(_ url: URL) -> Bool {
        guard let applicationURL = Self.containingApplicationURL else {
            return NSWorkspace.shared.open(url)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        #if DEBUG
        let processEnvironment = ProcessInfo.processInfo.environment
        let isolatedEnvironment = [
            "PINAX_STORAGE_DIRECTORY": processEnvironment["PINAX_STORAGE_DIRECTORY"],
            "PINAX_ACKNOWLEDGEMENT_DIRECTORY": processEnvironment["PINAX_ACKNOWLEDGEMENT_DIRECTORY"],
        ].compactMapValues { $0 }
        if !isolatedEnvironment.isEmpty {
            configuration.environment = isolatedEnvironment
        }
        #endif
        let result = WorkspaceOpenResult()
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { application, error in
            result.resolve(application != nil && error == nil)
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let value = result.value { return value }
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
        return false
    }

    private static var containingApplicationURL: URL? {
        var candidate = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension.lowercased() == "app" { return candidate }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}

private final class WorkspaceOpenResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool?

    var value: Bool? { lock.withLock { storedValue } }

    func resolve(_ value: Bool) {
        lock.withLock { storedValue = value }
    }
}

let processor = NativeMessageProcessor(opener: WorkspaceCaptureURLOpener())
let runner = NativeMessagingHostRunner(processor: processor)
let exitCode = runner.run(
    input: FileHandle.standardInput,
    output: FileHandle.standardOutput
)
exit(exitCode)
