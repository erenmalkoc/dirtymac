import Foundation
import IOKit.pwr_mgt

/// Keeps the display from dimming or sleeping while the keyboard is locked.
///
/// A lock lasts minutes now, and with the keyboard and the mouse both still
/// nobody touches the Mac, so the screen saver or the display sleep would
/// start. A screen that locks or a Mac that sleeps ends the lock (see
/// SessionWatcher), which would cut a cleaning short. macOS releases the
/// assertion by itself if the app dies, so a crash cannot leave the display
/// awake for good.
nonisolated protocol DisplayWakeHolding: AnyObject {
    /// Starts keeping the display awake. False when macOS refused, which
    /// is not worth failing a lock over.
    @discardableResult func hold() -> Bool
    /// Lets the display sleep again. Safe to call when nothing is held.
    func release()
}

nonisolated final class SystemDisplayWake: DisplayWakeHolding {
    private var assertionID: IOPMAssertionID = 0
    private var held = false

    var isHeld: Bool { held }

    @discardableResult
    func hold() -> Bool {
        guard !held else { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "dirtymac is locking the keyboard" as CFString,
            &assertionID
        )
        held = result == kIOReturnSuccess
        return held
    }

    func release() {
        guard held else { return }
        IOPMAssertionRelease(assertionID)
        held = false
        assertionID = 0
    }

    deinit { release() }
}
