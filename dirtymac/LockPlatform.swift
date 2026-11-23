import AppKit
import ApplicationServices
import CoreGraphics
import os

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

/// One installed tap and what its callback needs to know.
final class TapContext {
    unowned let owner: SessionEventTap
    let label: String
    var port: CFMachPort?
    var source: CFRunLoopSource?
    var pointerGuard: PointerGuard?
    var tally: TapTally?
    var lastFlush = CFAbsoluteTimeGetCurrent()

    init(owner: SessionEventTap, label: String, pointerGuard: PointerGuard?, diagnostics: Bool) {
        self.owner = owner
        self.label = label
        self.pointerGuard = pointerGuard
        self.tally = diagnostics ? TapTally() : nil
    }
}

/// The real tap: session-level, head-inserted, on the main run loop. The
/// pointer events are tapped a second time at the HID level, which sits
/// before the session in the input path, so a Mac that hands trackpad
/// input to apps without it passing the session tap is still covered.
/// If the HID tap cannot be made, the session tap alone does the job.
final class SessionEventTap: EventTapping {
    private var contexts: [TapContext] = []
    private var onEsc: (@MainActor (TapEventDecision) -> Void)?
    private let ownWindows: OwnWindowHitTesting
    private let logger = Logger(subsystem: "tech.erenium.dirtymac", category: "tap")

    init(ownWindows: OwnWindowHitTesting = OwnWindowHitTest()) {
        self.ownWindows = ownWindows
    }

    func install(mask: CGEventMask, guardPointer: Bool, onEsc: @escaping @MainActor (TapEventDecision) -> Void) -> Bool {
        uninstall()
        let diagnostics = UserDefaults.standard.bool(forKey: TapTally.defaultsKey)

        guard let session = makeTap(
            label: "session", location: .cgSessionEventTap, mask: mask,
            guardPointer: guardPointer, diagnostics: diagnostics
        ) else {
            return false
        }
        contexts = [session]
        self.onEsc = onEsc

        let pointerMask = mask & EventMask.pointerMask
        if pointerMask != 0,
           let hid = makeTap(
            label: "hid", location: .cghidEventTap, mask: pointerMask,
            guardPointer: guardPointer, diagnostics: diagnostics
           ) {
            contexts.append(hid)
        }
        if diagnostics {
            logger.notice("installed \(self.contexts.map(\.label).joined(separator: "+"), privacy: .public), mask \(String(mask, radix: 16), privacy: .public)")
        }
        return true
    }

    private func makeTap(
        label: String, location: CGEventTapLocation, mask: CGEventMask,
        guardPointer: Bool, diagnostics: Bool
    ) -> TapContext? {
        let context = TapContext(
            owner: self, label: label,
            pointerGuard: guardPointer ? PointerGuard() : nil, diagnostics: diagnostics
        )
        let refcon = Unmanaged.passUnretained(context).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<TapContext>.fromOpaque(refcon).takeUnretainedValue()
                // The run-loop source is on the main run loop, so the
                // callback already runs on the main thread.
                let swallow = MainActor.assumeIsolated {
                    context.owner.handle(context.owner.decision(type: type, event: event, in: context), type: type, event: event, in: context)
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return nil
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        context.port = port
        context.source = source
        return context
    }

    func uninstall() {
        for context in contexts {
            flush(context, force: true)
            if let port = context.port {
                CGEvent.tapEnable(tap: port, enable: false)
            }
            if let port = context.port, let source = context.source {
                Self.invalidate(port: port, source: source)
            }
            context.port = nil
            context.source = nil
        }
        contexts = []
        onEsc = nil
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
    fileprivate func decision(type: CGEventType, event: CGEvent, in context: TapContext) -> TapEventDecision {
        if var pointerGuard = context.pointerGuard, EventMask.isGuarded(type) {
            let location = event.location
            let windows = ownWindows
            let decision = pointerGuard.decide(type: type) { windows.isOverOwnWindow(at: location) }
            context.pointerGuard = pointerGuard
            return decision
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            context.pointerGuard?.reset()
        }
        return TapEventDecision.decide(type: type, event: event)
    }

    /// Acts on one decision; returns whether to swallow the event. Esc is
    /// swallowed too: the hold is only our unlock trigger and must never
    /// reach apps.
    fileprivate func handle(_ decision: TapEventDecision, type: CGEventType, event: CGEvent, in context: TapContext) -> Bool {
        let swallow: Bool
        switch decision {
        case .pass:
            swallow = false
        case .block:
            swallow = true
        case .escDown, .escUp:
            onEsc?(decision)
            swallow = true
        case .reEnable:
            if let port = context.port { CGEvent.tapEnable(tap: port, enable: true) }
            swallow = false
        }
        if context.tally != nil {
            let subtype = type.rawValue == kCGEventSystemDefined ? NSEvent(cgEvent: event)?.subtype.rawValue : nil
            context.tally?.record(TapTally.kind(of: type, systemSubtype: subtype), swallowed: swallow)
            flush(context, force: false)
        }
        return swallow
    }

    /// With diagnostics on, once a second says how many events of each
    /// kind a tap saw and what became of them. Counts only: nothing that
    /// was typed or where anything was clicked.
    private func flush(_ context: TapContext, force: Bool) {
        guard context.tally != nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - context.lastFlush >= 1 else { return }
        context.lastFlush = now
        if let summary = context.tally?.flush() {
            logger.notice("\(context.label, privacy: .public) tap: \(summary, privacy: .public)")
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
    /// The cover over the screens is one of our windows too, but a click
    /// on it is exactly what must not count as a click on dirtymac.
    var shieldLayer: Int = Int(ShieldGeometry.level.rawValue)

    func isOverOwnWindow(at point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let front = Self.frontmostWindow(at: point, in: list)
        else { return false }
        return Self.isOwn(front, pid: pid, shieldLayer: shieldLayer)
    }

    /// One of our windows, but not the cover.
    static func isOwn(_ front: (owner: pid_t, layer: Int), pid: pid_t, shieldLayer: Int) -> Bool {
        front.owner == pid && front.layer != shieldLayer
    }

    /// The owner of the first visible window in `windows` (front to back)
    /// that holds `point`.
    static func frontmostOwner(at point: CGPoint, in windows: [[String: Any]]) -> pid_t? {
        frontmostWindow(at: point, in: windows)?.owner
    }

    /// Owner and level of the first visible window in `windows` (front to
    /// back) that holds `point`.
    static func frontmostWindow(at point: CGPoint, in windows: [[String: Any]]) -> (owner: pid_t, layer: Int)? {
        for window in windows {
            let alpha = (window[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            else { continue }
            return (owner, (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)
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
