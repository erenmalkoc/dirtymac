import XCTest
@testable import dirtymac

/// The countdown the panel and the menu bar show while Esc is held,
/// driven by the hand-set clock of the blocker tests.
@MainActor
final class EscCountdownTests: XCTestCase {
    private let basic = LockConfiguration()

    private func locked(_ configuration: LockConfiguration? = nil, seconds: Int = 0) -> BlockerRig {
        let rig = BlockerRig()
        rig.blocker.start(configuration ?? LockConfiguration(mode: .advanced, autoUnlockSeconds: seconds))
        return rig
    }

    private func remaining(_ rig: BlockerRig) -> Int? {
        if case .holding(let remaining, _) = rig.blocker.escHold { return remaining }
        return nil
    }

    private func progress(_ rig: BlockerRig) -> Double? {
        if case .holding(_, let progress) = rig.blocker.escHold { return progress }
        return nil
    }

    // MARK: The seconds shown

    func testWholeSecondsCountDownFromThreeAndNeverShowZeroWhileHolding() {
        let total = KeyboardBlocker.escHoldDuration
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 0, total: total), 3)
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 0.01, total: total), 3)
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 0.99, total: total), 3)
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 1.01, total: total), 2)
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 1.99, total: total), 2)
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 2.01, total: total), 1)
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 2.99, total: total), 1)
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 3, total: total), 1, "zero belongs to the let-go state")
        XCTAssertEqual(EscHoldState.remainingSeconds(held: 9, total: total), 1)
    }

    func testAClockThatWentBackNeverShowsMoreThanTheFullHold() {
        XCTAssertEqual(EscHoldState.remainingSeconds(held: -5, total: 3), 3)
    }

    // MARK: Running through a hold

    func testNothingIsHeldBeforeEscGoesDown() {
        let rig = locked()
        XCTAssertEqual(rig.blocker.escHold, .idle)
        rig.clock.advance(by: 5)
        XCTAssertEqual(rig.blocker.escHold, .idle)
    }

    func testTheCountdownStartsAtThreeTheMomentEscGoesDown() {
        let rig = locked()
        rig.tap.send(.escDown)
        XCTAssertEqual(rig.blocker.escHold, .holding(remaining: 3, progress: 0))
    }

    func testTheCountdownFollowsTheClockToTheLetGoState() {
        let rig = locked()
        rig.tap.send(.escDown)

        rig.clock.advance(by: 0.5)
        XCTAssertEqual(remaining(rig), 3)
        XCTAssertEqual(try XCTUnwrap(progress(rig)), 0.5 / 3, accuracy: 0.03)

        rig.clock.advance(by: 1)   // 1.5 s
        XCTAssertEqual(remaining(rig), 2)
        XCTAssertEqual(try XCTUnwrap(progress(rig)), 0.5, accuracy: 0.03)

        rig.clock.advance(by: 1)   // 2.5 s
        XCTAssertEqual(remaining(rig), 1)
        XCTAssertEqual(try XCTUnwrap(progress(rig)), 2.5 / 3, accuracy: 0.03)

        rig.clock.advance(by: 0.6) // past 3 s
        XCTAssertEqual(rig.blocker.escHold, .letGo)
        XCTAssertTrue(rig.blocker.isActive, "the lock waits for the release")
    }

    func testTheProgressNeverGoesBackwardsWhileHolding() {
        let rig = locked()
        rig.tap.send(.escDown)
        var last = 0.0
        for _ in 0..<26 {
            rig.clock.advance(by: 0.1)
            guard let current = progress(rig) else { break }
            XCTAssertGreaterThanOrEqual(current, last)
            XCTAssertLessThanOrEqual(current, 1)
            last = current
        }
    }

    func testLettingGoEarlyClearsTheCountdownAndTheLockStays() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1.5)
        XCTAssertEqual(remaining(rig), 2)
        rig.tap.send(.escUp)
        XCTAssertEqual(rig.blocker.escHold, .idle)
        XCTAssertTrue(rig.blocker.isActive)
        rig.clock.advance(by: 5)
        XCTAssertEqual(rig.blocker.escHold, .idle, "nothing keeps counting after the release")
    }

    func testAutoRepeatDoesNotRestartTheCountdown() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1.5)
        rig.tap.send(.escDown)   // the key repeats
        rig.clock.advance(by: 0.1)
        XCTAssertEqual(remaining(rig), 2, "still the same hold, not back at 3")
    }

    func testAPressAfterAnEarlyReleaseStartsFromThreeAgain() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 2)
        rig.tap.send(.escUp)
        rig.tap.send(.escDown)
        XCTAssertEqual(rig.blocker.escHold, .holding(remaining: 3, progress: 0))
    }

    // MARK: Finishing

    func testReleasingAfterTheHoldUnlocksAndClearsTheCountdown() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3.2)
        XCTAssertEqual(rig.blocker.escHold, .letGo)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .escHeld)
        XCTAssertEqual(rig.blocker.escHold, .idle)
    }

    func testNotReleasingStillEndsTheLockAfterTheGraceAndClearsTheCountdown() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3.2)
        rig.clock.advance(by: KeyboardBlocker.escReleaseGrace + 0.1)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.escHold, .idle)
    }

    func testAnyOtherEndOfTheLockClearsTheCountdownToo() {
        // The timer ends it while Esc is still going down.
        let timed = locked(seconds: 30)
        timed.tap.send(.escDown)
        timed.clock.advance(by: 1.5)
        XCTAssertNotNil(remaining(timed))
        timed.clock.advance(by: 30)
        XCTAssertFalse(timed.blocker.isActive)
        XCTAssertEqual(timed.blocker.escHold, .idle)

        // A click on the power button, and a quit, end it the same way.
        for reason in [UnlockReason.clicked, .quit, .systemSleep, .screenLocked] {
            let rig = locked()
            rig.tap.send(.escDown)
            rig.clock.advance(by: 1.5)
            rig.blocker.stop(reason: reason)
            XCTAssertEqual(rig.blocker.escHold, .idle, "\(reason)")
        }
    }

    func testANewLockStartsWithoutACountdown() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1.5)
        rig.blocker.stop(reason: .clicked)
        rig.blocker.start(LockConfiguration())
        XCTAssertEqual(rig.blocker.escHold, .idle)
    }

    // MARK: No timer is left behind

    func testNoTimerOutlivesAHoldThatEndedEarly() {
        let rig = locked()
        let before = rig.clock.pendingCount
        rig.tap.send(.escDown)
        XCTAssertGreaterThan(rig.clock.pendingCount, before)
        rig.tap.send(.escUp)
        XCTAssertEqual(rig.clock.pendingCount, before, "the countdown timer is cancelled with the hold")
    }

    func testNoTimerOutlivesALockThatEndedMidHold() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1)
        rig.blocker.stop(reason: .clicked)
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    func testNoTimerOutlivesAFinishedHold() {
        let rig = locked()
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3.2)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    // MARK: It works the same in a frozen-mouse lock

    func testTheCountdownRunsInAFullLockdownToo() {
        let rig = locked(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 300))
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1.5)
        XCTAssertEqual(remaining(rig), 2)
    }
}
