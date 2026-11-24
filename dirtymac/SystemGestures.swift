import Foundation

/// Turns the trackpad's system gestures off while the keyboard is locked.
///
/// Three and four finger swipes (Mission Control, Spaces, App Exposé),
/// the pinch gestures and the swipe in from the right edge are handled by
/// macOS out of reach of every event tap (the event log shows them never
/// arriving as events an app can stop), so a palm on the trackpad could
/// still change screens. The one lever an app has is the settings that
/// turn them off, the ones Trackpad in System Settings writes. They are
/// switched off for the length of the lock and put back exactly as they
/// were, also after a crash: the values are written down before anything is
/// changed, and the next launch puts them back if the lock never got to.
protocol GestureSuppressing: AnyObject {
    /// Writes the current values down, then turns the gestures off.
    func suppress()
    /// Puts the written-down values back. Safe when nothing is suppressed.
    func restore()
}

/// One setting that switches a gesture on or off.
nonisolated struct GestureSetting: Equatable {
    let domain: String
    let key: String
    /// A boolean (`true` = on) or a number (0 = off).
    let isBoolean: Bool

    /// The value that turns the gesture off.
    var offValue: Any { isBoolean ? false : 0 }

    static let trackpadDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]
    static let trackpadKeys = [
        "TrackpadThreeFingerHorizSwipeGesture",
        "TrackpadThreeFingerVertSwipeGesture",
        "TrackpadFourFingerHorizSwipeGesture",
        "TrackpadFourFingerVertSwipeGesture",
        "TrackpadFourFingerPinchGesture",
        "TrackpadFiveFingerPinchGesture",
        "TrackpadTwoFingerFromRightEdgeSwipeGesture",
    ]
    static let dockKeys = [
        "showMissionControlGestureEnabled",
        "showAppExposeGestureEnabled",
        "showDesktopGestureEnabled",
        "showLaunchpadGestureEnabled",
    ]

    /// Every setting that is turned off: the trackpad's own for the built-in
    /// and the Bluetooth trackpad, and the Dock's.
    static let all: [GestureSetting] =
        trackpadDomains.flatMap { domain in
            trackpadKeys.map { GestureSetting(domain: domain, key: $0, isBoolean: false) }
        }
        + dockKeys.map { GestureSetting(domain: "com.apple.dock", key: $0, isBoolean: true) }
}

/// Reads and writes other apps' preferences.
protocol GesturePreferences: AnyObject {
    func value(for setting: GestureSetting) -> Any?
    /// `nil` removes the setting.
    func set(_ value: Any?, for setting: GestureSetting)
}

/// Makes the Dock read its settings again, which it only does when it starts.
protocol DockRestarting: AnyObject {
    func restart()
}

final class SystemGesturePreferences: GesturePreferences {
    func value(for setting: GestureSetting) -> Any? {
        CFPreferencesCopyValue(
            setting.key as CFString, setting.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
    }

    func set(_ value: Any?, for setting: GestureSetting) {
        CFPreferencesSetValue(
            setting.key as CFString, value as CFPropertyList?, setting.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(setting.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

final class SystemDockRestart: DockRestarting {
    func restart() {
        // Not waited for: the Dock is back in a moment, and a lock must
        // not stall on it.
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
    }
}

final class GestureSuppressor: GestureSuppressing {
    /// Where the values are written down, in dirtymac's own preferences.
    static let savedKey = "savedSystemGestureSettings"

    private let preferences: GesturePreferences
    private let dock: DockRestarting
    private let defaults: UserDefaults
    private let settings: [GestureSetting]

    init(
        preferences: GesturePreferences = SystemGesturePreferences(),
        dock: DockRestarting = SystemDockRestart(),
        defaults: UserDefaults = .standard,
        settings: [GestureSetting] = GestureSetting.all
    ) {
        self.preferences = preferences
        self.dock = dock
        self.defaults = defaults
        self.settings = settings
    }

    /// Whether values are written down and not yet put back.
    var isSuppressed: Bool { defaults.array(forKey: Self.savedKey) != nil }

    func suppress() {
        // A second call must not write the zeros down as the originals.
        guard !isSuppressed else { return }
        let saved: [[String: Any]] = settings.map { setting in
            var entry: [String: Any] = ["domain": setting.domain, "key": setting.key, "boolean": setting.isBoolean]
            if let value = preferences.value(for: setting) { entry["value"] = value }
            return entry
        }
        // First on disk, then changed: a crash in between loses nothing.
        defaults.set(saved, forKey: Self.savedKey)
        defaults.synchronize()
        for setting in settings {
            preferences.set(setting.offValue, for: setting)
        }
        dock.restart()
    }

    func restore() {
        guard let saved = defaults.array(forKey: Self.savedKey) as? [[String: Any]] else { return }
        for entry in saved {
            guard let domain = entry["domain"] as? String, let key = entry["key"] as? String else { continue }
            let setting = GestureSetting(domain: domain, key: key, isBoolean: entry["boolean"] as? Bool ?? false)
            preferences.set(entry["value"], for: setting)
        }
        defaults.removeObject(forKey: Self.savedKey)
        defaults.synchronize()
        dock.restart()
    }
}
