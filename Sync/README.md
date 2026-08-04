# mood. Cloud Sync

`PinaxCloudSync` is an optional, local-first sync layer for the JSON library in
`PinaxCore`. It mirrors projects, inspiration metadata, and feasible local
images into the signed-in user's **private** CloudKit database. The local app
group library remains the source used by the UI and capture extensions, so a
missing account, airplane mode, or CloudKit error never blocks a capture.

## App integration

Enable the iCloud capability with CloudKit for the macOS app, iOS app, and share
extension. Give each target access to the same iCloud container and the existing
mood. App Group. No API key, application account, or mood. server is involved.

Create one engine from the same repository used by the app:

```swift
import PinaxCloudSync
import PinaxCore

let repository = try LibraryRepository.appGroup()
let backend = CloudKitSyncBackend(
    // Omit containerIdentifier to use the target's default iCloud container.
    mediaDirectory: repository.mediaDirectory
)
let engine = try PinaxSyncEngine(repository: repository, backend: backend)

@MainActor
let syncCoordinator = PinaxSyncCoordinator(
    engine: engine,
    remoteChangeSubscriptionProvider: backend,
    isEnabled: userHasEnabledICloudSync
)
```

Retain `syncCoordinator` in app state. From the SwiftUI scene, request a sync
when the app becomes active, and use the same method for an explicit button:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .active {
        syncCoordinator.syncOnActivation()
    }
}

Button("Sync now") {
    Task { await syncCoordinator.sync() }
}
```

`status`, `lastResult`, and `lastError` are observable on the main actor. Setting
`isEnabled` to `false` makes activation and explicit requests no-ops; local
storage continues normally.

## Automatic background updates

The iOS and macOS apps register for remote notifications and call
`prepareForRemoteChanges()` at launch. The CloudKit backend idempotently creates
one silent `CKRecordZoneSubscription` for the private `PinaxLibrary` zone. When
that push arrives, the app runs the normal conflict-aware sync and reloads its
app-group library without needing a restart.

If a push races an already-running foreground sync, mood. awaits that work and
then performs one fresh reconciliation. This prevents a change committed after
the first fetch began from waiting until the next activation.

The iOS target needs the Push Notifications capability, Background Modes with
Background fetch and Remote notifications, and the `aps-environment`
entitlement. The macOS target needs Push Notifications and
`com.apple.developer.aps-environment`. Silent CloudKit pushes do not require a
notification-permission prompt or a mood. push server.

Push delivery is a hint rather than a guarantee: the system may delay,
coalesce, throttle, or suppress it. Keep the existing active-scene sync as a
catch-up path, especially after an iOS force-quit or when Background App Refresh
is disabled.

If the Xcode project does not infer linkage from the Swift package product, add
`CloudKit.framework` to the targets that instantiate `CloudKitSyncBackend`.

## Share extension

Always commit the capture locally first. The extension may then make a short,
best-effort request using the same app-group repository and CloudKit container:

```swift
let repository = try LibraryRepository.appGroup()
let backend = CloudKitSyncBackend(mediaDirectory: repository.mediaDirectory)
let engine = try PinaxSyncEngine(repository: repository, backend: backend)

let outcome = await PinaxBestEffortSync.uploadAfterCapture(
    using: engine,
    timeout: .seconds(4)
)
// Finish the extension request for every outcome. A later app activation retries.
```

The timeout returns without waiting indefinitely for CloudKit and cancels the
engine's active request. CloudKit may still finish an already-submitted system
operation before the extension is suspended, while the already-saved
inspiration remains available in the shared local library either way.

## Data and conflict behavior

- A private custom record zone named `PinaxLibrary` is created lazily.
- UUIDs are stable CloudKit record identities. The newer `updatedAt` value wins;
  equal timestamps use a deterministic encoded-value tie break.
- Deletions overwrite the same record with a timestamped tombstone. A small
  coordinated `pinax-cloud-sync-state.json` baseline in the app group detects
  local deletions and prevents stale offline copies from recreating them.
- Inspirations are deduplicated by `CanonicalURL`, including X/Twitter status
  URL variants. The losing UUID receives a tombstone.
- `localImageFilename` never becomes cross-device identity. If its file exists
  and is at most 45 MB, it is attached as a `CKAsset`; metadata still syncs if
  image transfer is unavailable or fails.
- Server-record races trigger one full refetch and deterministic merge retry.
- No lifecycle, `UIApplication`, or `NSApplication` APIs are used, so the public
  engine and best-effort entry point are app-extension safe.

The backend protocol is public. `InMemoryPinaxSyncBackend` provides a
deterministic implementation for tests and previews without an iCloud account.

## Verification

```sh
swift test --filter PinaxCloudSyncTests
```

The test suite covers last-writer-wins merging, tombstone persistence and
replay, canonical URL deduplication, project deletion repair, asset mutation
selection, coordinator coalescing and error recovery, timeout behavior,
idempotent subscription setup, notification routing, and end-to-end engine
round trips through the fake backend.
