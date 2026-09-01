# mood.

mood. is a local-first visual moodboard for collecting anything that catches your eye on X and the web—from interfaces and typography to interiors, fashion, objects, places, and art. The native macOS and iOS apps share one library model with General and Projects, search, editing, drag-and-drop or manual link capture, and private CloudKit sync.

Capture surfaces are included for:

- a Chromium toolbar action for the current page;
- a mood. action beside posts on X;
- X's own Bookmark action (Remove bookmark is ignored);
- the iOS system Share sheet, including X's **Share via…** flow.

See [Documentation/ARCHITECTURE.md](Documentation/ARCHITECTURE.md) for storage, native messaging, and sync details. The macOS app also bundles a read-only [agent API](Documentation/AGENT_API.md) for fetching projects and their saved items as versioned JSON. The [`mood-distill`](skills/mood-distill) skill turns those visuals—or one arbitrary image—into an evidence-grounded, portable [design essence](Documentation/DESIGN_ESSENCE.md).

## Requirements

- macOS 14 or newer and Xcode with the macOS 14 / iOS 17 SDKs;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate `Pinax.xcodeproj` from `project.yml`;
- Swift 6 toolchain;
- Node.js 20 or newer for the Chromium extension;
- an Apple Developer team for signed App Group and CloudKit builds.

No npm packages, server, API key, or mood. account are required.

## Generate and build

Build the browser extension before the Mac app so Xcode can copy the current `dist` bundle into `mood.app`:

User-visible names are mood. The Mac app wrapper is `mood.app` so Finder, Dock, and the application menu match. Compatibility-sensitive project, bundle identifier, helper, storage, CloudKit, URL-scheme, and extension identities retain their existing Pinax names so installed libraries and integrations keep working. Replace any leftover `/Applications/Pinax.app` after installing, then rerun Browser Setup so native-host manifests point at the new bundle path.

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

mood. uses the signed-in user's private CloudKit database. Shipping outside the development environment also requires deploying the CloudKit schema to production through Apple's CloudKit tooling. The repository has deterministic sync tests, but a live CloudKit round trip has not been claimed or verified without a signed, provisioned container and an iCloud account.

## Chromium setup on macOS

mood. supports Google Chrome, Chromium, Brave, Microsoft Edge, Arc, and Vivaldi.

1. Build and launch the signed/direct Mac app. The app bundle contains both `Contents/Helpers/PinaxNativeHost` and `Contents/Resources/BrowserExtension`.
2. In mood., open **Browser Setup** and choose **Install for all browsers** (or install one browser). This writes only the app's user-level `com.pinax.native_host.json` manifest, pointing to the helper inside the current app bundle.
3. In the browser, open `chrome://extensions` (or `edge://extensions`), enable Developer mode, choose **Load unpacked**, and select the BrowserExtension folder shown by mood. During repository development, `BrowserExtension/dist` is the equivalent folder.
4. Pin the extension if desired. Its toolbar button saves the active HTTP(S) page. On X, use the injected mood. action or add the post to X Bookmarks.

The unpacked extension has the fixed ID `ohhhjpbfjecipcnkahlhaggckmdjfndg`; the installed native-host manifest authorizes that exact origin. Rerun Browser Setup after moving the app, because Chromium manifests contain an absolute helper path.

The native host validates a capture and targets the containing `mood.app` bundle with the compatibility-preserved `pinax://capture` route. It waits for a request-ID-correlated acknowledgement written only after the app's coordinated repository transaction, then returns the real item ID and duplicate state. Browser feedback saying “Saved to mood.” therefore means the local library commit succeeded; dispatch failures, save errors, and confirmation timeouts are shown as errors.

## Agent API on macOS

The Mac app bundles `Contents/Helpers/mood-agent`, a local read-only JSON API intended for
agent skills and other automation. It reads through `LibraryRepository`, so requests see the
same coordinated App Group snapshot as the UI without requiring mood. to be open.

```sh
/Applications/mood.app/Contents/Helpers/mood-agent projects --pretty
/Applications/mood.app/Contents/Helpers/mood-agent inspirations --project "Website refresh" --pretty
/Applications/mood.app/Contents/Helpers/mood-agent inspiration --id <item-uuid> --pretty
```

See [Documentation/AGENT_API.md](Documentation/AGENT_API.md) for the version 1 response
schema, local-image paths, exit behavior, and stable error codes.

To turn a project, one saved item, or an arbitrary image into portable creative direction,
install the [`mood-distill`](skills/mood-distill) agent skill. It separates visible evidence,
abstraction, and directives; discounts duplicate references; preserves uncertainty; and
validates a canonical `DesignEssence` 1.0 object without mutating the library.

```sh
npx skills add https://github.com/rikuws/mood. --skill mood-distill -g
```

## Share from iOS and X

1. Build, sign, and install the **PinaxiOS** scheme; the **Save to mood.** Share Extension is embedded automatically.
2. Open mood. once and create any projects you want available in the share composer.
3. In X, tap the post's Share action, choose **Share via…**, then select **Save to mood.** If it is hidden, choose **More** and enable it.
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

# mood-distill helper lookup
bash skills/mood-distill/tests/find-mood-agent.test.sh
```

## Repository map

```text
Shared/                 Local models, canonical URL dedupe, coordinated JSON repository
AgentAPI/               Bundled read-only JSON command API for agent skills
skills/                 Portable Agent Skills (mood-distill)
Sync/                   CloudKit backend, merge engine, tombstones, sync state and tests
Mac/                    Native macOS library UI and Chromium installer
iOS/                    Native iOS library UI
ShareExtension/         iOS share composer and item extraction
BrowserExtension/       Manifest V3 Chromium extension
NativeHost/             Native messaging executable and protocol tests
Documentation/          Architecture notes
project.yml             XcodeGen source of truth
```
