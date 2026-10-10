import AppKit

/// Ends a running lock when the session around it changes: the Mac goes
/// to sleep, the screen locks, another user takes over, or System
/// Settings comes forward. A lock must never outlive the moment the user
/// stepped away or needs to type a password, and Accessibility must not
/// be switched off under a live tap: on macOS 15 and 26 that can hang
/// all input until a restart.
final class SessionWatcher {
    /// Posted (distributed) when the login window locks the screen.
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let systemSettingsBundleID = "com.apple.systempreferences"

    /// The unlock reason a notification stands for, if any.
    static func reason(for name: Notification.Name, activatedBundleID: String? = nil) -> UnlockReason? {
        switch name {
        case NSWorkspace.willSleepNotification:
            return .systemSleep
        case screenLockedNotification:
            return .screenLocked
        case NSWorkspace.sessionDidResignActiveNotification:
            return .userSwitched
        case NSWorkspace.didActivateApplicationNotification:
            return activatedBundleID == systemSettingsBundleID ? .systemSettings : nil
        default:
            return nil
        }
    }

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private let onSessionChange: (UnlockReason) -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// `onSessionChange` runs on the main thread for every relevant
    /// notification, whether or not a lock is running.
    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
        onSessionChange: @escaping (UnlockReason) -> Void
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.onSessionChange = onSessionChange
    }

    func start() {
        guard observers.isEmpty else { return }
        observe(NSWorkspace.willSleepNotification, on: workspaceCenter)
        observe(NSWorkspace.sessionDidResignActiveNotification, on: workspaceCenter)
        observe(NSWorkspace.didActivateApplicationNotification, on: workspaceCenter)
        observe(Self.screenLockedNotification, on: distributedCenter)
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let self,
                      let reason = Self.reason(for: note.name, activatedBundleID: app?.bundleIdentifier)
                else { return }
                self.onSessionChange(reason)
            }
        }
        observers.append((center, token))
    }
}
