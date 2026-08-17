import Foundation
import XCTest
@testable import BrowserIntegration

final class BrowserIntegrationInstallerTests: XCTestCase {
    func testManifestLocationsCoverSupportedChromiumBrowsers() throws {
        let fixture = try makeFixture()
        let installer = fixture.installer

        let expectedSuffixes: [ChromiumBrowser: String] = [
            .chrome: "Library/Application Support/Google/Chrome/NativeMessagingHosts/com.pinax.native_host.json",
            .chromium: "Library/Application Support/Chromium/NativeMessagingHosts/com.pinax.native_host.json",
            .brave: "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.pinax.native_host.json",
            .edge: "Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.pinax.native_host.json",
            .arc: "Library/Application Support/Arc/User Data/NativeMessagingHosts/com.pinax.native_host.json",
            .dia: "Library/Application Support/Dia/User Data/NativeMessagingHosts/com.pinax.native_host.json",
            .vivaldi: "Library/Application Support/Vivaldi/NativeMessagingHosts/com.pinax.native_host.json"
        ]

        XCTAssertEqual(installer.statuses().count, ChromiumBrowser.allCases.count)
        for browser in ChromiumBrowser.allCases {
            let suffix = try XCTUnwrap(expectedSuffixes[browser])
            XCTAssertTrue(installer.manifestURL(for: browser).path.hasSuffix(suffix))
        }
    }

    func testInstallWritesExpectedManifestAndReportsOperational() throws {
        let fixture = try makeFixture()

        let status = try fixture.installer.install(for: .chrome)

        XCTAssertEqual(status.manifestState, .installed)
        XCTAssertEqual(status.helperState, .available)
        XCTAssertTrue(status.isOperational)

        let data = try Data(contentsOf: status.manifestURL)
        let manifest = try JSONDecoder().decode(NativeHostManifest.self, from: data)
        XCTAssertEqual(manifest.name, "com.pinax.native_host")
        XCTAssertEqual(manifest.path, fixture.helper.path)
        XCTAssertEqual(manifest.type, "stdio")
        XCTAssertEqual(
            manifest.allowedOrigins,
            ["chrome-extension://ohhhjpbfjecipcnkahlhaggckmdjfndg/"]
        )
    }

    func testInstallIsIdempotent() throws {
        let fixture = try makeFixture()
        let first = try fixture.installer.install(for: .brave)
        let originalData = try Data(contentsOf: first.manifestURL)

        let second = try fixture.installer.install(for: .brave)

        XCTAssertEqual(second.manifestState, .installed)
        XCTAssertEqual(try Data(contentsOf: second.manifestURL), originalData)
    }

    func testRelocatedAppIsReportedAndUpdated() throws {
        let fixture = try makeFixture()
        _ = try fixture.installer.install(for: .edge)

        let relocatedHelper = fixture.root.appendingPathComponent("Relocated/PinaxNativeHost")
        try makeExecutable(at: relocatedHelper)
        let relocatedInstaller = BrowserIntegrationInstaller(
            homeDirectoryURL: fixture.home,
            helperExecutableURL: relocatedHelper
        )

        XCTAssertEqual(relocatedInstaller.status(for: .edge).manifestState, .updateRequired)
        let updated = try relocatedInstaller.update(for: .edge)

        XCTAssertEqual(updated.manifestState, .installed)
        let data = try Data(contentsOf: updated.manifestURL)
        let manifest = try JSONDecoder().decode(NativeHostManifest.self, from: data)
        XCTAssertEqual(manifest.path, relocatedHelper.path)
    }

    func testLegacyPinaxManifestCanBeRepaired() throws {
        let fixture = try makeFixture()
        let manifestURL = fixture.installer.manifestURL(for: .brave)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"name":"com.pinax.native_host"}"#.utf8).write(to: manifestURL)

        XCTAssertEqual(fixture.installer.status(for: .brave).manifestState, .updateRequired)
        let repaired = try fixture.installer.update(for: .brave)

        XCTAssertEqual(repaired.manifestState, .installed)
    }

    func testInstallNeverOverwritesUnrelatedManifest() throws {
        let fixture = try makeFixture()
        let manifestURL = fixture.installer.manifestURL(for: .arc)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let unrelatedData = Data(
            #"{"name":"org.example.other_host","description":"Other","path":"/other","type":"stdio","allowed_origins":["chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"]}"#.utf8
        )
        try unrelatedData.write(to: manifestURL)

        XCTAssertThrowsError(try fixture.installer.install(for: .arc)) { error in
            XCTAssertEqual(
                error as? BrowserIntegrationInstallerError,
                .conflictingManifest(
                    browser: .arc,
                    url: manifestURL,
                    existingName: "org.example.other_host"
                )
            )
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), unrelatedData)
    }

    func testInstallNeverOverwritesUnreadableManifest() throws {
        let fixture = try makeFixture()
        let manifestURL = fixture.installer.manifestURL(for: .vivaldi)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingData = Data("not json".utf8)
        try existingData.write(to: manifestURL)

        XCTAssertThrowsError(try fixture.installer.install(for: .vivaldi)) { error in
            guard case .unreadableManifest(let browser, let url, _) = error as? BrowserIntegrationInstallerError else {
                return XCTFail("Expected an unreadableManifest error, received \(error)")
            }
            XCTAssertEqual(browser, .vivaldi)
            XCTAssertEqual(url, manifestURL)
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), existingData)
    }

    func testInstallNeverFollowsOrReplacesManifestSymlink() throws {
        let fixture = try makeFixture()
        let manifestURL = fixture.installer.manifestURL(for: .chrome)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let targetURL = fixture.root.appendingPathComponent("shared-manifest.json")
        let targetData = Data(#"{"name":"com.pinax.native_host"}"#.utf8)
        try targetData.write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: manifestURL,
            withDestinationURL: targetURL
        )

        guard case .unreadable = fixture.installer.status(for: .chrome).manifestState else {
            return XCTFail("Expected a symlink manifest to be unreadable")
        }
        XCTAssertThrowsError(try fixture.installer.install(for: .chrome))
        XCTAssertEqual(try Data(contentsOf: targetURL), targetData)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: manifestURL.path),
            targetURL.path
        )
    }

    func testRemoveDeletesOnlyPinaxOwnedManifest() throws {
        let fixture = try makeFixture()
        let installed = try fixture.installer.install(for: .chromium)

        let removed = try fixture.installer.remove(for: .chromium)

        XCTAssertEqual(removed.manifestState, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.manifestURL.path))
    }

    func testRemoveNeverDeletesUnrelatedManifest() throws {
        let fixture = try makeFixture()
        let manifestURL = fixture.installer.manifestURL(for: .chrome)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let unrelatedData = Data(
            #"{"name":"org.example.other_host","description":"Other","path":"/other","type":"stdio","allowed_origins":[]}"#.utf8
        )
        try unrelatedData.write(to: manifestURL)

        XCTAssertThrowsError(try fixture.installer.remove(for: .chrome))
        XCTAssertEqual(try Data(contentsOf: manifestURL), unrelatedData)
    }

    func testMissingOrNonExecutableHelperPreventsInstallation() throws {
        let fixture = try makeFixture()
        let missingHelper = fixture.root.appendingPathComponent("Missing/PinaxNativeHost")
        let missingInstaller = BrowserIntegrationInstaller(
            homeDirectoryURL: fixture.home,
            helperExecutableURL: missingHelper
        )

        XCTAssertEqual(missingInstaller.status(for: .chrome).helperState, .missing)
        XCTAssertThrowsError(try missingInstaller.install(for: .chrome)) { error in
            XCTAssertEqual(
                error as? BrowserIntegrationInstallerError,
                .helperMissing(missingHelper)
            )
        }

        let nonExecutableHelper = fixture.root.appendingPathComponent("NonExecutable/PinaxNativeHost")
        try FileManager.default.createDirectory(
            at: nonExecutableHelper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: nonExecutableHelper)
        let nonExecutableInstaller = BrowserIntegrationInstaller(
            homeDirectoryURL: fixture.home,
            helperExecutableURL: nonExecutableHelper
        )

        XCTAssertEqual(nonExecutableInstaller.status(for: .chrome).helperState, .notExecutable)
        XCTAssertThrowsError(try nonExecutableInstaller.install(for: .chrome)) { error in
            XCTAssertEqual(
                error as? BrowserIntegrationInstallerError,
                .helperNotExecutable(nonExecutableHelper)
            )
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxBrowserIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let helper = root.appendingPathComponent("Pinax.app/Contents/Helpers/PinaxNativeHost")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try makeExecutable(at: helper)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        return Fixture(
            root: root,
            home: home,
            helper: helper,
            installer: BrowserIntegrationInstaller(
                homeDirectoryURL: home,
                helperExecutableURL: helper
            )
        )
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}

private struct Fixture {
    let root: URL
    let home: URL
    let helper: URL
    let installer: BrowserIntegrationInstaller
}
