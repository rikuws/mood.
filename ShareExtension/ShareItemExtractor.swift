import Foundation
import PinaxCore
import UIKit
import UniformTypeIdentifiers

struct ExtractedShareItem: Sendable {
    let url: URL
    let title: String
    let text: String
    let authorName: String?
    let authorHandle: String?
    let imageURL: URL?
    let imageData: Data?
    let imageFileExtension: String?

    var sourceHint: String {
        guard let host = url.host()?.lowercased() else { return "web" }
        return host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com")
            ? "x"
            : "web"
    }
}

enum ShareExtractionError: LocalizedError {
    case noURL

    var errorDescription: String? {
        switch self {
        case .noURL:
            "mood. couldn't find a web link in this share."
        }
    }
}

enum ShareItemExtractor {
    private static let providerTimeout: TimeInterval = 1.0
    private static let maximumImageBytes = 20 * 1_024 * 1_024
    private static let maximumTextCharacters = 100_000

    @MainActor
    static func extract(from items: [NSExtensionItem]) async throws -> ExtractedShareItem {
        let attributedTitle = items.lazy.compactMap(\.attributedTitle?.string).first
        let attributedText = items.lazy.compactMap(\.attributedContentText?.string).first

        let providers = items.flatMap { $0.attachments ?? [] }
        var sharedText = attributedText
        var sharedURL: URL?

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(from: provider, timeout: providerTimeout), isWebURL(url) {
                sharedURL = url
                break
            }
        }

        if sharedURL == nil {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = await loadText(from: provider, timeout: providerTimeout) {
                    sharedText = sharedText ?? text
                    if let url = firstWebURL(in: text) {
                        sharedURL = url
                        break
                    }
                }
            }
        }

        if sharedURL == nil, let attributedText {
            sharedURL = firstWebURL(in: attributedText)
        }

        guard let sharedURL else { throw ShareExtractionError.noURL }

        // Image extraction is optional. Some source apps advertise an image
        // provider that never calls back; never let that prevent the URL from
        // reaching the composer.
        let sharedImage = await loadFirstImage(
            from: providers,
            timeout: providerTimeout,
            maximumBytes: maximumImageBytes
        )
        let remotePreview = isXURL(sharedURL)
            ? await WebPreviewFetcher().fetchPreview(for: sharedURL)
            : nil
        return makeItem(
            url: sharedURL,
            title: attributedTitle,
            text: sharedText,
            sharedImage: sharedImage,
            remotePreview: remotePreview
        )
    }

    @MainActor
    private static func loadFirstImage(
        from providers: [NSItemProvider],
        timeout: TimeInterval,
        maximumBytes: Int
    ) async -> (Data, String)? {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let gate = ProviderLoadGate<(Data, String)>(continuation: continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                gate.resolve(nil)
            }
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                guard error == nil else {
                    gate.resolve(nil)
                    return
                }

                if let image = item as? UIImage,
                   let data = image.jpegData(compressionQuality: 0.9),
                   data.count <= maximumBytes {
                    gate.resolve((data, "jpg"))
                } else if let url = item as? URL,
                          let data = boundedData(from: url, maximumBytes: maximumBytes) {
                    gate.resolve((data, url.pathExtension.isEmpty ? "jpg" : url.pathExtension))
                } else if let data = item as? Data,
                          !data.isEmpty,
                          data.count <= maximumBytes {
                    gate.resolve((data, "jpg"))
                } else {
                    gate.resolve(nil)
                }
            }
        }
    }

    @MainActor
    private static func loadURL(
        from provider: NSItemProvider,
        timeout: TimeInterval
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let gate = ProviderLoadGate<URL>(continuation: continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                gate.resolve(nil)
            }
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if error != nil {
                    gate.resolve(nil)
                    return
                }

                switch item {
                case let url as URL:
                    gate.resolve(url)
                case let url as NSURL:
                    gate.resolve(url as URL)
                case let data as Data where data.count <= 16_384:
                    gate.resolve(URL(dataRepresentation: data, relativeTo: nil))
                case let text as String:
                    gate.resolve(URL(string: String(text.prefix(16_384))))
                default:
                    gate.resolve(nil)
                }
            }
        }
    }

    @MainActor
    private static func loadText(
        from provider: NSItemProvider,
        timeout: TimeInterval
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let gate = ProviderLoadGate<String>(continuation: continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                gate.resolve(nil)
            }
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if error != nil {
                    gate.resolve(nil)
                    return
                }

                switch item {
                case let text as String:
                    gate.resolve(String(text.prefix(maximumTextCharacters)))
                case let text as NSString:
                    gate.resolve(String((text as String).prefix(maximumTextCharacters)))
                case let data as Data where data.count <= 1_024 * 1_024:
                    gate.resolve(
                        String(data: data, encoding: .utf8)
                            .map { String($0.prefix(maximumTextCharacters)) }
                    )
                default:
                    gate.resolve(nil)
                }
            }
        }
    }

    private static func boundedData(from url: URL, maximumBytes: Int) -> Data? {
        guard url.isFileURL,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumBytes + 1),
              !data.isEmpty,
              data.count <= maximumBytes else {
            return nil
        }
        return data
    }

    private static func makeItem(
        url: URL,
        title: String?,
        text: String?,
        sharedImage: (Data, String)?,
        remotePreview: WebPreview?
    ) -> ExtractedShareItem {
        let cleanedText = text?
            .replacingOccurrences(of: url.absoluteString, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedText = remotePreview?.text?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? cleanedText.nonEmpty
            ?? ""
        let resolvedTitle = remotePreview?.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? resolvedText.nonEmpty
            ?? url.host()
            ?? "Saved link"

        return ExtractedShareItem(
            url: url,
            title: resolvedTitle,
            text: resolvedText,
            authorName: remotePreview?.authorName,
            authorHandle: remotePreview?.authorHandle,
            imageURL: remotePreview?.imageURL,
            imageData: sharedImage?.0 ?? remotePreview?.imageData,
            imageFileExtension: sharedImage?.1 ?? remotePreview?.imageFileExtension
        )
    }

    private static func firstWebURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first(where: isWebURL)
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host() != nil
    }

    private static func isXURL(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
    }
}

private final class ProviderLoadGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var isResolved = false
    private let continuation: CheckedContinuation<Value?, Never>

    init(continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Value?) {
        let shouldResume = lock.withLock {
            guard !isResolved else { return false }
            isResolved = true
            return true
        }
        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
