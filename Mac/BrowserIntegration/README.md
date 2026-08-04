# Pinax browser integration

`BrowserIntegrationInstaller` manages the per-user Chromium native-messaging manifests for
Pinax. It always points at the helper bundled at:

```text
Pinax.app/Contents/Helpers/PinaxNativeHost
```

The fixed native host is `com.pinax.native_host`. The only allowed extension origin is:

```text
chrome-extension://ohhhjpbfjecipcnkahlhaggckmdjfndg/
```

That ID is derived from the public `key` in the Chromium extension manifest. Changing the
extension key requires changing `PinaxBrowserIntegrationConfiguration.chromiumExtensionID`
at the same time.

## App integration

Add the Swift files in `Sources/BrowserIntegration` to the macOS app target, or depend on this
directory as a local Swift package. Once the helper exists and is executable in the final app
bundle, installation is straightforward:

```swift
let installer = BrowserIntegrationInstaller()

let statuses = installer.statuses()
try installer.install(for: .chrome)
try installer.update(for: .brave) // Also installs when absent.
try installer.remove(for: .vivaldi)
```

`status(for:)` returns both a manifest state (`notInstalled`, `installed`,
`updateRequired`, `conflict`, or `unreadable`) and helper state (`available`, `missing`, or
`notExecutable`). `isOperational` is true only when both pieces are ready. Calling `install`
again is safe, and calling it after the app moves updates the absolute helper path.

If a manifest at Pinax's expected filename declares another host or cannot be decoded, the
installer refuses to overwrite or remove it. Pinax-owned writes use `Data.write(.atomic)` and
are decoded again after the write before success is returned.

## User-level manifest locations

| Browser | Directory below the user's home folder |
| --- | --- |
| Google Chrome | `Library/Application Support/Google/Chrome/NativeMessagingHosts` |
| Chromium | `Library/Application Support/Chromium/NativeMessagingHosts` |
| Brave | `Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts` |
| Microsoft Edge | `Library/Application Support/Microsoft Edge/NativeMessagingHosts` |
| Arc | `Library/Application Support/Arc/User Data/NativeMessagingHosts` |
| Vivaldi | `Library/Application Support/Vivaldi/NativeMessagingHosts` |

Each directory receives only `com.pinax.native_host.json`. Chrome documents the Chrome and
Chromium user paths and the absolute executable-path requirement in its
[native messaging guide](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging). Microsoft documents the stable Edge path in its
[native messaging guide](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/native-messaging).

These are direct-distribution integration paths. A Mac App Sandbox container cannot normally
write arbitrary browser Application Support directories; an App Store/sandboxed build needs a
separate approved installation design. The direct Pinax build should remain unsandboxed for
this installer, while retaining hardened runtime and normal code signing/notarization.

## Tests

```sh
cd Mac/BrowserIntegration
swift test
```

The tests use temporary home/app directories and verify all six locations, manifest contents,
relocation updates, helper permissions, idempotency, removal, and preservation of unrelated or
unreadable files.
