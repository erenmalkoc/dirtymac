import AppKit
import ApplicationServices
import CoreGraphics

// The three things KeyboardBlocker needs from the system, behind small
// protocols so the whole lock lifecycle can be unit-tested with fakes:
// a real event tap needs an Accessibility permission CI cannot grant.

// MARK: - Event tap

protocol EventTapping: AnyObject {
    /// Starts intercepting the events in `mask`. With `guardPointer` the
    /// mouse buttons and scrolling in the mask are only let through over
    /// dirtymac's own windows (see `PointerGuard`). `onEsc` receives the
    /// hold-Esc input (`.escDown` / `.escUp`). Returns false when macOS
    /// refused the tap.
    func install(mask: CGEventMask, guardPointer: Bool, onEsc: @escaping @MainActor (TapEventDecision) -> Void) -> Bool
    /// Stops intercepting. Safe to call when nothing is installed.
    func uninstall()
}

/// The real tap: session-level, head-inserted, on the main run loop.
final class SessionEventTap: EventTapping {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var onEsc: (@MainActor (TapEventDecision) -> Void)?
    private var pointerGuard: PointerGuard?
    private let ownWindows: OwnWindowHitTesting

    init(ownWindows: OwnWindowHitTesting = OwnWindowHitTest()) {
        self.ownWindows = ownWindows
    }

    func install(mask: CGEventMask, guardPointer: Bool, onEsc: @escaping @MainActor (TapEventDecision) -> Void) -> Bool {
        uninstall()
        pointerGuard = guardPointer ? PointerGuard() : nil
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<SessionEventTap>.fromOpaque(refcon).takeUnretainedValue()
                // The run-loop source is on the main run loop, so the
                // callback already runs on the main thread.
                let swallow = MainActor.assumeIsolated {
                    tap.handle(tap.decision(type: type, event: event))
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        self.onEsc = onEsc
        return true
    }

    func uninstall() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let port, let source {
            Self.invalidate(port: port, source: source)
        }
        port = nil
        source = nil
        onEsc = nil
        pointerGuard = nil
    }

    /// Removes the source from the main run loop and invalidates the
    /// port, which also tears down the WindowServer tap. Releasing the
    /// references alone left every past lock's disabled tap alive until
    /// the app quit.
    static func invalidate(port: CFMachPort, source: CFRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(port)
    }

    /// The pointer events of a guarded lock go through the guard, which
    /// looks at the window under the cursor only when a button goes down.
    /// Everything else is decided by the plain rules.
    private func decision(type: CGEventType, event: CGEvent) -> TapEventDecision {
        if var pointerGuard, EventMask.isGuarded(type) {
            let location = event.location
            let windows = ownWindows
            let decision = pointerGuard.decide(type: type) { windows.isOverOwnWindow(at: location) }
            self.pointerGuard = pointerGuard
            return decision
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pointerGuard?.reset()
        }
        return TapEventDecision.decide(type: type, event: event)
    }

    /// Acts on one decision; returns whether to swallow the event. Esc is
    /// swallowed too: the hold is only our unlock trigger and must never
    /// reach apps.
    private func handle(_ decision: TapEventDecision) -> Bool {
        switch decision {
        case .pass:
            return false
        case .block:
            return true
        case .escDown, .escUp:
            onEsc?(decision)
            return true
        case .reEnable:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
    }
}

// MARK: - Own windows

/// Whether a point on the screen is over one of dirtymac's own windows.
protocol OwnWindowHitTesting {
    /// `point` is in global display coordinates, origin at the top left
    /// of the main display, which is what event locations use.
    func isOverOwnWindow(at point: CGPoint) -> Bool
}

/// Asks the window server which window is frontmost at the point: the
/// menu bar icon, the open panel and its menus are all windows of this
/// process, and the first window of the front-to-back list that holds the
/// point is the one a click would hit. Bounds and owner need no Screen
/// Recording permission.
struct OwnWindowHitTest: OwnWindowHitTesting {
    var pid: pid_t = ProcessInfo.processInfo.processIdentifier

    func isOverOwnWindow(at point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return Self.frontmostOwner(at: point, in: list) == pid
    }

    /// The owner of the first visible window in `windows` (front to back)
    /// that holds `point`.
    static func frontmostOwner(at point: CGPoint, in windows: [[String: Any]]) -> pid_t? {
        for window in windows {
            let alpha = (window[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point)
            else { continue }
            return (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        }
        return nil
    }
}

// MARK: - Accessibility permission

protocol AccessibilityPermission {
    var isTrusted: Bool { get }
    /// Shows the system prompt when the app isn't trusted yet; returns
    /// the current state.
    func requestAccess() -> Bool
    /// Removes this app's own entry from the Accessibility list.
    func resetEntry()
}

struct SystemAccessibility: AccessibilityPermission {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// An entry recorded for another build of the app (one run from
    /// Xcode, or a copy that was replaced while it ran) still shows as
    /// switched on in System Settings but no longer applies, and macOS
    /// then shows no prompt. Removing it lets the prompt and a fresh,
    /// working switch appear. Best effort: on failure the prompt still
    /// opens and the panel explains the manual way.
    func resetEntry() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = ["reset", "Accessibility", bundleID]
        tccutil.standardOutput = FileHandle.nullDevice
        tccutil.standardError = FileHandle.nullDevice
        do {
            try tccutil.run()
            tccutil.waitUntilExit()
        } catch {
            NSLog("dirtymac: tccutil reset failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Time

/// A scheduled callback that can be cancelled.
protocol LockTimer: AnyObject {
    func cancel()
}

/// Time and timers for a lock session.
protocol LockScheduling: AnyObject {
    /// Seconds on a clock that only moves forward.
    var now: TimeInterval { get }
    /// Runs `action` on the main thread after `delay` seconds, once or
    /// every `delay` seconds.
    func schedule(after delay: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> LockTimer
}

final class RunLoopScheduler: LockScheduling {
    /// CLOCK_MONOTONIC keeps counting while the Mac sleeps and never
    /// jumps with the wall clock, so the countdown, the elapsed time and
    /// the unlock deadline all measure the same thing.
    var now: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    func schedule(after delay: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> LockTimer {
        let timer = Timer(timeInterval: delay, repeats: repeats) { _ in
            // Main-run-loop timers fire on the main thread.
            MainActor.assumeIsolated { action() }
        }
        // Common modes, like the tap's own source: in the default mode
        // alone, hold-Esc and auto-unlock stalled while a menu was open.
        RunLoop.main.add(timer, forMode: .common)
        return ScheduledTimer(timer)
    }
}

private final class ScheduledTimer: LockTimer {
    private let timer: Timer

    init(_ timer: Timer) { self.timer = timer }

    func cancel() { timer.invalidate() }
}
