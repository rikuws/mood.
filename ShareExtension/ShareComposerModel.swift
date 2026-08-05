import Observation
import PinaxCloudSync
import PinaxCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class ShareComposerModel {
    enum Phase: Equatable {
        case loading
        case ready
        case extractionFailed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var projects: [Project] = []
    private(set) var url: URL?
    private(set) var source: CaptureSource = .web
    private(set) var imageData: Data?
    private(set) var isSaving = false
    private(set) var storageErrorMessage: String?

    var title = ""
    var note = ""
    var projectID: Project.ID?
    var saveErrorMessage: String?

    @ObservationIgnored
    private var imageFileExtension: String?

    @ObservationIgnored
    private var authorName: String?

    @ObservationIgnored
    private var authorHandle: String?

    @ObservationIgnored
    private var imageURL: URL?

    @ObservationIgnored
    private var store: LibraryStore?

    @ObservationIgnored
    private var syncEngine: PinaxSyncEngine?

    var canSave: Bool {
        phase == .ready
            && url != nil
            && store != nil
            && storageErrorMessage == nil
            && !isSaving
    }

    var previewImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }

    var sourceLabel: String {
        source == .x ? "X post" : "Web link"
    }

    func load(items: [NSExtensionItem]) async {
        phase = .loading
        saveErrorMessage = nil

        do {
            let item = try await ShareItemExtractor.extract(from: items)
            url = item.url
            source = item.sourceHint == "x" ? .x : .web
            title = item.title
            note = item.text
            authorName = item.authorName
            authorHandle = item.authorHandle
            imageURL = item.imageURL
            imageData = item.imageData
            imageFileExtension = item.imageFileExtension
            phase = .ready
        } catch {
            phase = .extractionFailed(error.localizedDescription)
            return
        }

        do {
            let repository = try LibraryRepository.appGroup()
            let store = LibraryStore(repository: repository)
            let backend = CloudKitSyncBackend(
                containerIdentifier: "iCloud.com.rikuwikman.Pinax",
                mediaDirectory: repository.mediaDirectory
            )
            syncEngine = try PinaxSyncEngine(repository: repository, backend: backend)
            self.store = store
            await store.reload()
            projects = store.projects
            if let error = store.lastError {
                storageErrorMessage = storageMessage(for: error)
            }
        } catch {
            storageErrorMessage = storageMessage(for: error)
        }
    }

    /// Returns `true` only after the shared repository confirms the capture.
    func save() async -> Bool {
        guard let url, let store, canSave else { return false }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await store.capture(
                CapturePayload(
                    source: source,
                    url: url,
                    title: title,
                    text: note,
                    authorName: authorName,
                    authorHandle: authorHandle,
                    imageURL: imageURL,
                    projectID: projectID,
                    assignProjectOnDuplicate: true,
                    overwriteMetadataOnDuplicate: true
                ),
                imageData: imageData,
                imageFileExtension: imageFileExtension
            )
            if let syncEngine {
                _ = await PinaxBestEffortSync.uploadAfterCapture(
                    using: syncEngine,
                    timeout: .seconds(3)
                )
            }
            return true
        } catch {
            if case LibraryRepositoryError.appGroupUnavailable = error {
                storageErrorMessage = storageMessage(for: error)
            } else {
                saveErrorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func storageMessage(for error: any Error) -> String {
        if case LibraryRepositoryError.appGroupUnavailable = error {
            return "mood. can't access its shared library. Enable the App Group \(PinaxStorage.appGroupIdentifier) for both the app and Share Extension, then try again."
        }
        return "mood. couldn't open its shared library: \(error.localizedDescription)"
    }

    private func storageMessage(for message: String) -> String {
        "mood. couldn't open its shared library: \(message)"
    }
}
