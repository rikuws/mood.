# mood. Chromium extension

The mood. extension saves the current web page from its toolbar button and adds a dedicated mood. control to every post on X. Clicking X's own **Bookmark** control also saves that post to mood.; clicking **Remove bookmark** never does.

It is a source-only Manifest V3 extension with no remote code, analytics, or network backend. Captures travel directly from the extension service worker to the installed mood. macOS app through Chromium native messaging.

## Supported browsers

The same unpacked build works in current Chromium-based browsers:

- Google Chrome
- Brave
- Microsoft Edge
- Arc
- Vivaldi

The mood. app's installer must register the compatibility-preserved `com.pinax.native_host` identity in each installed browser's vendor-specific `NativeMessagingHosts` directory. The extension has a fixed development identity:

```text
ohhhjpbfjecipcnkahlhaggckmdjfndg
```

The native host manifest must therefore contain:

```json
{
  "name": "com.pinax.native_host",
  "allowed_origins": [
    "chrome-extension://ohhhjpbfjecipcnkahlhaggckmdjfndg/"
  ]
}
```

`manifest.json` contains the matching public key. Keep that key stable: changing it changes the unpacked extension ID and breaks native-host authorization. A Chrome Web Store release should use the store-issued key/ID and add its origin to the native host installer if it differs.

## Build and load

Node 20 or newer is sufficient; there are no third-party packages.

```sh
cd BrowserExtension
npm test
npm run build
```

The build validates the manifest, permissions, JavaScript syntax, and fixed key, then copies only runtime files to `BrowserExtension/dist`.

Open the browser's extensions page, enable developer mode, choose **Load unpacked**, and select `BrowserExtension/dist`:

- Chrome/Brave/Arc/Vivaldi: `chrome://extensions`
- Edge: `edge://extensions`

Open the mood. macOS app once so it can install the native messaging host. Pin the extension if you want one-click capture from any HTTP(S) page.

## Capture behavior

The toolbar action temporarily receives access only to the active tab through `activeTab`. It prefers canonical and Open Graph metadata, selected text, and a useful preview image, then sends one capture to the native host.

On `x.com` and legacy `twitter.com`, a narrowly scoped content script:

1. observes X's recycled post DOM and SPA navigation;
2. adds a mood. button beside the native post actions;
3. captures the post synchronously when the button is used;
4. observes clicks on `[data-testid="bookmark"]` but deliberately ignores `[data-testid="removeBookmark"]`;
5. extracts the canonical `https://x.com/<handle>/status/<id>` URL, post text, author, handle, and first post image/video preview.

Both the content script and service worker coalesce rapid repeat captures. X gets an in-page status toast and button state; toolbar captures get an in-page toast plus a short action badge. “Saved to mood.” appears only after the Mac app acknowledges its repository commit; native-host connection, dispatch, save, and confirmation failures produce an actionable error instead of silently dropping the capture.

## Native message protocol

Messages use Chromium's native messaging framing: one UTF-8 JSON object prefixed with its 32-bit native-endian byte length. The extension opens one `sendNativeMessage` process per non-coalesced capture.

Request from the extension:

```json
{
  "protocolVersion": 1,
  "type": "capture",
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "capturedAt": "2026-07-21T19:15:00.000Z",
  "item": {
    "source": "x",
    "url": "https://x.com/designer/status/123456789",
    "title": "@designer: A compact description of the post",
    "text": "A compact description of the post",
    "authorName": "A Designer",
    "authorHandle": "designer",
    "imageURL": "https://pbs.twimg.com/media/example.jpg"
  },
  "context": {
    "trigger": "x_bookmark",
    "browser": "chromium-extension",
    "extensionVersion": "0.1.0"
  }
}
```

Required request fields are `protocolVersion`, `type`, `requestId`, `capturedAt`, `item.source`, `item.url`, `item.title`, `item.text`, `context.trigger`, `context.browser`, and `context.extensionVersion`. `authorName`, `authorHandle`, and `imageURL` are omitted when unavailable. Trigger is one of `toolbar`, `pinax_button`, or `x_bookmark`; source is `x` or `web`.

Accepted host response:

```json
{
  "ok": true,
  "itemId": "018fa4c2-42f0-7c9f-9a9e-e24b052f9380",
  "duplicate": false
}
```

The helper returns `ok` only after the app atomically writes a matching request-ID acknowledgement following the repository commit. `itemId` identifies the persisted inspiration and `duplicate` distinguishes a refreshed existing item from a new insert.

Rejected host response:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_capture",
    "message": "This post could not be saved."
  }
}
```

The host must always emit exactly one response object before exiting. User-safe host error messages are shown verbatim in X and on toolbar captures.

## Permissions

- `activeTab`: temporary access after an explicit toolbar click, instead of persistent access to every site.
- `scripting`: injects the page extractor and status feedback into that active tab.
- `nativeMessaging`: sends the capture to the local mood. app.
- Static content-script matches are limited to `https://x.com/*` and `https://twitter.com/*` so X integration can survive SPA navigation.

There is intentionally no `tabs`, `storage`, `<all_urls>`, cookies, web request, clipboard, or remote-code permission.

Implementation references: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [the `activeTab` permission](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab), and [the Manifest V3 scripting API](https://developer.chrome.com/docs/extensions/reference/api/scripting).
