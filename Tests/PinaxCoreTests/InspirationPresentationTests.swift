import XCTest
@testable import PinaxCore

final class InspirationPresentationTests: XCTestCase {
    func testXUsernameLabelPrefersNormalizedAuthorHandle() throws {
        let inspiration = try makeInspiration(
            url: "https://x.com/url_handle/status/123",
            authorName: "Display Name",
            authorHandle: " @metadata_handle "
        )

        XCTAssertEqual(inspiration.xUsernameLabel, "@metadata_handle")
    }

    func testXUsernameLabelFallsBackToStatusURLHandle() throws {
        let inspiration = try makeInspiration(
            url: "https://x.com/url_handle/status/123",
            authorName: "Display Name"
        )

        XCTAssertEqual(inspiration.xUsernameLabel, "@url_handle")
    }

    func testXUsernameLabelFallsBackToAuthorNameForHandlelessURL() throws {
        let inspiration = try makeInspiration(
            url: "https://x.com/i/web/status/123",
            authorName: "Display Name"
        )

        XCTAssertEqual(inspiration.xUsernameLabel, "Display Name")
    }

    func testXUsernameLabelIsUnavailableForOtherSources() throws {
        let inspiration = try makeInspiration(
            source: .web,
            url: "https://example.com",
            authorHandle: "example"
        )

        XCTAssertNil(inspiration.xUsernameLabel)
    }

    private func makeInspiration(
        source: CaptureSource = .x,
        url: String,
        authorName: String? = nil,
        authorHandle: String? = nil
    ) throws -> Inspiration {
        let url = try XCTUnwrap(URL(string: url))
        return Inspiration(
            source: source,
            url: url,
            canonicalURL: url,
            authorName: authorName,
            authorHandle: authorHandle
        )
    }
}
