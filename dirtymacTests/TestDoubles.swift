import CoreGraphics
import Foundation
@testable import dirtymac

/// Stands in for the real CGEventTap: records what the blocker installs
/// and lets a test feed it the hold-Esc input.
final class FakeEventTap: EventTapping {
    var refuses = false
    private(set) var installedMask: CGEventMask?
    private(set) var installCount = 0
    private(set) var uninstallCount = 0
    private var onEsc: (@MainActor (TapEventDecision) -> Void)?

    var isInstalled: Bool { onEsc != nil }

    func install(mask: CGEventMask, onEsc: @escaping @MainActor (TapEventDecision) -> Void) -> Bool {
        guard !refuses else { return false }
        installCount += 1
        installedMask = mask
        self.onEsc = onEsc
        return true
    }

    func uninstall() {
        if onEsc != nil { uninstallCount += 1 }
        onEsc = nil
    }

    func send(_ decision: TapEventDecision) {
        onEsc?(decision)
    }
}

final class FakePermission: AccessibilityPermission {
    var trusted = true
    private(set) var requests = 0

    var isTrusted: Bool { trusted }

    func requestAccess() -> Bool {
        requests += 1
        return trusted
    }
}

final class FakeSecureInput: SecureInputDetecting {
    var enabled = false
    var owner: String? = "Terminal"

    var isEnabled: Bool { enabled }

    func ownerName() -> String? { owner }
}

/// A clock the test moves by hand; timers fire in order as it passes them.
final class ManualScheduler: LockScheduling {
    private final class Entry: LockTimer {
        var fireAt: TimeInterval
        let interval: TimeInterval
        let repeats: Bool
        let action: @MainActor () -> Void
        var isCancelled = false

        init(fireAt: TimeInterval, interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.interval = interval
            self.repeats = repeats
            self.action = action
        }

        func cancel() { isCancelled = true }
    }

    private(set) var now: TimeInterval = 1_000
    private var entries: [Entry] = []

    /// Timers that are scheduled and not cancelled.
    var pendingCount: Int { entries.filter { !$0.isCancelled }.count }

    func schedule(after delay: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> LockTimer {
        let entry = Entry(fireAt: now + delay, interval: delay, repeats: repeats, action: action)
        entries.append(entry)
        return entry
    }

    /// Moves the clock without firing anything, like time spent asleep:
    /// timers that fell due fire late, on the next `advance`.
    func jump(by seconds: TimeInterval) {
        now += seconds
    }

    /// Moves the clock forward, firing every timer that falls due on the
    /// way, in order.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = entries
            .filter({ !$0.isCancelled && $0.fireAt <= target + 1e-6 })
            .min(by: { $0.fireAt < $1.fireAt }) {
            now = max(now, next.fireAt)
            if next.repeats {
                next.fireAt += next.interval
            } else {
                next.isCancelled = true
            }
            next.action()
        }
        now = target
        entries.removeAll { $0.isCancelled }
    }
}

/// A blocker wired to fakes.
final class BlockerRig {
    let tap = FakeEventTap()
    let permission = FakePermission()
    let clock = ManualScheduler()
    let secureInput = FakeSecureInput()
    lazy var blocker = KeyboardBlocker(
        tap: tap,
        permission: permission,
        scheduler: clock,
        secureInput: secureInput
    )
}
