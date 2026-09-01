import Foundation
import XCTest
@testable import PinaxCore

final class WebPreviewTests: XCTestCase {
    func testParsesCurrentXOpenGraphMetadataAndDecodesEntities() throws {
        let html = #"""
        <!doctype html>
        <html><head>
        <meta content="Kazu &amp; Co. (@pnly_tar) on X" property="og:title">
        <meta property="og:description" content="First line&#10;&#10;Second &quot;line&quot;">
        <meta name="twitter:creator" content="@pnly_tar">
        <meta property="og:image:secure_url" content="https://pbs.twimg.com/media/example?format=jpg&amp;name=large">
        </head></html>
        """#

        let preview = WebPreviewHTMLParser.parse(
            html,
            pageURL: try XCTUnwrap(URL(string: "https://x.com/pnly_tar/status/123?s=12"))
        )

        XCTAssertEqual(preview.title, "Kazu & Co. (@pnly_tar) on X")
        XCTAssertEqual(preview.text, "First line\n\nSecond \"line\"")
        XCTAssertEqual(preview.authorName, "Kazu & Co.")
        XCTAssertEqual(preview.authorHandle, "pnly_tar")
        XCTAssertEqual(
            preview.imageURL?.absoluteString,
            "https://pbs.twimg.com/media/example?format=jpg&name=large"
        )
    }

    func testRejectsUnsafePreviewImageSchemes() throws {
        let html = #"<meta property="og:image" content="file:///tmp/private.jpg">"#
        let preview = WebPreviewHTMLParser.parse(
            html,
            pageURL: try XCTUnwrap(URL(string: "https://x.com/pinax/status/123"))
        )
        XCTAssertNil(preview.imageURL)
    }

    func testRejectsXsGenericFallbackImage() throws {
        let html = #"<meta property="og:image" content="https://abs.twimg.com/rweb/ssr/default/v2/og/image.png">"#
        let preview = WebPreviewHTMLParser.parse(
            html,
            pageURL: try XCTUnwrap(URL(string: "https://x.com/pinax/status/123"))
        )
        XCTAssertNil(preview.imageURL)
    }

    func testRejectsXProfileImagesAsPreview() throws {
        let html = #"<meta property="og:image" content="https://pbs.twimg.com/profile_images/123/avatar.jpg">"#
        let preview = WebPreviewHTMLParser.parse(
            html,
            pageURL: try XCTUnwrap(URL(string: "https://x.com/pinax/status/123"))
        )
        XCTAssertNil(preview.imageURL)
    }

    func testRepositoryEnrichmentRepairsPlaceholderWithoutCountingAnotherCapture() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try LibraryRepository(storageDirectory: directory)
        let url = try XCTUnwrap(URL(string: "https://x.com/pnly_tar/status/123?s=12"))
        let captured = try await repository.capture(
            CapturePayload(source: .x, url: url, title: "x.com")
        )

        let enriched = try await repository.enrichInspiration(
            id: captured.inspiration.id,
            with: WebPreview(
                title: "Kazu (@pnly_tar) on X",
                text: "A visual post",
                authorName: "Kazu",
                authorHandle: "@pnly_tar",
                imageURL: URL(string: "https://pbs.twimg.com/media/example.jpg:large"),
                imageData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
                imageFileExtension: "jpg"
            )
        )

        XCTAssertEqual(enriched.title, "Kazu (@pnly_tar) on X")
        XCTAssertEqual(enriched.text, "A visual post")
        XCTAssertEqual(enriched.authorName, "Kazu")
        XCTAssertEqual(enriched.authorHandle, "pnly_tar")
        XCTAssertEqual(enriched.captureCount, 1)
        XCTAssertNotNil(enriched.localImageFilename)
        XCTAssertTrue(
            try XCTUnwrap(repository.localImageURL(for: enriched)).checkResourceIsReachable()
        )
    }

    @MainActor
    func testStoreRepairsLegacyURLOnlyXSavesUsingInjectedFetcher() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try LibraryRepository(storageDirectory: directory)
        let url = try XCTUnwrap(URL(string: "https://x.com/pinax/status/456?s=12"))
        _ = try await repository.capture(
            CapturePayload(source: .x, url: url, title: "x.com")
        )
        let store = LibraryStore(repository: repository)

        let count = await store.enrichMissingXPreviews(
            using: FixturePreviewFetcher(
                preview: WebPreview(
                    title: "Pinax (@pinax) on X",
                    text: "Preview restored",
                    authorName: "Pinax",
                    authorHandle: "pinax",
                    imageURL: URL(string: "https://pbs.twimg.com/media/restored.jpg")
                )
            )
        )

        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.inspirations.first?.title, "Pinax (@pinax) on X")
        XCTAssertEqual(store.inspirations.first?.text, "Preview restored")
        XCTAssertEqual(
            store.inspirations.first?.imageURL?.absoluteString,
            "https://pbs.twimg.com/media/restored.jpg"
        )
    }

    @MainActor
    func testStoreRepairsImageLessXSavesThatAlreadyHavePostCopy() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try LibraryRepository(storageDirectory: directory)
        let url = try XCTUnwrap(URL(string: "https://x.com/akhakim_/status/2093251204705140809"))
        _ = try await repository.capture(
            CapturePayload(
                source: .x,
                url: url,
                title: "@akhakim_: Workspace availability dashboard.",
                text: "Workspace availability dashboard.",
                authorName: "Achmad Hakim",
                authorHandle: "akhakim_"
            )
        )
        let store = LibraryStore(repository: repository)

        let count = await store.enrichMissingXPreviews(
            using: FixturePreviewFetcher(
                preview: WebPreview(
                    title: "Achmad Hakim (@akhakim_) on X",
                    text: "Workspace availability dashboard.",
                    authorName: "Achmad Hakim",
                    authorHandle: "akhakim_",
                    imageURL: URL(string: "https://pbs.twimg.com/media/HQy43uLaAAAABib.jpg:large"),
                    imageData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
                    imageFileExtension: "jpg"
                )
            )
        )

        XCTAssertEqual(count, 1)
        XCTAssertEqual(
            store.inspirations.first?.title,
            "@akhakim_: Workspace availability dashboard."
        )
        XCTAssertEqual(
            store.inspirations.first?.imageURL?.absoluteString,
            "https://pbs.twimg.com/media/HQy43uLaAAAABib.jpg:large"
        )
        XCTAssertNotNil(store.inspirations.first?.localImageFilename)
    }

    @MainActor
    func testCaptureHydratesMissingPreviewWithoutOverwritingPostCopy() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try LibraryRepository(storageDirectory: directory)
        let url = try XCTUnwrap(URL(string: "https://x.com/AdityaSur11/status/2093345358877266398"))
        let store = LibraryStore(repository: repository)
        let captured = try await store.capture(
            CapturePayload(
                source: .x,
                url: url,
                title: "@AdityaSur11: Onboarding checklist UI",
                text: "Onboarding checklist UI",
                authorName: "Adi",
                authorHandle: "AdityaSur11"
            )
        )
        let hydrated = await store.fillMissingPreview(
            for: captured.inspiration.id,
            using: FixturePreviewFetcher(
                preview: WebPreview(
                    title: "Adi (@AdityaSur11) on X",
                    text: "Onboarding checklist UI",
                    imageURL: URL(string: "https://pbs.twimg.com/media/onboarding.jpg:large"),
                    imageData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
                    imageFileExtension: "jpg"
                )
            )
        )

        XCTAssertTrue(hydrated)
        XCTAssertEqual(
            store.inspirations.first?.title,
            "@AdityaSur11: Onboarding checklist UI"
        )
        XCTAssertEqual(store.inspirations.first?.authorHandle, "AdityaSur11")
        XCTAssertEqual(
            store.inspirations.first?.imageURL?.absoluteString,
            "https://pbs.twimg.com/media/onboarding.jpg:large"
        )
        XCTAssertNotNil(store.inspirations.first?.localImageFilename)
    }
}

private struct FixturePreviewFetcher: WebPreviewFetching {
    let preview: WebPreview?

    func fetchPreview(for url: URL) async -> WebPreview? {
        preview
    }
}
