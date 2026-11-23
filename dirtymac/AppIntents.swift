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

    /// Optional. Without it the lock uses the timer from Settings, as
    /// before. The range is the same one IntentLockPlan clamps to.
    @Parameter(
        title: "Minutes",
        description: "How long to lock, from 1 to 60. Leave it empty to use the timer from Settings.",
        inclusiveRange: (1, 60)
    )
    var minutes: Int?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.shared else { return .result() }
        Self.run(
            minutes: minutes,
            blocker: app.blocker,
            storedConfiguration: LockConfiguration.current,
            openPanel: { app.showPopoverWhenReady() }
        )
        return .result()
    }

    /// The whole action, apart from where its inputs come from, so it can
    /// be run against a fake blocker.
    @MainActor
    static func run(
        minutes: Int?,
        blocker: KeyboardBlocker,
        storedConfiguration: LockConfiguration,
        openPanel: () -> Void
    ) {
        blocker.refreshPermission()
        blocker.refreshSecureInput()
        switch IntentLockPlan.plan(
            minutes: minutes,
            isActive: blocker.isActive,
            hasPermission: blocker.hasPermission,
            secureInputOn: blocker.secureInput != nil,
            storedConfiguration: storedConfiguration
        ) {
        case .alreadyLocked:
            break
        case .openPanel:
            openPanel()
        case .lock(let configuration):
            blocker.beginLock(configuration ?? storedConfiguration)
        }
    }
}

/// What the action does with its optional length.
enum IntentLockPlan: Equatable {
    case alreadyLocked
    case openPanel
    /// Lock now. nil means "with the stored settings", as the action always
    /// did, a configuration means "for the length that was asked for".
    case lock(LockConfiguration?)

    /// The lengths the action accepts, in minutes. Shortcuts can pass any
    /// number from a variable, so anything else is pulled into this range.
    static let minMinutes = 1
    static let maxMinutes = 60

    static func seconds(forMinutes minutes: Int) -> Int {
        min(max(minutes, minMinutes), maxMinutes) * 60
    }

    /// The same gates as before decide whether to lock at all (a frozen
    /// mouse, a missing permission and secure input all go to the panel).
    /// A length only changes what a lock that was going to start does.
    static func plan(
        minutes: Int?,
        isActive: Bool,
        hasPermission: Bool,
        secureInputOn: Bool,
        storedConfiguration: LockConfiguration
    ) -> IntentLockPlan {
        switch IntentLockDecision.decide(
            isActive: isActive,
            hasPermission: hasPermission,
            mouseLocked: storedConfiguration.effective.blockMouseAndTrackpad,
            secureInputOn: secureInputOn
        ) {
        case .alreadyLocked:
            return .alreadyLocked
        case .openPanel:
            return .openPanel
        case .lock:
            guard let minutes else { return .lock(nil) }
            return .lock(QuickLock.configuration(
                seconds: seconds(forMinutes: minutes),
                storedConfiguration: storedConfiguration
            ))
        }
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
