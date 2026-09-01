import Foundation
import Observation

/// Main-actor view model for SwiftUI. The repository remains the source of
/// truth, so `reload()` can be called whenever the app becomes active or an
/// extension/URL capture signals an external change.
@MainActor
@Observable
public final class LibraryStore {
    public private(set) var snapshot: LibrarySnapshot
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    public var searchText = ""
    public var scope: LibraryScope = .all

    @ObservationIgnored
    public let repository: LibraryRepository

    public init(
        repository: LibraryRepository,
        initialSnapshot: LibrarySnapshot = .empty()
    ) {
        self.repository = repository
        snapshot = initialSnapshot
    }

    public var projects: [Project] {
        snapshot.projects
    }

    public var inspirations: [Inspiration] {
        LibraryRepository.filteredInspirations(in: snapshot)
    }

    public var visibleInspirations: [Inspiration] {
        LibraryRepository.filteredInspirations(
            in: snapshot,
            query: searchText,
            scope: scope
        )
    }

    public var counts: ProjectCounts {
        LibraryRepository.counts(in: snapshot)
    }

    public func localImageURL(for inspiration: Inspiration) -> URL? {
        repository.localImageURL(for: inspiration)
    }

    /// Non-throwing by design for `.task`, scene-phase, and external-change
    /// hooks. Failures remain observable through `lastError`.
    public func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await repository.load()
            lastError = nil
        } catch {
            record(error)
        }
    }

    /// Repairs saves that never received a preview image, including Mac
    /// browser captures that already have post text. Network failures are
    /// best-effort and leave the original saved link untouched.
    @discardableResult
    public func enrichMissingXPreviews(
        using fetcher: any WebPreviewFetching = WebPreviewFetcher(),
        maximumCount: Int = 24
    ) async -> Int {
        do {
            let current = try await repository.load()
            let candidates = current.inspirations
                .filter(Self.needsPreviewEnrichment)
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(max(0, maximumCount))

            let previews = await withTaskGroup(
                of: (Inspiration.ID, WebPreview?).self,
                returning: [(Inspiration.ID, WebPreview)].self
            ) { group in
                for inspiration in candidates {
                    group.addTask {
                        (
                            inspiration.id,
                            await fetcher.fetchPreview(for: inspiration.url)
                        )
                    }
                }

                var resolved: [(Inspiration.ID, WebPreview)] = []
                for await (id, preview) in group {
                    if let preview, preview.hasContent {
                        resolved.append((id, preview))
                    }
                }
                return resolved
            }

            var repairedCount = 0
            for (id, preview) in previews {
                guard let before = current.inspirations.first(where: { $0.id == id }) else {
                    continue
                }
                let after = try await repository.enrichInspiration(id: id, with: preview)
                if after != before {
                    repairedCount += 1
                }
            }
            if repairedCount > 0 {
                try await refreshSnapshot()
            }
            return repairedCount
        } catch {
            record(error)
            return 0
        }
    }

    /// Fills a missing remote/local preview after a capture without treating
    /// it as another user save. Returns `true` when library metadata changed.
    @discardableResult
    public func fillMissingPreview(
        for id: Inspiration.ID,
        using fetcher: any WebPreviewFetching = WebPreviewFetcher()
    ) async -> Bool {
        do {
            let current = try await repository.load()
            guard let inspiration = current.inspirations.first(where: { $0.id == id }),
                  Self.needsPreviewEnrichment(inspiration),
                  let preview = await fetcher.fetchPreview(for: inspiration.url),
                  preview.hasContent else {
                return false
            }

            let after = try await repository.enrichInspiration(id: id, with: preview)
            if after != inspiration {
                try await refreshSnapshot()
                return true
            }
            return false
        } catch {
            record(error)
            return false
        }
    }

    @discardableResult
    public func capture(
        _ payload: CapturePayload,
        imageData: Data? = nil,
        imageFileExtension: String? = nil
    ) async throws -> CaptureResult {
        do {
            let result = try await repository.capture(
                payload,
                imageData: imageData,
                imageFileExtension: imageFileExtension
            )
            try await refreshSnapshot()
            return result
        } catch {
            record(error)
            throw error
        }
    }

    @discardableResult
    public func createProject(name: String, colorHex: String? = nil) async throws -> Project {
        do {
            let project = try await repository.createProject(name: name, colorHex: colorHex)
            try await refreshSnapshot()
            return project
        } catch {
            record(error)
            throw error
        }
    }

    @discardableResult
    public func updateProject(
        id: Project.ID,
        name: String,
        colorHex: String? = nil
    ) async throws -> Project {
        do {
            let project = try await repository.updateProject(
                id: id,
                name: name,
                colorHex: colorHex
            )
            try await refreshSnapshot()
            return project
        } catch {
            record(error)
            throw error
        }
    }

    @discardableResult
    public func deleteProject(id: Project.ID) async throws -> Project {
        do {
            let project = try await repository.deleteProject(id: id)
            if scope == .project(id) { scope = .general }
            try await refreshSnapshot()
            return project
        } catch {
            record(error)
            throw error
        }
    }

    @discardableResult
    public func updateInspiration(_ inspiration: Inspiration) async throws -> Inspiration {
        do {
            let inspiration = try await repository.updateInspiration(inspiration)
            try await refreshSnapshot()
            return inspiration
        } catch {
            record(error)
            throw error
        }
    }

    @discardableResult
    public func moveInspiration(
        id: Inspiration.ID,
        to projectID: Project.ID?
    ) async throws -> Inspiration {
        do {
            let inspiration = try await repository.moveInspiration(id: id, to: projectID)
            try await refreshSnapshot()
            return inspiration
        } catch {
            record(error)
            throw error
        }
    }

    @discardableResult
    public func deleteInspiration(id: Inspiration.ID) async throws -> Inspiration {
        do {
            let inspiration = try await repository.deleteInspiration(id: id)
            try await refreshSnapshot()
            return inspiration
        } catch {
            record(error)
            throw error
        }
    }

    public func clearError() {
        lastError = nil
    }

    private func refreshSnapshot() async throws {
        snapshot = try await repository.load()
        lastError = nil
    }

    private func record(_ error: any Error) {
        lastError = error.localizedDescription
    }

    private static func needsPreviewEnrichment(_ inspiration: Inspiration) -> Bool {
        let missingImage = inspiration.imageURL == nil && inspiration.localImageFilename == nil
        let host = inspiration.url.host()?.lowercased() ?? ""
        let isX = inspiration.source == .x
            || host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")

        let title = inspiration.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasPlaceholderTitle = title.isEmpty
            || title == host
            || title == host.replacingOccurrences(of: "www.", with: "")
            || title == inspiration.url.absoluteString.lowercased()
            || title == "saved link"
            || title == "x"
            || title == "twitter"

        if isX {
            return hasPlaceholderTitle || missingImage
        }
        return missingImage
    }
}
