import Foundation

/// Constants shared with the packaged Chromium extension and native-messaging helper.
public enum PinaxBrowserIntegrationConfiguration {
    public static let nativeHostName = "com.pinax.native_host"
    public static let nativeHostManifestFileName = "\(nativeHostName).json"

    /// Derived from the public key checked into the Chromium extension manifest.
    public static let chromiumExtensionID = "ohhhjpbfjecipcnkahlhaggckmdjfndg"
    public static let chromiumExtensionOrigin = "chrome-extension://\(chromiumExtensionID)/"

    public static let helperBundleRelativePath = "Contents/Helpers/PinaxNativeHost"
}
