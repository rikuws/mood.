# mood.

mood. is a local-first native macOS and iOS visual moodboard for collecting imagery, text, authorship, and source context into General and Projects. Mac and iOS share one coordinated App Group library (`library.json` plus `Media/`) with an optional private CloudKit replica. Capture surfaces are a Chromium toolbar action, an injected mood. control on X, and the iOS Share sheet (including X **Share via…**). Design is restrained and native: collected content carries personality; Apple navigation, sheets, menus, and gestures stay standard.

## Architecture

- `Mac/`: macOS lifecycle, SwiftUI library UI, resources, and Chromium native-messaging installer (`Mac/BrowserIntegration`); built by `PinaxMac` as `mood.app`.
- `iOS/`: iOS/iPadOS lifecycle, views, support, and resources; built by `PinaxiOS`, which embeds the share extension.
- `Shared/`: `PinaxCore` package target—models, URL canonicalization, `LibraryRepository` actor, observable store, previews, product identity, and agent API contract.
- `AppUI/`: platform-shared SwiftUI image-loading UI included directly in both application targets.
- `Sync/`: `PinaxCloudSync` target—CloudKit backend, merge/tombstone logic, coordinator, and colocated tests.
- `ShareExtension/`: UIKit/SwiftUI share composer that writes to the App Group before a bounded best-effort sync.
- `BrowserExtension/`: source-only Manifest V3 Chromium extension, Node tests/build script, and ignored generated `dist/`.
- `NativeHost/`: separate Swift package and Xcode library/tool targets for framed native messaging and the `pinax://capture` bridge.
- `AgentAPI/`: `pinax-agent` executable source; read-only JSON through `LibraryRepository`; bundled into the Mac app.
- `skills/`: portable Agent Skills. `mood-distill` fetches a project through `pinax-agent` and synthesizes creative direction from saved imagery and notes.
- `Tests/`: root `PinaxCoreTests`. Also `Sync/Tests`, `NativeHost/Tests`, `Mac/BrowserIntegration/Tests`, and `BrowserExtension/tests`.

## Generate and open

`project.yml` defines targets, schemes, dependencies, entitlements, bundle metadata, and helper bundling. Treat the tracked `Pinax.xcodeproj` as generated output and never hand-edit it.

```sh
xcodegen generate
open Pinax.xcodeproj
```

## Build

Use the shared application schemes `PinaxMac` and `PinaxiOS` (Xcode also lists package-generated helper schemes). Refresh `BrowserExtension/dist` with `(cd BrowserExtension && npm run check)` before the Mac build so the current extension is bundled.

```sh
xcodebuild -project Pinax.xcodeproj -scheme PinaxMac \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/PinaxDerivedData \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Pinax.xcodeproj -scheme PinaxiOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PinaxDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Unsigned builds prove compilation only. The unsigned Mac app uses Application Support and skips CloudKit. They do not validate App Group storage, browser installation, signing, or live CloudKit.

## Test

```sh
swift test
(cd NativeHost && swift test)
(cd Mac/BrowserIntegration && swift test)
(cd BrowserExtension && npm run check)
bash skills/mood-distill/tests/find-pinax-agent.test.sh
```

`swift test` runs `PinaxCoreTests` and deterministic `PinaxCloudSyncTests`. Signed, provisioned targets are required for App Group and live CloudKit.

## Conventions

- Swift 6 with complete strict concurrency in the generated app project.
- Four-space indentation, UpperCamelCase types/files, lowerCamelCase members, trailing commas in multiline declarations, and private helpers near their owning type.
- Value models conform to `Codable`, equality/hash protocols, and `Sendable` as appropriate.
- Persistence and sync use actors; SwiftUI-facing state uses `@MainActor`, Observation’s `@Observable`, `@State`, and `@Environment`.
- Async/await, protocol injection, explicit `any`, and deterministic XCTest fixtures are common.
- No SwiftLint, SwiftFormat, or repository-wide formatting configuration is present.

## Gotchas

- Preserve Pinax bundle IDs (`com.rikuwikman.Pinax`, `.ShareExtension`, `.AgentAPI`), App Group `group.com.rikuwikman.pinax`, CloudKit `iCloud.com.rikuwikman.Pinax`, URL scheme `pinax`, native-host name `com.pinax.native_host`, extension key/ID `ohhhjpbfjecipcnkahlhaggckmdjfndg`, helpers `PinaxNativeHost`/`pinax-agent`, and persisted schemas (library/sync version 1).
- Signed App Group/CloudKit behavior requires the same provisioned Apple team across the apps, share extension, and agent helper.
- Unsigned Mac builds use Application Support and skip CloudKit; unsigned builds prove compilation only.
- Browser manifests contain absolute helper paths and must be reinstalled after moving the app.
- Do not edit `BrowserExtension/dist` or `Pinax.xcodeproj` directly.
- Keep the Mac direct-distribution/browser-integration boundary in mind before enabling sandboxing.
