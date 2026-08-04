import Foundation
import XCTest
@testable import PinaxCore

final class CanonicalURLTests: XCTestCase {
    func testXAndTwitterStatusVariantsCollapseToStatusIdentity() throws {
        let variants = [
            "https://twitter.com/DesignDaily/status/1234567890?s=46&t=tracking",
            "https://www.x.com/designdaily/status/1234567890/photo/1#fragment",
            "http://mobile.twitter.com/i/web/status/1234567890",
            "https://x.com/any-handle/statuses/1234567890/video/1",
        ]

        let canonical = try variants.map(CanonicalURL.canonicalize)

        XCTAssertEqual(Set(canonical), [URL(string: "https://x.com/i/status/1234567890")!])
    }

    func testXProfileNormalizesLegacyHostCaseAndShareQuery() throws {
        let canonical = try CanonicalURL.canonicalize(
            "http://WWW.TWITTER.COM/DesignDaily/?s=20&utm_source=share#bio"
        )

        XCTAssertEqual(canonical.absoluteString, "https://x.com/designdaily")
    }

    func testGenericURLRemovesTrackingSortsSemanticQueryAndNormalizesHost() throws {
        let canonical = try CanonicalURL.canonicalize(
            "https://WWW.Example.COM:443/gallery/?utm_source=x&z=2&b=1&fbclid=nope#section"
        )

        XCTAssertEqual(canonical.absoluteString, "https://example.com/gallery?b=1&z=2")
    }

    func testGenericURLResolvesDotSegmentsAndPreservesNonDefaultPort() throws {
        let canonical = try CanonicalURL.canonicalize(
            "http://example.com:8080/a/./b/../board/"
        )

        XCTAssertEqual(canonical.absoluteString, "http://example.com:8080/a/board")
    }

    func testDifferentNonTrackingQueryValuesRemainDistinct() throws {
        let first = try CanonicalURL.canonicalize("https://example.com/work?id=1")
        let second = try CanonicalURL.canonicalize("https://example.com/work?id=2")

        XCTAssertNotEqual(first, second)
    }

    func testRejectsUnsupportedAndRelativeURLs() {
        XCTAssertThrowsError(try CanonicalURL.canonicalize("file:///tmp/image.png"))
        XCTAssertThrowsError(try CanonicalURL.canonicalize("/relative/path"))
        XCTAssertThrowsError(try CanonicalURL.canonicalize("not a url"))
    }
}
