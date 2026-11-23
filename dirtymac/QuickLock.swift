import AppKit

/// What a one-click "lock for N minutes" does.
enum QuickLockDecision: Equatable {
    /// Already locked: nothing to start.
    case alreadyLocked
    /// Needs the panel: no Accessibility permission yet, or the stored
    /// settings freeze the mouse and so need the confirmation (and, above
    /// five minutes, the Esc check) that only the panel can ask for.
    case openPanel
    /// Lock now with this configuration.
    case lock(LockConfiguration)
}

/// Locking the keyboard for a chosen length with one click, from the menu
/// bar's right-click menu or from Shortcuts. The length replaces the
/// stored auto-unlock timer for this one lock, nothing else changes.
enum QuickLock {
    /// 1 min, 5 min, 15 min, 30 min, 1 hour: every one a keyboard-only
    /// lock, which the menu bar icon can always end with a click.
    static let durations = [60, 300, 900, 1800, 3600]

    /// Offered only while the stored settings leave the mouse free. A
    /// frozen mouse goes through the panel's confirmation instead.
    static func isOffered(storedConfiguration: LockConfiguration) -> Bool {
        !storedConfiguration.effective.blockMouseAndTrackpad
    }

    static func decide(
        seconds: Int,
        isActive: Bool,
        hasPermission: Bool,
        storedConfiguration: LockConfiguration
    ) -> QuickLockDecision {
        if isActive { return .alreadyLocked }
        if !hasPermission || !isOffered(storedConfiguration: storedConfiguration) { return .openPanel }
        return .lock(configuration(seconds: seconds, storedConfiguration: storedConfiguration))
    }

    /// The stored settings with the timer replaced. Basic mode, which has
    /// no timer, becomes its own keyboard-only block set with one.
    static func configuration(seconds: Int, storedConfiguration: LockConfiguration) -> LockConfiguration {
        var configuration = storedConfiguration.effective
        configuration.mode = .advanced
        configuration.autoUnlockSeconds = seconds
        return configuration.effective
    }
}

/// Runs quick locks for the menu and builds the menu item.
@MainActor
final class QuickLockController: NSObject {
    private let blocker: KeyboardBlocker
    private let storedConfiguration: () -> LockConfiguration
    private let openPanel: () -> Void

    init(
        blocker: KeyboardBlocker,
        storedConfiguration: @escaping () -> LockConfiguration = { .current },
        openPanel: @escaping () -> Void
    ) {
        self.blocker = blocker
        self.storedConfiguration = storedConfiguration
        self.openPanel = openPanel
    }

    func run(seconds: Int) {
        blocker.refreshPermission()
        switch QuickLock.decide(
            seconds: seconds,
            isActive: blocker.isActive,
            hasPermission: blocker.hasPermission,
            storedConfiguration: storedConfiguration()
        ) {
        case .alreadyLocked:
            break
        case .openPanel:
            openPanel()
        case .lock(let configuration):
            blocker.beginLock(configuration)
        }
    }

    @objc func lockFromMenu(_ sender: NSMenuItem) {
        run(seconds: sender.tag)
    }

    /// "Lock for ▸ 1 min, 5 min …", or nil when it should not be offered:
    /// a lock is running, or the stored settings freeze the mouse.
    func makeMenuItem(title: String, locale: Locale) -> NSMenuItem? {
        guard !blocker.isActive, QuickLock.isOffered(storedConfiguration: storedConfiguration()) else { return nil }
        let submenu = NSMenu(title: title)
        for seconds in QuickLock.durations {
            let item = NSMenuItem(
                title: LockConfiguration.unlockChoiceTitle(seconds, locale: locale),
                action: #selector(lockFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = seconds
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }
}
