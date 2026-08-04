# Pinax

Pinax is a local-first moodbook for collecting visual inspiration from X and the web. The native macOS and iOS apps share one library model with General and project collections, search, editing, drag-and-drop or manual link capture, and private CloudKit sync.

Capture surfaces are included for:

- a Chromium toolbar action for the current page;
- a Pinax action beside posts on X;
- X's own Bookmark action (Remove bookmark is ignored);
- the iOS system Share sheet, including X's **Share via…** flow.

See [Documentation/ARCHITECTURE.md](Documentation/ARCHITECTURE.md) for storage, native messaging, and sync details. The macOS app also bundles a read-only [agent API](Documentation/AGENT_API.md) for fetching projects and their inspirations as versioned JSON.

## Requirements

- macOS 14 or newer and Xcode with the macOS 14 / iOS 17 SDKs;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate `Pinax.xcodeproj` from `project.yml`;
- Swift 6 toolchain;
- Node.js 20 or newer for the Chromium extension;
- an Apple Developer team for signed App Group and CloudKit builds.

No npm packages, server, API key, or Pinax account are required.

## Generate and build

Build the browser extension before the Mac app so Xcode can copy the current `dist` bundle into `Pinax.app`:

```sh
cd BrowserExtension
npm run check
cd ..

xcodegen generate

xcodebuild \
  -project Pinax.xcodeproj \
  -scheme PinaxMac \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/PinaxDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project Pinax.xcodeproj \
  -scheme PinaxiOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PinaxDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Those `CODE_SIGNING_ALLOWED=NO` commands verify compilation only. The unsigned Mac app deliberately stores its development library under Application Support and does not initialize CloudKit, because it has no effective App Group or iCloud entitlement. Use a properly signed build to verify shared-container and cross-device behavior.

For normal development, open `Pinax.xcodeproj`, select a team for **PinaxMac**, **PinaxiOS**, and **PinaxShareExtension**, then run the corresponding shared scheme. `project.yml` is the project source of truth; regenerate after changing it instead of hand-editing the generated project.

## Apple capabilities and signing

All three app targets must be provisioned by the same Apple Developer team with:

```text
App Group: group.com.rikuwikman.pinax
iCloud container: iCloud.com.rikuwikman.Pinax
iCloud service: CloudKit
```

The configured bundle identifiers are:

```text
macOS and iOS app: com.rikuwikman.Pinax
iOS Share Extension: com.rikuwikman.Pinax.ShareExtension
```

Create or register the App Group, iCloud container, and bundle identifiers in the Apple Developer account, add them to the profiles used by every target, and let Xcode resolve signing. A local Apple Development certificate and automatic signing are still required even though the entitlement files and XcodeGen configuration are already present.

Pinax uses the signed-in user's private CloudKit database. Shipping outside the development environment also requires deploying the CloudKit schema to production through Apple's CloudKit tooling. The repository has deterministic sync tests, but a live CloudKit round trip has not been claimed or verified without a signed, provisioned container and an iCloud account.

## Chromium setup on macOS

Pinax supports Google Chrome, Chromium, Brave, Microsoft Edge, Arc, and Vivaldi.

1. Build and launch the signed/direct Mac app. The app bundle contains both `Contents/Helpers/PinaxNativeHost` and `Contents/Resources/BrowserExtension`.
2. In Pinax, open **Browser Setup** and choose **Install for all browsers** (or install one browser). This writes only Pinax's user-level `com.pinax.native_host.json` manifest, pointing to the helper inside the current app bundle.
3. In the browser, open `chrome://extensions` (or `edge://extensions`), enable Developer mode, choose **Load unpacked**, and select the BrowserExtension folder shown by Pinax. During repository development, `BrowserExtension/dist` is the equivalent folder.
4. Pin the extension if desired. Its toolbar button saves the active HTTP(S) page. On X, use the injected Pinax action or add the post to X Bookmarks.

The unpacked extension has the fixed ID `ohhhjpbfjecipcnkahlhaggckmdjfndg`; the installed native-host manifest authorizes that exact origin. Rerun Browser Setup after moving the app, because Chromium manifests contain an absolute helper path.

The native host validates a capture and targets the Pinax app bundled around it with `pinax://capture`. It waits for a request-ID-correlated acknowledgement written only after the app's coordinated repository transaction, then returns the real item ID and duplicate state. Browser feedback saying “Saved to Pinax” therefore means the local library commit succeeded; dispatch failures, save errors, and confirmation timeouts are shown as errors.

## Agent API on macOS

The Mac app bundles `Contents/Helpers/pinax-agent`, a local read-only JSON API intended for
agent skills and other automation. It reads through `LibraryRepository`, so requests see the
same coordinated App Group snapshot as the UI without requiring Pinax to be open.

```sh
/Applications/Pinax.app/Contents/Helpers/pinax-agent projects --pretty
/Applications/Pinax.app/Contents/Helpers/pinax-agent inspirations --project "Website refresh" --pretty
```

See [Documentation/AGENT_API.md](Documentation/AGENT_API.md) for the version 1 response
schema, local-image paths, exit behavior, and stable error codes.

## Share from iOS and X

1. Build, sign, and install the **PinaxiOS** scheme; the **Save to Pinax** Share Extension is embedded automatically.
2. Open Pinax once and create any projects you want available in the share composer.
3. In X, tap the post's Share action, choose **Share via…**, then select **Save to Pinax**. If it is hidden, choose **More** and enable it.
4. Review the title and note, choose General or a project, and tap **Save**.

The extension also accepts HTTP(S) links shared by other iOS apps. It commits to the App Group library first, then attempts a short best-effort CloudKit upload; a failed or timed-out upload does not discard the local save, and the next app activation retries normal sync.

## Test

```sh
# Core repository and deterministic CloudKit sync tests
swift test

# Chromium native messaging protocol and URL bridge
(cd NativeHost && swift test)

# Browser manifest installation and safety checks
(cd Mac/BrowserIntegration && swift test)

# Extension tests, validation, and dist build
(cd BrowserExtension && npm run check)
```

## Repository map

```text
Shared/                 Local models, canonical URL dedupe, coordinated JSON repository
AgentAPI/               Bundled read-only JSON command API for agent skills
Sync/                   CloudKit backend, merge engine, tombstones, sync state and tests
Mac/                    Native macOS library UI and Chromium installer
iOS/                    Native iOS library UI
ShareExtension/         iOS share composer and item extraction
BrowserExtension/       Manifest V3 Chromium extension
NativeHost/             Native messaging executable and protocol tests
Documentation/          Architecture notes
project.yml             XcodeGen source of truth
```
