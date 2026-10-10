import Foundation
import Combine
import AppKit

// What the tap blocks and how it treats each event lives in LockCore.swift;
// the tap, the permission check and the timers in LockPlatform.swift.

/// Why a lock ended.
enum UnlockReason: Equatable {
    /// The power button in the panel.
    case clicked
    /// The hold-Esc emergency exit.
    case escHeld
    /// The auto-unlock timer.
    case autoUnlock
    /// The app is quitting.
    case quit
    /// The Mac went to sleep.
    case systemSleep
    /// The screen was locked.
    case screenLocked
    /// Another user took over the screen (fast user switching).
    case userSwitched
    /// System Settings came forward during the lock.
    case systemSettings
    /// The Accessibility permission was taken away during the lock.
    case permissionRevoked
}

@MainActor
final class KeyboardBlocker: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var hasPermission: Bool = false
    /// Configured auto-unlock duration for the active session (0 = none).
    @Published private(set) var autoUnlockTotal: Int = 0
    /// Why the most recent lock ended; nil while locked and before the
    /// first lock.
    @Published private(set) var lastUnlockReason: UnlockReason?

    /// How long Esc has to be held to force an unlock.
    static let escHoldDuration: TimeInterval = 3.0
    /// Once the hold is complete the lock waits for Esc to come up, at
    /// most this long, so the rest of the press can't auto-repeat into
    /// the frontmost app (leaving full screen, cancelling a dialog).
    static let escReleaseGrace: TimeInterval = 1.5

    private let tap: EventTapping
    private let permission: AccessibilityPermission
    private let scheduler: LockScheduling

    private var startedAt: TimeInterval?
    private var ticker: LockTimer?
    private var autoUnlockTimer: LockTimer?
    private var escHoldTimer: LockTimer?
    /// Set once Esc has been held long enough; the unlock finishes when
    /// Esc comes up or when this fires.
    private var escReleaseTimer: LockTimer?

    init(
        tap: EventTapping = SessionEventTap(),
        permission: AccessibilityPermission = SystemAccessibility(),
        scheduler: LockScheduling = RunLoopScheduler()
    ) {
        self.tap = tap
        self.permission = permission
        self.scheduler = scheduler
        refreshPermission()
    }

    // MARK: Permission

    func refreshPermission() {
        hasPermission = permission.isTrusted
    }

    func requestPermission() {
        hasPermission = permission.requestAccess()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Lock

    /// Locks with `configuration`, the stored settings by default.
    /// Returns false when no lock started: the app has no Accessibility
    /// permission (the system prompt is shown) or macOS refused the tap.
    @discardableResult
    func start(_ configuration: LockConfiguration = .current) -> Bool {
        guard !isActive else { return true }

        refreshPermission()
        guard hasPermission else {
            requestPermission()
            return false
        }

        // Applied here as well, so no caller can skip the safety rules
        // (such as the mandatory timer while the mouse is locked).
        let config = configuration.effective
        let installed = tap.install(mask: EventMask.build(for: config)) { [weak self] decision in
            self?.handleEsc(decision)
        }
        guard installed else {
            // Tap creation failed — likely permission revoked between checks.
            hasPermission = false
            return false
        }

        startedAt = scheduler.now
        elapsed = 0
        autoUnlockTotal = config.autoUnlockSeconds
        lastUnlockReason = nil
        isActive = true

        ticker = scheduler.schedule(after: 1, repeats: true) { [weak self] in
            self?.tick()
        }
        if autoUnlockTotal > 0 {
            autoUnlockTimer = scheduler.schedule(
                after: TimeInterval(autoUnlockTotal),
                repeats: false
            ) { [weak self] in
                self?.stop(reason: .autoUnlock)
            }
        }
        return true
    }

    func stop(reason: UnlockReason) {
        guard isActive else { return }
        tap.uninstall()
        ticker?.cancel()
        ticker = nil
        autoUnlockTimer?.cancel()
        autoUnlockTimer = nil
        escHoldTimer?.cancel()
        escHoldTimer = nil
        escReleaseTimer?.cancel()
        escReleaseTimer = nil
        startedAt = nil
        elapsed = 0
        autoUnlockTotal = 0
        lastUnlockReason = reason
        isActive = false
    }

    private func tick() {
        guard let startedAt else { return }
        // A tap left running without the permission can hang all input
        // on some macOS versions; let go as soon as it disappears.
        guard permission.isTrusted else {
            hasPermission = false
            stop(reason: .permissionRevoked)
            return
        }
        elapsed = scheduler.now - startedAt
        // The deadline timer can fire late, e.g. right after the Mac
        // wakes. The clock decides, so the countdown can't sit at 00:00
        // while the lock keeps running.
        if autoUnlockTotal > 0, elapsed >= TimeInterval(autoUnlockTotal) {
            stop(reason: .autoUnlock)
        }
    }

    // MARK: Hold-Escape emergency exit

    private func handleEsc(_ decision: TapEventDecision) {
        switch decision {
        case .escDown: escHoldBegan()
        case .escUp: escHoldEnded()
        default: break
        }
    }

    private func escHoldBegan() {
        // Auto-repeat neither restarts a hold nor re-arms a finished one.
        guard isActive, escHoldTimer == nil, escReleaseTimer == nil else { return }
        escHoldTimer = scheduler.schedule(after: Self.escHoldDuration, repeats: false) { [weak self] in
            self?.escHoldCompleted()
        }
    }

    private func escHoldCompleted() {
        escHoldTimer = nil
        guard isActive else { return }
        // Keep swallowing Esc until it comes up; never wait longer than
        // the grace period, so a lost key-up can't keep the lock on.
        escReleaseTimer = scheduler.schedule(after: Self.escReleaseGrace, repeats: false) { [weak self] in
            self?.stop(reason: .escHeld)
        }
    }

    private func escHoldEnded() {
        if escReleaseTimer != nil {
            // This key-up is still inside the tap's callback; tear the
            // tap down on the next run-loop pass, not from within it.
            escReleaseTimer?.cancel()
            escReleaseTimer = scheduler.schedule(after: 0, repeats: false) { [weak self] in
                self?.stop(reason: .escHeld)
            }
            return
        }
        escHoldTimer?.cancel()
        escHoldTimer = nil
    }

    // MARK: Display helpers

    var elapsedDisplay: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var hasAutoUnlock: Bool { autoUnlockTotal > 0 }

    /// Seconds left before the auto-unlock fires (0 if no timer).
    var autoUnlockRemaining: Int {
        guard autoUnlockTotal > 0 else { return 0 }
        return max(0, autoUnlockTotal - Int(elapsed))
    }

    var autoUnlockRemainingDisplay: String {
        let r = autoUnlockRemaining
        return String(format: "%02d:%02d", r / 60, r % 60)
    }
}
