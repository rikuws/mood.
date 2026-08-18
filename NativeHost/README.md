# mood. native messaging host

`PinaxNativeHost` is the compatibility-preserved stdio bridge between the mood. Chromium extension and the
native macOS app. It contains no persistence logic. It validates the web URL, creates a
percent-encoded `pinax://capture` URL, targets the containing `mood.app` bundle, and waits for a
request-correlated acknowledgement written after the app's repository transaction.

The implementation follows Chromium's [native messaging protocol](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging): a four-byte little-endian
payload length followed by UTF-8 JSON. Input and output are both limited to 1 MiB by mood.
The stricter input limit is intentional even though Chrome currently permits larger
browser-to-host messages.

## Browser protocol

The extension sends:

```json
{
  "protocolVersion": 1,
  "type": "capture",
  "requestId": "a-unique-request-id",
  "capturedAt": "2026-07-21T12:00:00Z",
  "item": {
    "source": "x",
    "url": "https://x.com/example/status/123",
    "title": "Optional title",
    "text": "Optional post or page text",
    "authorName": "Optional name",
    "authorHandle": "@optional_handle",
    "imageURL": "https://example.com/optional-image.jpg"
  },
  "context": {
    "trigger": "pinax_button",
    "browser": "chromium-extension"
  }
}
```

Unknown JSON keys are ignored and optional metadata may be absent. `protocolVersion`,
`type`, `item`, and `item.url` are required. The capture URL must be absolute HTTP or HTTPS.
An invalid optional image URL is omitted instead of rejecting the whole capture.

Success includes the committed library identity and duplicate state:

```json
{
  "ok": true,
  "itemId": "018fa4c2-42f0-7c9f-9a9e-e24b052f9380",
  "duplicate": false
}
```

Failures use this stable shape:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_url",
    "message": "Capture URLs must use HTTP or HTTPS."
  }
}
```

Current error codes include `invalid_request`, `invalid_request_id`, `unsupported_protocol`,
`unsupported_message`, `invalid_url`, `open_failed`, `confirmation_unavailable`,
`confirmation_timeout`, `capture_failed`, `message_too_large`, `response_too_large`,
`framing_error`, and `internal_error`.

The native app receives `pinax://capture` with these query items when present:

- `url`, `source`, `title`, `text`
- `authorName`, `authorHandle`, `imageURL`
- `capturedAt`, `trigger`, `browser`, `requestId`

`source` is normalized to `x` or `web`; missing or unknown values are inferred from the URL.

## Build and bundle

```sh
cd NativeHost
swift test
swift build -c release
```

Copy the release executable into the application at this exact relative path and retain its
executable bit:

```text
mood.app/Contents/Helpers/PinaxNativeHost
```

The nested executable must be code signed before the outer application is signed. In an
Xcode build, make the helper a dependency/copy-files product when possible; if it is built
by a script, copy it before the app's code-sign phase. Do not put diagnostic text on stdout,
because every stdout byte is part of native messaging. Diagnostics may go to stderr.

The app bundle must register the `pinax` URL scheme (`CFBundleURLTypes`), route
`pinax://capture` into the same repository path used by the share extension, and link
`PinaxNativeMessaging` so it can write the matching acknowledgement. After the helper is
in the final app bundle, call `BrowserIntegrationInstaller` so each manifest contains the
app's current absolute helper path.

## Tests

The Swift package tests cover little-endian framing, clean and partial EOF, input/output size
limits, tolerant metadata mapping, unsafe URL rejection, macOS-open failures, acknowledgement
round trips/timeouts, and structured responses. `CaptureURLOpening` keeps URL construction
and request handling testable without launching the GUI app.
