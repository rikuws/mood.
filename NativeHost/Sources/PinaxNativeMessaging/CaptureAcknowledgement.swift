import Foundation

public enum CaptureAcknowledgementIdentifier {
    public static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 128 else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }
}

public protocol CaptureAcknowledgementWaiting {
    func prepare(for requestID: String) -> Bool
    func wait(for requestID: String) -> NativeHostResponse?
}

/// Small request-correlated handoff shared by the native host and the Mac app.
/// The host creates/removes the slot before dispatching the custom URL, then
/// waits until the app has completed its coordinated repository transaction.
public struct FileCaptureAcknowledgementStore: CaptureAcknowledgementWaiting {
    public static let directoryName = "NativeMessagingAcknowledgements"

    private let configuredDirectoryURL: URL?
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval

    public init(
        directoryURL: URL? = nil,
        timeout: TimeInterval = 9,
        pollInterval: TimeInterval = 0.05
    ) {
        configuredDirectoryURL = directoryURL
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    public func prepare(for requestID: String) -> Bool {
        guard let fileURL = try? fileURL(for: requestID) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return true
        } catch {
            return false
        }
    }

    public func wait(for requestID: String) -> NativeHostResponse? {
        guard let fileURL = try? fileURL(for: requestID) else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        let decoder = JSONDecoder()

        while Date() < deadline {
            if let data = try? Data(contentsOf: fileURL),
               let response = try? decoder.decode(NativeHostResponse.self, from: data) {
                try? FileManager.default.removeItem(at: fileURL)
                return response
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return nil
    }

    public func write(_ response: NativeHostResponse, for requestID: String) throws {
        let fileURL = try fileURL(for: requestID)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(response)
        try data.write(to: fileURL, options: .atomic)
    }

    private func fileURL(for requestID: String) throws -> URL {
        guard let identifier = CaptureAcknowledgementIdentifier.normalized(requestID) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return try directoryURL().appendingPathComponent("\(identifier).json", isDirectory: false)
    }

    private func directoryURL() throws -> URL {
        if let configuredDirectoryURL { return configuredDirectoryURL }
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PINAX_ACKNOWLEDGEMENT_DIRECTORY"],
           override.hasPrefix("/"),
           !override.contains("\0") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("Pinax", isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }
}
