import Foundation

public enum BrowserManifestState: Equatable, Sendable {
    case notInstalled
    case installed
    case updateRequired
    case conflict(existingName: String?)
    case unreadable(message: String)
}

public enum NativeHostHelperState: Equatable, Sendable {
    case available
    case missing
    case notExecutable
}

public struct BrowserIntegrationStatus: Equatable, Sendable {
    public let browser: ChromiumBrowser
    public let manifestURL: URL
    public let helperExecutableURL: URL
    public let manifestState: BrowserManifestState
    public let helperState: NativeHostHelperState

    public var isOperational: Bool {
        manifestState == .installed && helperState == .available
    }

    public init(
        browser: ChromiumBrowser,
        manifestURL: URL,
        helperExecutableURL: URL,
        manifestState: BrowserManifestState,
        helperState: NativeHostHelperState
    ) {
        self.browser = browser
        self.manifestURL = manifestURL
        self.helperExecutableURL = helperExecutableURL
        self.manifestState = manifestState
        self.helperState = helperState
    }
}

public enum BrowserIntegrationInstallerError: Error, Equatable, LocalizedError {
    case helperMissing(URL)
    case helperNotExecutable(URL)
    case conflictingManifest(browser: ChromiumBrowser, url: URL, existingName: String?)
    case unreadableManifest(browser: ChromiumBrowser, url: URL, message: String)
    case verificationFailed(browser: ChromiumBrowser, url: URL)

    public var errorDescription: String? {
        switch self {
        case let .helperMissing(url):
            return "The Pinax native host helper is missing at \(url.path)."
        case let .helperNotExecutable(url):
            return "The Pinax native host helper is not executable at \(url.path)."
        case let .conflictingManifest(browser, url, existingName):
            let owner = existingName.map { " It declares the host \($0)." } ?? ""
            return "Pinax did not change the unrelated \(browser.displayName) manifest at \(url.path).\(owner)"
        case let .unreadableManifest(browser, url, message):
            return "Pinax could not safely identify the existing \(browser.displayName) manifest at \(url.path): \(message)"
        case let .verificationFailed(browser, url):
            return "The \(browser.displayName) native host manifest could not be verified after writing \(url.path)."
        }
    }
}

struct NativeHostManifest: Codable, Equatable {
    let name: String
    let description: String
    let path: String
    let type: String
    let allowedOrigins: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case type
        case allowedOrigins = "allowed_origins"
    }
}

/// Installs Pinax's user-level native host manifest without modifying browser bundles.
///
/// Calling `install(for:)` is idempotent: it creates a missing manifest or updates a manifest
/// whose declared name is `com.pinax.native_host`. A file that cannot be identified as Pinax's
/// manifest is reported as a conflict and is never overwritten or removed.
public struct BrowserIntegrationInstaller {
    public let homeDirectoryURL: URL
    public let helperExecutableURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates an installer for the currently running Pinax app bundle.
    public init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.init(
            homeDirectoryURL: fileManager.homeDirectoryForCurrentUser,
            helperExecutableURL: bundle.bundleURL
                .appendingPathComponent(PinaxBrowserIntegrationConfiguration.helperBundleRelativePath),
            fileManager: fileManager
        )
    }

    /// Injection-friendly initializer used by tests and nonstandard app launchers.
    public init(
        homeDirectoryURL: URL,
        helperExecutableURL: URL,
        fileManager: FileManager = .default
    ) {
        self.homeDirectoryURL = homeDirectoryURL.standardizedFileURL
        self.helperExecutableURL = helperExecutableURL.standardizedFileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func manifestDirectoryURL(for browser: ChromiumBrowser) -> URL {
        browser.nativeMessagingHostDirectoryComponents.reduce(homeDirectoryURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    public func manifestURL(for browser: ChromiumBrowser) -> URL {
        manifestDirectoryURL(for: browser)
            .appendingPathComponent(PinaxBrowserIntegrationConfiguration.nativeHostManifestFileName)
    }

    public func status(for browser: ChromiumBrowser) -> BrowserIntegrationStatus {
        let manifestURL = manifestURL(for: browser)

        return BrowserIntegrationStatus(
            browser: browser,
            manifestURL: manifestURL,
            helperExecutableURL: helperExecutableURL,
            manifestState: manifestState(at: manifestURL),
            helperState: helperState
        )
    }

    public func statuses() -> [BrowserIntegrationStatus] {
        ChromiumBrowser.allCases.map(status(for:))
    }

    /// Installs a missing Pinax manifest or updates an existing Pinax-owned manifest atomically.
    @discardableResult
    public func install(for browser: ChromiumBrowser) throws -> BrowserIntegrationStatus {
        try validateHelper()

        let before = status(for: browser)
        switch before.manifestState {
        case let .conflict(existingName):
            throw BrowserIntegrationInstallerError.conflictingManifest(
                browser: browser,
                url: before.manifestURL,
                existingName: existingName
            )
        case let .unreadable(message):
            throw BrowserIntegrationInstallerError.unreadableManifest(
                browser: browser,
                url: before.manifestURL,
                message: message
            )
        case .installed:
            return before
        case .notInstalled, .updateRequired:
            break
        }

        try fileManager.createDirectory(
            at: manifestDirectoryURL(for: browser),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(expectedManifest)
        try data.write(to: before.manifestURL, options: .atomic)

        let after = status(for: browser)
        guard after.manifestState == .installed else {
            throw BrowserIntegrationInstallerError.verificationFailed(
                browser: browser,
                url: after.manifestURL
            )
        }
        return after
    }

    /// `update` is deliberately idempotent and also installs the manifest when it is absent.
    @discardableResult
    public func update(for browser: ChromiumBrowser) throws -> BrowserIntegrationStatus {
        try install(for: browser)
    }

    /// Removes only a manifest that can be decoded and identified as Pinax-owned.
    @discardableResult
    public func remove(for browser: ChromiumBrowser) throws -> BrowserIntegrationStatus {
        let before = status(for: browser)
        switch before.manifestState {
        case .notInstalled:
            return before
        case let .conflict(existingName):
            throw BrowserIntegrationInstallerError.conflictingManifest(
                browser: browser,
                url: before.manifestURL,
                existingName: existingName
            )
        case let .unreadable(message):
            throw BrowserIntegrationInstallerError.unreadableManifest(
                browser: browser,
                url: before.manifestURL,
                message: message
            )
        case .installed, .updateRequired:
            try fileManager.removeItem(at: before.manifestURL)
            return status(for: browser)
        }
    }

    private var expectedManifest: NativeHostManifest {
        NativeHostManifest(
            name: PinaxBrowserIntegrationConfiguration.nativeHostName,
            description: "Save web design inspiration to Pinax.",
            path: helperExecutableURL.path,
            type: "stdio",
            allowedOrigins: [PinaxBrowserIntegrationConfiguration.chromiumExtensionOrigin]
        )
    }

    private func manifestState(at url: URL) -> BrowserManifestState {
        // Never follow or replace a manifest symlink. It may point at a file owned by another app.
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return .unreadable(message: "The manifest path is a symbolic link.")
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return .notInstalled
        }

        do {
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unreadable(message: "The manifest is not a JSON object.")
            }

            let existingName = object["name"] as? String
            guard existingName == PinaxBrowserIntegrationConfiguration.nativeHostName else {
                return .conflict(existingName: existingName)
            }

            // Once ownership is established by the exact native host name, malformed or legacy
            // Pinax fields are safe to repair with the current complete manifest.
            guard let existing = try? decoder.decode(NativeHostManifest.self, from: data) else {
                return .updateRequired
            }
            return existing == expectedManifest ? .installed : .updateRequired
        } catch {
            return .unreadable(message: error.localizedDescription)
        }
    }

    private var helperState: NativeHostHelperState {
        guard fileManager.fileExists(atPath: helperExecutableURL.path) else {
            return .missing
        }
        return fileManager.isExecutableFile(atPath: helperExecutableURL.path)
            ? .available
            : .notExecutable
    }

    private func validateHelper() throws {
        switch helperState {
        case .available:
            return
        case .missing:
            throw BrowserIntegrationInstallerError.helperMissing(helperExecutableURL)
        case .notExecutable:
            throw BrowserIntegrationInstallerError.helperNotExecutable(helperExecutableURL)
        }
    }
}
