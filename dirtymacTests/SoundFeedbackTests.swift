import XCTest
import AppKit
@testable import dirtymac

final class SoundFeedbackTests: XCTestCase {
    /// The cues use system sounds by name; if a macOS release renames
    /// them, the preferred name fails here before users hear silence.
    func testEveryCueHasItsSystemSound() {
        for cue in SoundCue.allCases {
            let name = cue.soundNames[0]
            XCTAssertNotNil(NSSound(named: NSSound.Name(name)), "\(cue): no system sound named \(name)")
            XCTAssertNotNil(SystemSounds().sound(for: cue), "\(cue)")
        }
    }

    func testSoundsAreOnUntilTurnedOff() throws {
        let defaults = try TestDefaults.make(self)
        XCTAssertTrue(SystemSounds.isEnabled(in: defaults))
        defaults.set(false, forKey: SystemSounds.enabledKey)
        XCTAssertFalse(SystemSounds.isEnabled(in: defaults))
    }

    func testAnEscHoldTicksEachSecondBeforeItCompletes() {
        XCTAssertEqual(SoundSchedule.escHoldTicks(holdDuration: 3), [1, 2])
    }

    func testTheLastThreeSecondsOfAnAutoUnlockTick() {
        XCTAssertEqual((0...5).filter { SoundSchedule.countdownTicks(remaining: $0, total: 30) }, [1, 2, 3])
        XCTAssertFalse(SoundSchedule.countdownTicks(remaining: 2, total: 5), "short timers stay quiet")
        XCTAssertFalse(SoundSchedule.countdownTicks(remaining: 2, total: 0))
    }

    func testOnlyUnlocksNobodyWatchedAreAnnounced() {
        XCTAssertEqual(SoundSchedule.cue(for: .autoUnlock), .unlocked)
        XCTAssertEqual(SoundSchedule.cue(for: .secureInput), .warning)
        let quiet: [UnlockReason] = [.clicked, .escHeld, .quit, .systemSleep, .screenLocked,
                                     .userSwitched, .systemSettings, .permissionRevoked]
        for reason in quiet { XCTAssertNil(SoundSchedule.cue(for: reason), "\(reason)") }
    }
}
