import Foundation

public enum ChromiumBrowser: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case chrome
    case chromium
    case brave
    case edge
    case arc
    case vivaldi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .chromium: "Chromium"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .arc: "Arc"
        case .vivaldi: "Vivaldi"
        }
    }

    /// User-level native messaging manifest directory, relative to the home directory.
    public var nativeMessagingHostDirectoryComponents: [String] {
        switch self {
        case .chrome:
            ["Library", "Application Support", "Google", "Chrome", "NativeMessagingHosts"]
        case .chromium:
            ["Library", "Application Support", "Chromium", "NativeMessagingHosts"]
        case .brave:
            ["Library", "Application Support", "BraveSoftware", "Brave-Browser", "NativeMessagingHosts"]
        case .edge:
            ["Library", "Application Support", "Microsoft Edge", "NativeMessagingHosts"]
        case .arc:
            ["Library", "Application Support", "Arc", "User Data", "NativeMessagingHosts"]
        case .vivaldi:
            ["Library", "Application Support", "Vivaldi", "NativeMessagingHosts"]
        }
    }
}
