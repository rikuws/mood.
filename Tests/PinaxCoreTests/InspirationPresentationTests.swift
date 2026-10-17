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

    func testMeaningfulTitleKeepsARealTitle() throws {
        let inspiration = try makeInspiration(
            source: .web,
            url: "https://example.com/work/still.jpg",
            title: "  Pod bay, lit from the floor  "
        )

        XCTAssertEqual(inspiration.meaningfulTitle, "Pod bay, lit from the floor")
    }

    func testMeaningfulTitleDropsImageFileNames() throws {
        let titles = [
            "IMG_2041.jpeg",
            "poster final.PNG",
            "GxYz12 (1200×800)",
            "still.jpg (JPEG Image, 1200 × 800 pixels)",
            "still.jpg 1,200×800 pixels",
            "GxYz12",
        ]
        for title in titles {
            let inspiration = try makeInspiration(
                source: .web,
                url: "https://pbs.example.com/media/GxYz12?format=jpg",
                title: title
            )
            XCTAssertNil(inspiration.meaningfulTitle, title)
        }
    }

    func testMeaningfulTitleDropsTheImageURLsOwnFileName() throws {
        let inspiration = try makeInspiration(
            source: .web,
            url: "https://example.com/gallery",
            title: "dune-04",
            imageURL: "https://cdn.example.com/dune-04.webp"
        )

        XCTAssertNil(inspiration.meaningfulTitle)
    }

    func testMeaningfulTitleDropsAddressesAndPlaceholders() throws {
        for title in ["", "www.example.com", "example.com", "https://www.example.com/a", "Saved link"] {
            let inspiration = try makeInspiration(
                source: .web,
                url: "https://www.example.com/a",
                title: title
            )
            XCTAssertNil(inspiration.meaningfulTitle, title)
        }
    }

    func testMeaningfulTitleKeepsSizesThatArentPixelDimensions() throws {
        let inspiration = try makeInspiration(
            source: .web,
            url: "https://example.com/work",
            title: "Untitled (50 x 70 cm)"
        )

        XCTAssertEqual(inspiration.meaningfulTitle, "Untitled (50 x 70 cm)")
    }

    private func makeInspiration(
        source: CaptureSource = .x,
        url: String,
        title: String = "",
        authorName: String? = nil,
        authorHandle: String? = nil,
        imageURL: String? = nil
    ) throws -> Inspiration {
        let url = try XCTUnwrap(URL(string: url))
        return Inspiration(
            source: source,
            url: url,
            canonicalURL: url,
            title: title,
            authorName: authorName,
            authorHandle: authorHandle,
            imageURL: imageURL.flatMap(URL.init(string:))
        )
    }
}
