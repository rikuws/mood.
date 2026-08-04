# Pinax architecture

Pinax is a local-first moodbook with several capture surfaces, one coordinated library format, and an optional private CloudKit replica.

## System overview

```text
Chromium toolbar / X Pinax action / confirmed X Bookmark
                         |
                         v
        Chromium native messaging (framed JSON on stdio)
                         |
                         v
               PinaxNativeHost helper
                         |  validated pinax://capture URL
                         v
                    Pinax for Mac --------+
                         |                 |
                         |                 v
                         |       private CloudKit database
                         |       custom zone: PinaxLibrary
                         |                 ^
                         v                 |
             coordinated local library ---+
             library.json + Media/
                         ^  ^
                         |  |
                         |  +--- pinax-agent (read-only JSON API)
                         |
              shared App Group container
                         |
            +------------+-------------+
            |                          |
      Pinax for iOS          Save to Pinax extension
                                      ^
                                      |
                         X / Safari / any iOS share
```

The Mac native host never edits the library. It validates the extension payload and opens a narrow app URL against the Pinax app bundle that contains the helper, leaving canonicalization, deduplication, and persistence to the app. A request-ID-correlated acknowledgement file is written atomically only after that repository transaction. The host consumes it and returns the real item ID and duplicate state; dispatch, save, and timeout failures return structured errors instead of optimistic success.

The iOS Share Extension writes directly to the same App Group library because a share extension cannot depend on launching its containing app. It saves locally before attempting a three-second best-effort CloudKit sync.

The macOS app also bundles `Contents/Helpers/pinax-agent` for local agent integrations. It
is a read-only, versioned JSON command API that discovers projects and fetches a selected
project's inspirations. The helper reads through `LibraryRepository`, including coordinated
file access and safe local-media path resolution; it does not require the app process to be
running and does not expose a network listener. See [AGENT_API.md](AGENT_API.md) for its
contract.

## Local storage

Production targets use the App Group:

```text
group.com.rikuwikman.pinax
```

The library consists of a versioned `library.json`, a `Media/` directory for captured local images, and a small CloudKit sync-state file. The JSON snapshot contains projects, inspirations, stable UUIDs and timestamps, capture metadata, and canonical URLs. Browser captures normally retain remote preview URLs. The iOS share extension resolves public X Open Graph metadata and copies its bounded preview image into `Media/`; app launch also repairs older URL-only X saves without counting them as new captures or overwriting user edits.

`LibraryRepository` is an actor for in-process serialization. It wraps each cross-process read/modify/write transaction in `NSFileCoordinator` and atomically replaces the JSON file, so the app and Share Extension do not expose a partially written snapshot. Cloud merges perform their final read/merge/write inside the same coordinated transaction so a capture made during a network fetch is retained.

Canonical URL deduplication treats equivalent web URLs as one item, including X/Twitter status variants. Repeated automatic browser capture refreshes missing metadata without removing an item from its curated project. An explicit General/project selection in a manual or share capture can reassign the duplicate, and non-empty title/note metadata entered by the user replaces the old values.

On macOS only, an unsigned development build falls back to `~/Library/Application Support/Pinax` rather than trying to use an App Group it is not entitled to. It also skips CloudKit initialization. iOS does not fall back: app and Share Extension storage must fail visibly rather than silently diverge.

## CloudKit sync

All signed targets use:

```text
iCloud.com.rikuwikman.Pinax
```

`CloudKitSyncBackend` mirrors the local logical snapshot into the signed-in user's private database and lazily creates the custom record zone `PinaxLibrary`. The UI always reads the local repository; CloudKit availability never gates a capture.

Sync behavior includes:

- stable UUID-based project and inspiration records;
- deterministic last-writer-wins merging using `updatedAt` and an encoded-value tie break;
- timestamped tombstones so deletions survive offline replicas;
- canonical-URL deduplication across devices;
- repair of inspirations whose project was deleted;
- optional `CKAsset` transfer for local images no larger than 45 MB;
- a single refetch-and-merge retry for server-record conflicts.

Apps sync on activation and after local mutations, then reload the coordinated local snapshot. Pull to refresh invokes the same path on iOS. The Share Extension only makes a bounded upload attempt after its local commit; an app activation performs the full retry later.

The merge engine and an in-memory backend are covered by deterministic tests. Live private-database behavior still requires all targets to be signed with a real Apple Developer team, the App Group and CloudKit container to exist in that team, and a device or Mac signed into iCloud. No live CloudKit verification is implied by an unsigned build or the unit-test suite.

## Chromium boundary

Native host name:

```text
com.pinax.native_host
```

Allowed unpacked extension origin:

```text
chrome-extension://ohhhjpbfjecipcnkahlhaggckmdjfndg/
```

Requests use Chromium's native-messaging framing: a four-byte little-endian length followed by UTF-8 JSON. Version 1 sends an HTTP(S) item URL, source, metadata, request context, and capture trigger. The host rejects unsafe or oversized input, percent-encodes accepted fields into `pinax://capture`, emits exactly one JSON response, and writes no diagnostic text to stdout.

The helper targets its containing `Pinax.app` explicitly, so another registered build cannot receive the capture by accident. It requests a non-activating open; a cold browser capture can launch Pinax without opening its moodbook window, while a later Dock click or normal launch opens the native library as usual. The helper waits up to nine seconds for the app's repository acknowledgement, within the extension's fifteen-second native-response deadline.

The Mac build bundles the helper at `Contents/Helpers/PinaxNativeHost` and the built extension at `Contents/Resources/BrowserExtension`. Browser Setup writes a per-user native-host manifest for Chrome, Chromium, Brave, Edge, Arc, and Vivaldi. Each manifest contains the helper's absolute path and only the fixed allowed origin. Existing unrelated or unreadable manifests are not overwritten.

On X, the content script observes the recycled SPA timeline, adds its action beside each post, and extracts the canonical status URL and available metadata. For X's Bookmark action, it snapshots the post on the click and sends only after that same post changes to X's bookmarked state; Remove bookmark is ignored. Rapid repeated captures are coalesced.

Because the installer writes into browser Application Support directories, the Mac app is designed for direct distribution rather than a Mac App Store sandbox. Moving the app requires reinstalling its manifests so their absolute helper paths remain valid.

## iOS extension boundary

The Share Extension accepts one web URL or web page, text containing an HTTP(S) URL, and an optional image. Every provider callback is time-bounded; text is capped and optional image data is limited to 20 MB, so a stalled or oversized source app cannot strand the composer or exhaust its extension budget before the URL is saved. For an X URL, it also makes a bounded best-effort desktop-web metadata request, rejects X's generic fallback artwork, and persists the resulting title, post text, author, remote image URL, and local image bytes when available.

The composer lets the user edit the title and note and choose General or a project. Saving completes only after the App Group repository confirms its local transaction. CloudKit upload failure does not turn a confirmed local save into an error.

X does not expose a supported API for injecting Pinax into its native iOS post-action row. Pinax therefore uses the system path: **Share** -> **Share via…** -> **Save to Pinax**.

## Provisioning boundary

`project.yml` declares the App Group and CloudKit entitlements for PinaxMac, PinaxiOS, PinaxShareExtension, and the read-only PinaxAgent helper. That source configuration cannot create Apple Developer resources, certificates, or provisioning profiles. Before device or live-sync verification, the selected team must own and provision:

```text
group.com.rikuwikman.pinax
iCloud.com.rikuwikman.Pinax
com.rikuwikman.Pinax
com.rikuwikman.Pinax.ShareExtension
com.rikuwikman.Pinax.AgentAPI
```

Use `xcodegen generate` after project configuration changes. For distribution, sign the nested native host and agent helper before the outer Mac app and deploy the CloudKit schema to the production environment as appropriate for the release channel.
