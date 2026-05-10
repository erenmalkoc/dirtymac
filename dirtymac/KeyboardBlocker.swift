import Foundation
import Combine
import CoreGraphics
import ApplicationServices
import AppKit

@MainActor
final class KeyboardBlocker: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var hasPermission: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var ticker: Timer?
    private var startedAt: Date?

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

        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
                        Task { @MainActor in blocker.reEnableTap() }
                    }
                    return Unmanaged.passUnretained(event)
                }
                // Swallow keyboard events entirely.
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
        isActive = true

        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer is scheduled on the main run loop, so it fires on the
            // main thread — hop to the MainActor without a Task suspend.
            MainActor.assumeIsolated {
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
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
        startedAt = nil
        elapsed = 0
        isActive = false
    }

    fileprivate func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Display helpers

    var elapsedDisplay: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
