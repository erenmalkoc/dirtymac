import Foundation
import Combine
import CoreGraphics
import ApplicationServices
import AppKit

// macOS routes media / brightness / volume / function-key controls
// through a separate event channel: `kCGEventSystemDefined` (raw 14)
// with the aux-buttons subtype (NX_SUBTYPE_AUX_CONTROL_BUTTONS = 8).
// They do NOT arrive as keyDown / keyUp, so a plain keyboard tap
// lets them through. We add the system-defined type to the mask and
// then filter by subtype inside the callback so other system events
// (e.g. power button, subtype 1) keep working — leaving the user a
// hardware emergency exit if anything goes wrong.
private let kCGEventSystemDefined: UInt32 = 14
private let kAuxControlButtonsSubtype: Int16 = 8

// Escape key. Holding it for `escHoldDuration` force-unlocks — the
// universal emergency exit, available in every mode and essential when
// the mouse is part of the lockdown (the menu bar is unreachable then).
private let kEscapeKeyCode: Int64 = 53

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

        var rawMask = (1 << CGEventType.keyDown.rawValue)
                     | (1 << CGEventType.keyUp.rawValue)

        if config.blockModifierKeys {
            rawMask |= (1 << CGEventType.flagsChanged.rawValue)
        }
        if config.blockMediaKeys {
            rawMask |= (1 << kCGEventSystemDefined)
        }
        if config.blockMouseAndTrackpad {
            let mouseTypes: [CGEventType] = [
                .leftMouseDown, .leftMouseUp,
                .rightMouseDown, .rightMouseUp,
                .otherMouseDown, .otherMouseUp,
                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                .mouseMoved, .scrollWheel
            ]
            for t in mouseTypes { rawMask |= (1 << t.rawValue) }
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(rawMask),
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
                        Task { @MainActor in blocker.reEnableTap() }
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Hold-Escape emergency exit. We still swallow the Esc
                // events so they never reach apps; the hold pattern is
                // only used as our unlock trigger.
                if type == .keyDown || type == .keyUp {
                    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keycode == kEscapeKeyCode, let refcon {
                        let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
                        MainActor.assumeIsolated {
                            if type == .keyDown { blocker.escHoldBegan() }
                            else { blocker.escHoldEnded() }
                        }
                        return nil
                    }
                }

                // System-defined events: only swallow the aux-button
                // subtype (brightness, volume, media, F-key controls).
                // Pass everything else through so things like the power
                // button still reach the system.
                if type.rawValue == kCGEventSystemDefined {
                    let isAuxControl = MainActor.assumeIsolated {
                        NSEvent(cgEvent: event)?.subtype.rawValue == kAuxControlButtonsSubtype
                    }
                    return isAuxControl ? nil : Unmanaged.passUnretained(event)
                }

                // Everything else in the mask is meant to be blocked.
                return nil
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
