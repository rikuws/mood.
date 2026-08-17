import CoreGraphics
import ImageIO
import XCTest
@testable import PinaxCore

final class PreviewImageDecoderTests: XCTestCase {
    func testThumbnailPixelSizeUsesStableBucketsAndCapsAtTheMaximum() {
        XCTAssertEqual(PreviewImageDecoder.thumbnailPixelSize(forLongestSide: 10), 256)
        XCTAssertEqual(PreviewImageDecoder.thumbnailPixelSize(forLongestSide: 256), 256)
        XCTAssertEqual(PreviewImageDecoder.thumbnailPixelSize(forLongestSide: 257), 512)
        XCTAssertEqual(PreviewImageDecoder.thumbnailPixelSize(forLongestSide: 1_800), 2_048)
        XCTAssertEqual(PreviewImageDecoder.thumbnailPixelSize(forLongestSide: 8_000), 2_048)
        XCTAssertEqual(PreviewImageDecoder.thumbnailPixelSize(forLongestSide: 0), 256)
    }

    func testThumbnailDownsamplesToTheRequestedLongestEdge() throws {
        let url = try writeJPEG(width: 2_000, height: 1_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = try XCTUnwrap(
            PreviewImageDecoder.thumbnail(fromFileURL: url, maxPixelSize: 256)
        )

        XCTAssertEqual(thumbnail.width, 256)
        XCTAssertEqual(thumbnail.height, 128)
    }

    func testThumbnailFromDataMatchesFileDecoding() throws {
        let data = try jpegData(width: 800, height: 400)
        let thumbnail = try XCTUnwrap(
            PreviewImageDecoder.thumbnail(from: data, maxPixelSize: 256)
        )

        XCTAssertEqual(thumbnail.width, 256)
        XCTAssertEqual(thumbnail.height, 128)
    }

    func testPixelSizeReadsEncodedDimensions() throws {
        let url = try writeJPEG(width: 1_200, height: 400)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            PreviewImageDecoder.pixelSize(at: url),
            CGSize(width: 1_200, height: 400)
        )
        XCTAssertEqual(
            PreviewImageDecoder.aspectRatio(at: url, clampedTo: 0.8...1.35),
            1.35
        )
    }

    func testPixelSizeSwapsDimensionsForRotatedEXIFOrientation() throws {
        let url = try writeJPEG(width: 2_000, height: 1_000, orientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            PreviewImageDecoder.pixelSize(at: url),
            CGSize(width: 1_000, height: 2_000)
        )
        XCTAssertEqual(
            PreviewImageDecoder.aspectRatio(at: url, clampedTo: 0.8...1.35),
            0.8
        )
    }

    private func writeJPEG(width: Int, height: Int, orientation: Int = 1) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try jpegData(width: width, height: height, orientation: orientation)
            .write(to: url)
        return url
    }

    private func jpegData(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            struct ContextError: Error {}
            throw ContextError()
        }

        context.setFillColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))

        guard let image = context.makeImage() else {
            struct ImageError: Error {}
            throw ImageError()
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            struct DestinationError: Error {}
            throw DestinationError()
        }

        let properties = [kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
