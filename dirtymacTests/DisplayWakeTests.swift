import XCTest
import IOKit.pwr_mgt
@testable import dirtymac

/// The screen stays on while the keyboard is locked, and only then.
@MainActor
final class DisplayWakeTests: XCTestCase {
    private func timed(_ seconds: Int = 0, keepAwake: Bool = true) -> LockConfiguration {
        LockConfiguration(mode: .advanced, autoUnlockSeconds: seconds, keepDisplayAwake: keepAwake)
    }

    // MARK: Held exactly while locked

    func testTheDisplayIsHeldWhileTheLockRunsAndReleasedWhenItEnds() {
        let rig = BlockerRig()
        XCTAssertFalse(rig.displayWake.isHeld)
        rig.blocker.start(timed())
        XCTAssertTrue(rig.displayWake.isHeld)
        XCTAssertEqual(rig.displayWake.holdCalls, 1)
        rig.blocker.stop(reason: .clicked)
        XCTAssertFalse(rig.displayWake.isHeld)
        XCTAssertEqual(rig.displayWake.releaseCalls, 1)
    }

    func testEveryWayTheLockEndsReleasesTheDisplay() {
        let reasons: [UnlockReason] = [
            .clicked, .escHeld, .autoUnlock, .quit, .systemSleep, .screenLocked,
            .userSwitched, .systemSettings, .permissionRevoked, .secureInput,
        ]
        for reason in reasons {
            let rig = BlockerRig()
            rig.blocker.start(timed())
            rig.blocker.stop(reason: reason)
            XCTAssertFalse(rig.displayWake.isHeld, "\(reason)")
        }
    }

    func testHoldEscAndTheTimerReleaseItThroughTheirRealPaths() {
        let held = BlockerRig()
        held.blocker.start(timed())
        held.tap.send(.escDown)
        held.clock.advance(by: 3.2)
        held.tap.send(.escUp)
        held.clock.advance(by: 0)
        XCTAssertFalse(held.blocker.isActive)
        XCTAssertFalse(held.displayWake.isHeld)

        let auto = BlockerRig()
        auto.blocker.start(timed(30))
        auto.clock.advance(by: 31)
        XCTAssertFalse(auto.blocker.isActive)
        XCTAssertFalse(auto.displayWake.isHeld)
    }

    func testItIsNeverHeldTwiceNorReleasedWithoutALock() {
        let rig = BlockerRig()
        rig.blocker.start(timed())
        rig.blocker.start(timed())   // already locked: a no-op
        XCTAssertEqual(rig.displayWake.holdCalls, 1)
        rig.blocker.stop(reason: .clicked)
        rig.blocker.stop(reason: .clicked)   // nothing running
        XCTAssertEqual(rig.displayWake.releaseCalls, 1)
    }

    func testEachNewLockHoldsItAgain() {
        let rig = BlockerRig()
        for round in 1...3 {
            rig.blocker.start(timed())
            XCTAssertTrue(rig.displayWake.isHeld)
            rig.blocker.stop(reason: .clicked)
            XCTAssertFalse(rig.displayWake.isHeld)
            XCTAssertEqual(rig.displayWake.holdCalls, round)
        }
    }

    // MARK: The switch

    func testTurnedOffTheDisplayIsLeftAlone() {
        let rig = BlockerRig()
        rig.blocker.start(timed(keepAwake: false))
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.displayWake.holdCalls, 0)
        rig.blocker.stop(reason: .clicked)
        XCTAssertFalse(rig.displayWake.isHeld)
    }

    func testBasicModeKeepsTheScreenAwakeToo() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration())
        XCTAssertTrue(rig.displayWake.isHeld, "the preset fixes what is blocked, not this")
        let off = BlockerRig()
        off.blocker.start(LockConfiguration(keepDisplayAwake: false))
        XCTAssertEqual(off.displayWake.holdCalls, 0, "and the switch still applies in Basic")
    }

    func testAFullLockdownHoldsItToo() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 120))
        XCTAssertTrue(rig.displayWake.isHeld)
    }

    // MARK: A lock that does not start holds nothing

    func testARefusedLockNeverTakesTheDisplay() {
        let noPermission = BlockerRig()
        noPermission.permission.trusted = false
        noPermission.blocker.start(timed())
        XCTAssertEqual(noPermission.displayWake.holdCalls, 0, "no permission")

        let secure = BlockerRig()
        secure.secureInput.enabled = true
        secure.blocker.start(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 120))
        XCTAssertEqual(secure.displayWake.holdCalls, 0, "full lockdown refused for secure input")

        let unchecked = BlockerRig()
        unchecked.blocker.start(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 900))
        XCTAssertEqual(unchecked.displayWake.holdCalls, 0, "a long lock refused for want of the Esc check")

        let tapRefused = BlockerRig()
        tapRefused.tap.refuses = true
        tapRefused.blocker.start(timed())
        XCTAssertEqual(tapRefused.displayWake.holdCalls, 0, "macOS refused the tap")
    }

    func testAnOKRefusalByMacOSDoesNotStopTheLock() {
        let rig = BlockerRig()
        rig.displayWake.refuses = true
        XCTAssertTrue(rig.blocker.start(timed()), "keeping the screen on is a courtesy, not a condition")
        XCTAssertTrue(rig.blocker.isActive)
        rig.blocker.stop(reason: .clicked)
        XCTAssertFalse(rig.blocker.isActive)
    }

    // MARK: Stored setting

    func testTheSettingIsOnByDefaultAndLoadsFromStorage() throws {
        let defaults = try TestDefaults.make(self)
        XCTAssertTrue(LockConfiguration.load(from: defaults).keepDisplayAwake)
        defaults.set(false, forKey: LockConfiguration.Key.keepDisplayAwake)
        XCTAssertFalse(LockConfiguration.load(from: defaults).keepDisplayAwake)
        defaults.set(true, forKey: LockConfiguration.Key.keepDisplayAwake)
        XCTAssertTrue(LockConfiguration.load(from: defaults).keepDisplayAwake)
    }

    func testTheBasicPresetKeepsTheSetting() {
        XCTAssertFalse(LockConfiguration(keepDisplayAwake: false).effective.keepDisplayAwake)
        XCTAssertTrue(LockConfiguration(keepDisplayAwake: true).effective.keepDisplayAwake)
        let advanced = LockConfiguration(mode: .advanced, keepDisplayAwake: false).effective
        XCTAssertFalse(advanced.keepDisplayAwake)
    }

    // MARK: The real assertion

    /// How many "prevent display sleep" assertions THIS process holds, as
    /// `pmset -g assertions` lists them per process. The system-wide flag
    /// would depend on whatever else the Mac is doing (a video playing in
    /// a browser holds the same assertion).
    private func ownDisplayAssertions() -> Int {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as NSDictionary?
        else { return -1 }
        let mine = byProcess[NSNumber(value: getpid())] as? [[String: Any]] ?? []
        return mine.filter {
            $0[kIOPMAssertionTypeKey as String] as? String == kIOPMAssertPreventUserIdleDisplaySleep as String
                && $0[kIOPMAssertionNameKey as String] as? String == "dirtymac is locking the keyboard"
        }.count
    }

    func testTheRealAssertionIsTakenAndGivenBack() {
        let wake = SystemDisplayWake()
        let before = ownDisplayAssertions()
        XCTAssertGreaterThanOrEqual(before, 0, "the assertion list could be read")
        XCTAssertTrue(wake.hold())
        XCTAssertTrue(wake.isHeld)
        XCTAssertEqual(ownDisplayAssertions(), before + 1, "macOS now keeps the display awake")
        XCTAssertTrue(wake.hold(), "holding twice is fine")
        XCTAssertEqual(ownDisplayAssertions(), before + 1, "and takes only one assertion")
        wake.release()
        XCTAssertFalse(wake.isHeld)
        XCTAssertEqual(ownDisplayAssertions(), before, "released: the display may sleep again")
        wake.release()   // nothing held: harmless
        XCTAssertEqual(ownDisplayAssertions(), before)
    }

    func testTheRealAssertionIsGivenBackWhenTheObjectGoesAway() {
        let before = ownDisplayAssertions()
        var wake: SystemDisplayWake? = SystemDisplayWake()
        wake?.hold()
        XCTAssertEqual(ownDisplayAssertions(), before + 1)
        wake = nil
        XCTAssertEqual(ownDisplayAssertions(), before, "a dropped holder cannot keep the display awake")
    }
}
