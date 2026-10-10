import XCTest
@testable import dirtymac

/// Every way into and out of a lock, run against a fake tap and a
/// hand-driven clock. The real tap needs an Accessibility permission CI
/// cannot grant, so this is where the exits are proven on each build.
final class KeyboardBlockerTests: XCTestCase {
    private let basic = LockConfiguration()

    private func timed(_ seconds: Int) -> LockConfiguration {
        LockConfiguration(mode: .advanced, autoUnlockSeconds: seconds)
    }

    private func fullLockdown(_ seconds: Int = 0) -> LockConfiguration {
        LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: seconds)
    }

    /// Holds Esc for the full duration and lets go.
    private func holdEsc(_ rig: BlockerRig) {
        rig.tap.send(.escDown)
        rig.clock.advance(by: KeyboardBlocker.escHoldDuration)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
    }

    // MARK: Starting

    func testLocksWithTheMaskOfTheConfiguration() {
        let rig = BlockerRig()
        XCTAssertTrue(rig.blocker.start(basic))
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.tap.installedMask, EventMask.build(for: basic.effective))
        XCTAssertNil(rig.blocker.lastUnlockReason)
    }

    func testWithoutPermissionItAsksAndStaysUnlocked() {
        let rig = BlockerRig()
        rig.permission.trusted = false
        XCTAssertFalse(rig.blocker.start(basic))
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertFalse(rig.blocker.hasPermission)
        XCTAssertEqual(rig.permission.requests, 1)
        XCTAssertEqual(rig.tap.installCount, 0)
    }

    func testARefusedTapLeavesTheKeyboardUnlocked() {
        let rig = BlockerRig()
        rig.tap.refuses = true
        XCTAssertFalse(rig.blocker.start(basic))
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertFalse(rig.blocker.hasPermission)
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    func testStartingTwiceInstallsOneTap() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        XCTAssertTrue(rig.blocker.start(basic))
        XCTAssertEqual(rig.tap.installCount, 1)
    }

    // MARK: Hold Esc

    func testHoldingEscForThreeSecondsUnlocksWhenEscComesUp() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 2.9)
        XCTAssertTrue(rig.blocker.isActive)
        rig.clock.advance(by: 0.1)
        // Held long enough, but Esc is still down: keep swallowing it so
        // its auto-repeat never reaches the frontmost app.
        XCTAssertTrue(rig.blocker.isActive)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .escHeld)
        XCTAssertEqual(rig.tap.uninstallCount, 1)
    }

    func testTheUnlockWaitsForTheTapCallbackToReturn() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3)
        rig.tap.send(.escUp)
        // Still inside the callback for that key-up: no teardown yet.
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.tap.uninstallCount, 0)
        rig.clock.advance(by: 0)
        XCTAssertFalse(rig.blocker.isActive)
    }

    func testAStuckEscStillUnlocksAfterTheGracePeriod() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3)
        rig.clock.advance(by: KeyboardBlocker.escReleaseGrace - 0.1)
        XCTAssertTrue(rig.blocker.isActive)
        rig.clock.advance(by: 0.1)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .escHeld)
    }

    func testAutoRepeatAfterTheHoldDoesNotPostponeTheUnlock() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3)
        rig.tap.send(.escDown)   // auto-repeat
        rig.clock.advance(by: 1)
        rig.tap.send(.escDown)   // auto-repeat
        rig.clock.advance(by: KeyboardBlocker.escReleaseGrace - 1)
        XCTAssertFalse(rig.blocker.isActive)
    }

    func testReleasingEscEarlyKeepsTheLock() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 2.9)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 10)
        XCTAssertTrue(rig.blocker.isActive)
    }

    func testEscAutoRepeatDoesNotRestartTheHold() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1)
        rig.tap.send(.escDown)   // auto-repeat
        rig.clock.advance(by: 1)
        rig.tap.send(.escDown)   // auto-repeat
        rig.clock.advance(by: 1)
        // Complete 3 s after the first press, not after the repeats.
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .escHeld)
    }

    func testAFreshPressAfterReleasingStartsANewHold() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 2)
        rig.tap.send(.escUp)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 2.9)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertTrue(rig.blocker.isActive)

        holdEsc(rig)
        XCTAssertFalse(rig.blocker.isActive)
    }

    func testHoldingEscUnlocksFullLockdown() {
        let rig = BlockerRig()
        rig.blocker.start(fullLockdown(300))
        holdEsc(rig)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .escHeld)
    }

    // MARK: Auto-unlock

    func testAutoUnlockFiresAtTheConfiguredSecond() {
        let rig = BlockerRig()
        rig.blocker.start(timed(60))
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 60)
        rig.clock.advance(by: 59)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.elapsed, 59, accuracy: 0.001)
        XCTAssertEqual(rig.blocker.autoUnlockRemaining, 1)
        rig.clock.advance(by: 1)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .autoUnlock)
    }

    func testFullLockdownNeverRunsWithoutATimer() {
        let rig = BlockerRig()
        rig.blocker.start(fullLockdown(0))
        XCTAssertEqual(rig.blocker.autoUnlockTotal, LockConfiguration.minMouseLockSeconds)
        rig.clock.advance(by: TimeInterval(LockConfiguration.minMouseLockSeconds))
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .autoUnlock)
    }

    func testBasicModeHasNoTimer() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        XCTAssertFalse(rig.blocker.hasAutoUnlock)
        rig.clock.advance(by: 3600)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.elapsedDisplay, "60:00")
    }

    func testAnOverdueDeadlineUnlocksOnTheFirstTickAfterWaking() {
        let rig = BlockerRig()
        rig.blocker.start(timed(60))
        rig.clock.advance(by: 10)
        rig.clock.jump(by: 3600)        // asleep: no timer ran
        rig.clock.advance(by: 0.5)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .autoUnlock)
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    func testElapsedTimeIncludesTimeAsleep() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.clock.jump(by: 3600)
        rig.clock.advance(by: 1)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.elapsedDisplay, "60:01")
    }

    func testDisplaysFollowTheClock() {
        let rig = BlockerRig()
        rig.blocker.start(timed(120))
        rig.clock.advance(by: 30)
        XCTAssertEqual(rig.blocker.elapsedDisplay, "00:30")
        XCTAssertEqual(rig.blocker.autoUnlockRemainingDisplay, "01:30")
    }

    // MARK: Stopping

    func testClickAndQuitRecordTheirReason() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.blocker.stop(reason: .clicked)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .clicked)

        rig.blocker.start(basic)
        XCTAssertNil(rig.blocker.lastUnlockReason)
        rig.blocker.stop(reason: .quit)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .quit)
    }

    func testStoppingClearsTheSessionAndRemovesTheTapOnce() {
        let rig = BlockerRig()
        rig.blocker.start(timed(60))
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1)
        rig.blocker.stop(reason: .clicked)
        rig.blocker.stop(reason: .clicked)

        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertFalse(rig.tap.isInstalled)
        XCTAssertEqual(rig.tap.uninstallCount, 1)
        XCTAssertEqual(rig.clock.pendingCount, 0, "a timer survived the unlock")
        XCTAssertEqual(rig.blocker.elapsed, 0)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 0)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .clicked)
    }

    func testRevokingThePermissionEndsTheLockOnTheNextTick() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.permission.trusted = false
        rig.clock.advance(by: 1)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertFalse(rig.blocker.hasPermission)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .permissionRevoked)
        XCTAssertEqual(rig.tap.uninstallCount, 1)
    }

    func testStoppingDuringTheReleaseGraceCancelsIt() {
        let rig = BlockerRig()
        rig.blocker.start(basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3)
        rig.blocker.stop(reason: .clicked)
        rig.clock.advance(by: 5)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .clicked)
        XCTAssertEqual(rig.clock.pendingCount, 0)
        XCTAssertEqual(rig.tap.uninstallCount, 1)
    }
}
