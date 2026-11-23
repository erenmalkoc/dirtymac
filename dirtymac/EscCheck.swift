import AppKit
import Combine

/// "Hold Esc to check that your way out works": the step a long full
/// lockdown asks for before it starts. With the mouse frozen the only ways
/// out are hold-Esc and the timer, so a keyboard whose Esc does not reach
/// the app (a layout without the key, a remap, a keyboard that is not
/// the one being cleaned) is found out while the keyboard still works.
///
/// The rules are a small value type driven by a clock, so every edge is
/// tested without a keyboard.
struct EscCheck: Equatable {
    /// As long as the real exit, so passing this proves the real one works.
    static let defaultHoldDuration = KeyboardBlocker.escHoldDuration

    var holdDuration: TimeInterval = EscCheck.defaultHoldDuration
    private(set) var heldSince: TimeInterval?
    private(set) var passed = false

    /// Esc went down. The key repeats while held: only the first press
    /// counts, or the timer would restart every few milliseconds.
    mutating func escDown(at now: TimeInterval) {
        guard !passed, heldSince == nil else { return }
        heldSince = now
    }

    /// Esc came up. Held long enough, that is a pass, even if no tick
    /// happened to land between the last moment and the release.
    mutating func escUp(at now: TimeInterval) {
        tick(at: now)
        heldSince = nil
    }

    mutating func tick(at now: TimeInterval) {
        guard let heldSince, now - heldSince >= holdDuration else { return }
        passed = true
        self.heldSince = nil
    }

    /// 0...1, for the bar. A clock that went backwards counts as zero.
    func progress(at now: TimeInterval) -> Double {
        if passed { return 1 }
        guard let heldSince else { return 0 }
        return min(1, max(0, (now - heldSince) / holdDuration))
    }

    mutating func reset() {
        heldSince = nil
        passed = false
    }
}

/// Listens for Esc while the confirmation is on screen and feeds EscCheck.
///
/// The panel is an NSPopover, which closes when Esc is pressed. While the
/// check is running the Esc events are taken before the popover sees them,
/// and handed back as soon as the check passed.
@MainActor
final class EscCheckModel: ObservableObject {
    static let escKeyCode: UInt16 = 53

    @Published private(set) var progress: Double = 0
    @Published private(set) var passed = false

    private var check: EscCheck
    /// Whether the Esc press being followed is still down.
    private var escIsDown = false
    private let now: () -> TimeInterval
    // Plain handles, read from deinit too, which is not isolated.
    nonisolated(unsafe) private var monitor: Any?
    nonisolated(unsafe) private var timer: Timer?

    /// How many Esc monitors exist right now, across all models. Zero
    /// whenever no confirmation is being checked: a leaked monitor would
    /// keep swallowing Esc. Counted so a test can see a leak.
    nonisolated(unsafe) private(set) static var activeMonitors = 0

    var isListening: Bool { monitor != nil }

    /// A model dropped while listening (its view went away without a
    /// stop) must not leave Esc swallowed for the rest of the session.
    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            Self.activeMonitors -= 1
        }
        timer?.invalidate()
    }

    init(
        holdDuration: TimeInterval = EscCheck.defaultHoldDuration,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        check = EscCheck(holdDuration: holdDuration)
        self.now = now
    }

    /// Begins from zero. Calling it again starts over, never a second listener.
    func start() {
        stop()
        check.reset()
        escIsDown = false
        publish()
        Self.activeMonitors += 1
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // Local monitors run on the main thread.
            let swallowed = MainActor.assumeIsolated {
                self?.handle(keyCode: event.keyCode, isDown: event.type == .keyDown, isRepeat: event.isARepeat) ?? false
            }
            return swallowed ? nil : event
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        // Every run-loop mode, so the bar keeps moving while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Lets go of the keyboard events. Safe to call at any time, repeatedly.
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            Self.activeMonitors -= 1
        }
        monitor = nil
        timer?.invalidate()
        timer = nil
    }

    /// Forgets a pass, for the next time the confirmation opens.
    func reset() {
        check.reset()
        escIsDown = false
        publish()
    }

    /// Returns whether the event is taken (true) or goes on to the panel.
    @discardableResult
    func handle(keyCode: UInt16, isDown: Bool, isRepeat: Bool) -> Bool {
        guard keyCode == Self.escKeyCode else { return false }
        if check.passed {
            // Passing happens while the key is still held. Its repeats and
            // its release are still part of that press: let one through
            // and the popover closes under the user's finger (Esc closes
            // it), and reopening starts the check over.
            let partOfTheHeldPress = escIsDown
            if !isDown { escIsDown = false }
            return partOfTheHeldPress
        }
        if isDown {
            if !isRepeat {
                escIsDown = true
                check.escDown(at: now())
            }
        } else {
            escIsDown = false
            check.escUp(at: now())
        }
        publish()
        return true
    }

    func refresh() {
        check.tick(at: now())
        publish()
    }

    private func publish() {
        let current = check.progress(at: now())
        if current != progress { progress = current }
        if check.passed != passed { passed = check.passed }
    }
}
