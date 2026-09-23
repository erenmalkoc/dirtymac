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
        // Full lockdown freezes the mouse too, so it keeps its explicit
        // in-popover confirmation; a missing permission needs the popover's
        // prompt. Both fall back to just opening the panel.
        if blocker.isActive {
            return .result()
        } else if !blocker.hasPermission || LockConfiguration.current.blockMouseAndTrackpad {
            app.showPopoverWhenReady()
        } else {
            blocker.start()
        }
        return .result()
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
