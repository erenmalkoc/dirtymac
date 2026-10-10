import Foundation
import Combine
import CoreGraphics
import ApplicationServices
import AppKit

// What the tap blocks and how it treats each event lives in LockCore.swift.

@MainActor
final class KeyboardBlocker: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var hasPermission: Bool = false
    /// Configured auto-unlock duration for the active session (0 = none).
    @Published private(set) var autoUnlockTotal: Int = 0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var ticker: Timer?
    private var startedAt: Date?

    private var autoUnlockTimer: Timer?
    private var escHoldTimer: Timer?
    private let escHoldDuration: TimeInterval = 3.0

    init() {
        refreshPermission()
    }

    // MARK: Permission

    func refreshPermission() {
        hasPermission = AXIsProcessTrusted()
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let opts = [key: true] as CFDictionary
        hasPermission = AXIsProcessTrustedWithOptions(opts)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Toggle

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard !isActive else { return }

        refreshPermission()
        guard hasPermission else {
            requestPermission()
            return
        }

        let config = LockConfiguration.current
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: EventMask.build(for: config),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
                // The tap's run-loop source is on the main run loop, so
                // the callback already runs on the main thread.
                let swallow = MainActor.assumeIsolated {
                    blocker.handle(TapEventDecision.decide(type: type, event: event))
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            // Tap creation failed — likely permission revoked between checks.
            hasPermission = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        startedAt = Date()
        elapsed = 0
        autoUnlockTotal = config.autoUnlockSeconds
        isActive = true

        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer is scheduled on the main run loop, so it fires on the
            // main thread — hop to the MainActor without a Task suspend.
            MainActor.assumeIsolated {
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }

        if autoUnlockTotal > 0 {
            autoUnlockTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(autoUnlockTotal),
                repeats: false
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                }
            }
        }
    }

    func stop() {
        guard isActive else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        ticker?.invalidate()
        ticker = nil
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        escHoldTimer?.invalidate()
        escHoldTimer = nil
        startedAt = nil
        elapsed = 0
        autoUnlockTotal = 0
        isActive = false
    }

    /// Acts on one tap decision; returns whether to swallow the event.
    /// The Esc events are swallowed too: the hold pattern is only our
    /// unlock trigger and must never reach apps.
    fileprivate func handle(_ decision: TapEventDecision) -> Bool {
        switch decision {
        case .pass:
            return false
        case .block:
            return true
        case .escDown:
            escHoldBegan()
            return true
        case .escUp:
            escHoldEnded()
            return true
        case .reEnable:
            reEnableTap()
            return false
        }
    }

    fileprivate func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Hold-Escape emergency exit

    fileprivate func escHoldBegan() {
        guard isActive, escHoldTimer == nil else { return } // ignore auto-repeat
        escHoldTimer = Timer.scheduledTimer(
            withTimeInterval: escHoldDuration,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.stop()
            }
        }
    }

    fileprivate func escHoldEnded() {
        escHoldTimer?.invalidate()
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
