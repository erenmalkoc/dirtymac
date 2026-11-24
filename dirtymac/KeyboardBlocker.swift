import Foundation
import Combine
import AppKit

// What the tap blocks and how it treats each event lives in LockCore.swift;
// the tap, the permission check and the timers in LockPlatform.swift.

/// What the hold-Esc exit is doing, for the panel and the menu bar to show.
enum EscHoldState: Equatable {
    /// Esc is not being held.
    case idle
    /// Esc is held: whole seconds still to go (3, 2, 1) and 0...1 progress.
    case holding(remaining: Int, progress: Double)
    /// Held long enough: the unlock finishes when Esc comes up.
    case letGo

    /// The whole seconds shown while holding: 3 at the start, 1 for the
    /// last stretch, never 0 (0 is the "let go" state). `held` is how long
    /// Esc has been down.
    static func remainingSeconds(held: TimeInterval, total: TimeInterval) -> Int {
        let left = Int((total - held).rounded(.up))
        return min(Int(total.rounded(.up)), max(1, left))
    }
}

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
    /// Another app turned on secure input during a full lockdown.
    case secureInput
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
    /// Set while another app holds Secure Event Input, so keys get past
    /// the tap; nil otherwise. See SecureInput.swift.
    @Published private(set) var secureInput: SecureInputStatus?
    /// The hold-Esc exit as it runs: a countdown the panel and the menu
    /// bar show, so nobody has to count the three seconds themselves.
    @Published private(set) var escHold: EscHoldState = .idle
    /// Seconds left of the start delay while one is running; nil
    /// otherwise. Nothing is blocked yet during this wait.
    @Published private(set) var lockCountdown: Int?

    /// How long Esc has to be held to force an unlock.
    static let escHoldDuration: TimeInterval = 3.0
    /// Once the hold is complete the lock waits for Esc to come up, at
    /// most this long, so the rest of the press can't auto-repeat into
    /// the frontmost app (leaving full screen, cancelling a dialog).
    static let escReleaseGrace: TimeInterval = 1.5

    private let tap: EventTapping
    private let permission: AccessibilityPermission
    private let scheduler: LockScheduling
    private let secureInputDetector: SecureInputDetecting
    private let sounds: SoundPlaying
    private let displayWake: DisplayWakeHolding
    private let shield: PointerShielding
    private let gestures: GestureSuppressing

    private var startedAt: TimeInterval?
    private var ticker: LockTimer?
    private var autoUnlockTimer: LockTimer?
    private var escHoldTimer: LockTimer?
    /// Set once Esc has been held long enough; the unlock finishes when
    /// Esc comes up or when this fires.
    private var escReleaseTimer: LockTimer?
    /// The ticks heard while Esc is held.
    private var escTickTimers: [LockTimer] = []
    /// When the current Esc hold began, and the timer that refreshes the
    /// countdown while it runs.
    private var escHoldStartedAt: TimeInterval?
    private var escCountdownTimer: LockTimer?
    private var pendingLockTimer: LockTimer?
    /// How often the countdown refreshes while Esc is held.
    static let escCountdownInterval: TimeInterval = 0.1
    /// Whether the running lock includes the mouse and trackpad.
    private var mouseLocked = false
    /// Consecutive ticks with secure input on.
    private var secureInputReadings = 0

    init(
        tap: EventTapping = SessionEventTap(),
        permission: AccessibilityPermission = SystemAccessibility(),
        scheduler: LockScheduling = RunLoopScheduler(),
        secureInput: SecureInputDetecting = SystemSecureInput(),
        sounds: SoundPlaying = SystemSounds(),
        displayWake: DisplayWakeHolding = SystemDisplayWake(),
        shield: PointerShielding = ScreenShield(),
        gestures: GestureSuppressing = GestureSuppressor()
    ) {
        self.tap = tap
        self.permission = permission
        self.scheduler = scheduler
        self.secureInputDetector = secureInput
        self.sounds = sounds
        self.displayWake = displayWake
        self.shield = shield
        self.gestures = gestures
        refreshPermission()
    }

    // MARK: Permission

    func refreshPermission() {
        hasPermission = permission.isTrusted
    }

    func requestPermission() {
        // Untrusted while System Settings may still show dirtymac switched
        // on (an entry left by another build): clear it first, or macOS
        // shows no prompt and the switch does nothing.
        if !permission.isTrusted { permission.resetEntry() }
        hasPermission = permission.requestAccess()
    }

    /// Re-reads Secure Event Input. The panel calls this every second
    /// while it is open and no lock runs; during a lock the ticker does.
    func refreshSecureInput() {
        secureInput = secureInputDetector.isEnabled
            ? SecureInputStatus(ownerName: secureInputDetector.ownerName())
            : nil
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Lock

    /// Locks with `configuration`, the stored settings by default.
    /// Returns false when no lock started: the app has no Accessibility
    /// permission (the system prompt is shown), a full lockdown was asked
    /// for while secure input is on, a long full lockdown was asked for
    /// without `escVerified` (the panel passes it once the user has held
    /// Esc), or macOS refused the tap.
    @discardableResult
    func start(_ configuration: LockConfiguration = .current, escVerified: Bool = false) -> Bool {
        guard !isActive else { return true }
        // A wait that was still counting down is overtaken by this start.
        cancelPendingLock()

        // Applied here as well, so no caller can skip the safety rules
        // (such as the mandatory timer while the mouse is locked).
        let config = configuration.effective
        guard preflight(config, escVerified: escVerified) else { return false }

        let installed = tap.install(
            mask: EventMask.build(for: config),
            guardPointer: config.guardPointer && !config.blockMouseAndTrackpad
        ) { [weak self] decision in
            self?.handleEsc(decision)
        }
        guard installed else {
            // Tap creation failed — likely permission revoked between checks.
            hasPermission = false
            return false
        }

        // Only once the lock is certain to run, so a refused start never
        // leaves the display held.
        if config.keepDisplayAwake { displayWake.hold() }
        // The pointer is covered whenever it is guarded, or frozen: on
        // macOS 27 scrolling never passes the taps, a window takes it.
        if config.guardPointer || config.blockMouseAndTrackpad { shield.show() }
        // Three and four finger swipes cannot be stopped by any tap, so
        // their settings are turned off for the length of the lock.
        if config.suppressGestures { gestures.suppress() }

        startedAt = scheduler.now
        elapsed = 0
        autoUnlockTotal = config.autoUnlockSeconds
        mouseLocked = config.blockMouseAndTrackpad
        // Already on screen as a warning: no need to wait for a repeat.
        secureInputReadings = secureInput == nil ? 0 : SecureInputPolicy.readingsToAct
        lastUnlockReason = nil
        isActive = true
        sounds.play(.locked)

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

    /// The checks every lock passes before anything is installed: the
    /// permission (asked for when missing), secure input and, for a long
    /// frozen-mouse lock, the Esc check. Run again when a delayed lock
    /// finally starts, and once before the wait begins, so a lock that
    /// would be refused is refused at the click and not after a countdown.
    private func preflight(_ config: LockConfiguration, escVerified: Bool) -> Bool {
        refreshPermission()
        guard hasPermission else {
            requestPermission()
            return false
        }
        refreshSecureInput()
        guard SecureInputPolicy.canStart(
            secureInputOn: secureInput != nil,
            mouseLocked: config.blockMouseAndTrackpad
        ) else { return false }
        // Enforced here, not only in the panel, so no other way of starting
        // a lock (a shortcut, an intent, a future caller) can skip the check.
        return !config.requiresEscCheck || escVerified
    }

    // MARK: Delayed start

    /// Locks after the configured start delay, or at once without one.
    /// Every way of starting a lock that a person triggers (the panel, the
    /// menu, a Shortcut) comes through here. While the wait runs nothing
    /// is blocked and `lockCountdown` shows the seconds left.
    func beginLock(_ configuration: LockConfiguration = .current, escVerified: Bool = false) {
        guard !isActive, pendingLockTimer == nil else { return }
        let config = configuration.effective
        guard config.startDelaySeconds > 0 else {
            start(configuration, escVerified: escVerified)
            return
        }
        guard preflight(config, escVerified: escVerified) else { return }

        lockCountdown = config.startDelaySeconds
        sounds.play(.tick)
        pendingLockTimer = scheduler.schedule(after: 1, repeats: true) { [weak self] in
            self?.pendingLockTick(configuration, escVerified: escVerified)
        }
    }

    private func pendingLockTick(_ configuration: LockConfiguration, escVerified: Bool) {
        guard let remaining = lockCountdown else { return }
        guard remaining > 1 else {
            // Cleared first: start() checks everything again and may still
            // refuse (the permission was taken away meanwhile).
            cancelPendingLock()
            start(configuration, escVerified: escVerified)
            return
        }
        lockCountdown = remaining - 1
        sounds.play(.tick)
    }

    /// Ends a wait that is running. Safe to call when none is.
    func cancelPendingLock() {
        pendingLockTimer?.cancel()
        pendingLockTimer = nil
        if lockCountdown != nil { lockCountdown = nil }
    }

    func stop(reason: UnlockReason) {
        // A quit or a sleep during the wait must not lock afterwards.
        cancelPendingLock()
        guard isActive else { return }
        tap.uninstall()
        displayWake.release()
        shield.hide()
        gestures.restore()
        ticker?.cancel()
        ticker = nil
        autoUnlockTimer?.cancel()
        autoUnlockTimer = nil
        escHoldTimer?.cancel()
        escHoldTimer = nil
        escReleaseTimer?.cancel()
        escReleaseTimer = nil
        cancelEscTicks()
        endEscCountdown(to: .idle)
        startedAt = nil
        elapsed = 0
        autoUnlockTotal = 0
        mouseLocked = false
        secureInputReadings = 0
        lastUnlockReason = reason
        isActive = false
        if let cue = SoundSchedule.cue(for: reason) { sounds.play(cue) }
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
        if SoundSchedule.countdownTicks(remaining: autoUnlockRemaining, total: autoUnlockTotal) {
            sounds.play(.tick)
        }
        // The deadline timer can fire late, e.g. right after the Mac
        // wakes. The clock decides, so the countdown can't sit at 00:00
        // while the lock keeps running.
        if autoUnlockTotal > 0, elapsed >= TimeInterval(autoUnlockTotal) {
            stop(reason: .autoUnlock)
            return
        }
        checkSecureInput()
    }

    private func checkSecureInput() {
        guard secureInputDetector.isEnabled else {
            secureInputReadings = 0
            secureInput = nil
            return
        }
        secureInputReadings += 1
        switch SecureInputPolicy.duringLock(readings: secureInputReadings, mouseLocked: mouseLocked) {
        case .none:
            break
        case .warn:
            if secureInput == nil {
                secureInput = SecureInputStatus(ownerName: secureInputDetector.ownerName())
                sounds.play(.warning)
            }
        case .release:
            secureInput = SecureInputStatus(ownerName: secureInputDetector.ownerName())
            stop(reason: .secureInput)
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
        escTickTimers = SoundSchedule.escHoldTicks(holdDuration: Self.escHoldDuration).map { delay in
            scheduler.schedule(after: delay, repeats: false) { [weak self] in
                self?.sounds.play(.tick)
            }
        }
        escHoldStartedAt = scheduler.now
        publishEscCountdown()
        escCountdownTimer = scheduler.schedule(after: Self.escCountdownInterval, repeats: true) { [weak self] in
            self?.publishEscCountdown()
        }
    }

    private func publishEscCountdown() {
        guard let escHoldStartedAt else { return }
        let held = max(0, scheduler.now - escHoldStartedAt)
        let next = EscHoldState.holding(
            remaining: EscHoldState.remainingSeconds(held: held, total: Self.escHoldDuration),
            progress: min(1, held / Self.escHoldDuration)
        )
        if next != escHold { escHold = next }
    }

    /// Stops refreshing the countdown and leaves `state` showing.
    private func endEscCountdown(to state: EscHoldState) {
        escCountdownTimer?.cancel()
        escCountdownTimer = nil
        escHoldStartedAt = nil
        if escHold != state { escHold = state }
    }

    private func cancelEscTicks() {
        escTickTimers.forEach { $0.cancel() }
        escTickTimers = []
    }

    private func escHoldCompleted() {
        escHoldTimer = nil
        cancelEscTicks()
        guard isActive else { return }
        endEscCountdown(to: .letGo)
        // The chime is the cue to let go; the unlock finishes on release.
        sounds.play(.unlocked)
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
        cancelEscTicks()
        endEscCountdown(to: .idle)
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
