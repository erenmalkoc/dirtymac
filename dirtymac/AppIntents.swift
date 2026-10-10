import AppIntents

// App Intents are the one entry point that works while dirtymac is not
// running at all: Spotlight, Siri and the Shortcuts app launch the app
// on demand and then run the intent. A Shortcut built from these can
// also be given its own system-wide keyboard shortcut in Shortcuts.

struct OpenDirtymacIntent: AppIntent {
    static let title: LocalizedStringResource = "Open dirtymac"
    static let description = IntentDescription("Opens the dirtymac menu bar panel.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.showPopoverWhenReady()
        return .result()
    }
}

struct LockKeyboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Keyboard for Cleaning"
    static let description = IntentDescription("Locks the keyboard so you can clean it. Hold Esc for 3 seconds to unlock.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.shared else { return .result() }
        let blocker = app.blocker
        blocker.refreshPermission()
        blocker.refreshSecureInput()
        switch IntentLockDecision.decide(
            isActive: blocker.isActive,
            hasPermission: blocker.hasPermission,
            mouseLocked: LockConfiguration.current.blockMouseAndTrackpad,
            secureInputOn: blocker.secureInput != nil
        ) {
        case .alreadyLocked:
            break
        case .openPanel:
            app.showPopoverWhenReady()
        case .lock:
            blocker.start()
        }
        return .result()
    }
}

/// What "Lock Keyboard for Cleaning" does when run from Spotlight or
/// Shortcuts, where nobody is looking at the panel yet.
enum IntentLockDecision: Equatable {
    case alreadyLocked
    case openPanel
    case lock

    /// Locks straight away only when nothing needs the user's eyes: full
    /// lockdown keeps its confirmation, a missing permission its prompt,
    /// and secure input its warning (keys would not be blocked).
    static func decide(isActive: Bool, hasPermission: Bool, mouseLocked: Bool, secureInputOn: Bool) -> IntentLockDecision {
        if isActive { return .alreadyLocked }
        if !hasPermission || mouseLocked || secureInputOn { return .openPanel }
        return .lock
    }
}

struct DirtymacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockKeyboardIntent(),
            phrases: [
                "Lock keyboard with \(.applicationName)",
                "Clean keyboard with \(.applicationName)",
            ],
            shortTitle: "Lock Keyboard",
            systemImageName: "keyboard"
        )
        AppShortcut(
            intent: OpenDirtymacIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open dirtymac",
            systemImageName: "menubar.rectangle"
        )
    }
}
