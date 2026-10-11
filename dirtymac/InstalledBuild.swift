import Foundation

/// Notices when an update replaced this app on disk while it kept
/// running — Homebrew before 1.3.0 did not quit it first, and a copy
/// can be dragged over a running one. Such a process no longer passes
/// macOS's code-signature checks, so its Accessibility access looks lost
/// and opening the app again only brings this stale copy forward. The
/// cure is to restart into the new version.
enum InstalledBuild {
    /// CFBundleVersion of the bundle at `bundleURL` as it is on disk now.
    static func onDisk(bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = plist as? [String: Any]
        else { return nil }
        return info["CFBundleVersion"] as? String
    }

    /// A missing or unreadable bundle (an uninstall in progress) is not
    /// a replacement: restarting would find nothing to open.
    static func wasReplaced(running: String?, onDisk: String?) -> Bool {
        guard let running, let onDisk else { return false }
        return running != onDisk
    }

    /// Whether the running copy of this app is stale.
    static var currentWasReplaced: Bool {
        wasReplaced(
            running: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            onDisk: onDisk(bundleURL: Bundle.main.bundleURL)
        )
    }
}
