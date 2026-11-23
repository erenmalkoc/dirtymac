import XCTest
@testable import dirtymac

/// The wait between the click on Lock and the lock.
@MainActor
final class StartDelayTests: XCTestCase {
    private func delayed(_ seconds: Int, mode: LockMode = .advanced, mouse: Bool = false, autoUnlock: Int = 0) -> LockConfiguration {
        LockConfiguration(
            mode: mode, blockMouseAndTrackpad: mouse, autoUnlockSeconds: autoUnlock, startDelaySeconds: seconds
        )
    }

    // MARK: The setting

    func testTheChoicesAreOffThenSortedAndShort() {
        let choices = LockConfiguration.startDelayChoices
        XCTAssertEqual(choices.first, 0)
        XCTAssertEqual(choices, choices.sorted())
        XCTAssertEqual(Set(choices).count, choices.count)
        XCTAssertLessThanOrEqual(choices.last ?? 0, 10, "a longer wait would only be in the way")
    }

    func testNoDelayByDefaultSoNothingChangesForExistingUsers() throws {
        XCTAssertEqual(LockConfiguration().startDelaySeconds, 0)
        XCTAssertEqual(LockConfiguration.load(from: try TestDefaults.make(self)).startDelaySeconds, 0)
    }

    func testOnlyAChoiceTheSettingsOfferIsKept() {
        for seconds in LockConfiguration.startDelayChoices {
            XCTAssertEqual(LockConfiguration.sanitizedStartDelay(seconds), seconds)
        }
        for odd in [-5, 1, 2, 4, 7, 11, 60, 1_000_000, Int.min, Int.max] {
            XCTAssertEqual(LockConfiguration.sanitizedStartDelay(odd), 0, "\(odd)")
        }
    }

    func testTheStoredDelayLoadsAndIsSanitisedOnTheWay() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(5, forKey: LockConfiguration.Key.startDelaySeconds)
        XCTAssertEqual(LockConfiguration.load(from: defaults).startDelaySeconds, 5)
        defaults.set(7, forKey: LockConfiguration.Key.startDelaySeconds)
        XCTAssertEqual(LockConfiguration.load(from: defaults).startDelaySeconds, 0)
    }

    func testBasicModeKeepsTheDelayToo() {
        XCTAssertEqual(delayed(5, mode: .basic).effective.startDelaySeconds, 5)
        XCTAssertEqual(delayed(5, mode: .advanced).effective.startDelaySeconds, 5)
        XCTAssertEqual(delayed(4, mode: .basic).effective.startDelaySeconds, 0)
    }

    // MARK: Counting down

    func testWithoutADelayTheLockStartsAtOnce() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(0))
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertNil(rig.blocker.lockCountdown)
    }

    func testADelayWaitsCountsDownAndThenLocks() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(3))
        XCTAssertFalse(rig.blocker.isActive, "nothing is blocked during the wait")
        XCTAssertEqual(rig.blocker.lockCountdown, 3)
        XCTAssertEqual(rig.tap.installCount, 0)

        rig.clock.advance(by: 1)
        XCTAssertEqual(rig.blocker.lockCountdown, 2)
        rig.clock.advance(by: 1)
        XCTAssertEqual(rig.blocker.lockCountdown, 1)
        XCTAssertFalse(rig.blocker.isActive)

        rig.clock.advance(by: 1)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertNil(rig.blocker.lockCountdown)
        XCTAssertEqual(rig.tap.installCount, 1)
    }

    func testTheLockThatFollowsIsTheOneThatWasAskedFor() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(3, autoUnlock: 120))
        rig.clock.advance(by: 3)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 120)
        XCTAssertTrue(rig.displayWake.isHeld)
        rig.clock.advance(by: 121)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .autoUnlock)
    }

    func testEachSecondOfTheWaitTicks() {
        let rig = BlockerRig()
        let before = rig.sounds.played.filter { $0 == .tick }.count
        rig.blocker.beginLock(delayed(5))
        rig.clock.advance(by: 4)
        XCTAssertEqual(rig.sounds.played.filter { $0 == .tick }.count - before, 5, "at the click and at each second until the last")
    }

    func testNoTimeIsLostAcrossTheWholeRange() {
        for seconds in LockConfiguration.startDelayChoices where seconds > 0 {
            let rig = BlockerRig()
            rig.blocker.beginLock(delayed(seconds))
            rig.clock.advance(by: Double(seconds) - 0.5)
            XCTAssertFalse(rig.blocker.isActive, "\(seconds) s: not yet")
            rig.clock.advance(by: 0.6)
            XCTAssertTrue(rig.blocker.isActive, "\(seconds) s: now")
        }
    }

    // MARK: Cancelling

    func testCancellingStopsTheWaitAndNothingLocksLater() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(5))
        rig.clock.advance(by: 2)
        rig.blocker.cancelPendingLock()
        XCTAssertNil(rig.blocker.lockCountdown)
        rig.clock.advance(by: 30)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.tap.installCount, 0)
        XCTAssertEqual(rig.clock.pendingCount, 0, "no timer is left behind")
        XCTAssertFalse(rig.displayWake.isHeld)
    }

    func testCancellingWithNothingPendingIsHarmless() {
        let rig = BlockerRig()
        rig.blocker.cancelPendingLock()
        rig.blocker.cancelPendingLock()
        XCTAssertNil(rig.blocker.lockCountdown)
        rig.blocker.beginLock(delayed(0))
        rig.blocker.cancelPendingLock()
        XCTAssertTrue(rig.blocker.isActive, "cancelling a wait never unlocks a running lock")
    }

    func testAQuitDuringTheWaitCancelsIt() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(5))
        rig.blocker.stop(reason: .quit)
        XCTAssertNil(rig.blocker.lockCountdown)
        rig.clock.advance(by: 30)
        XCTAssertFalse(rig.blocker.isActive)
    }

    func testAnImmediateStartOvertakesTheWait() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(10))
        rig.blocker.start(delayed(0))
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertNil(rig.blocker.lockCountdown)
        XCTAssertEqual(rig.tap.installCount, 1)
        rig.clock.advance(by: 30)
        XCTAssertEqual(rig.tap.installCount, 1, "the old wait must not start a second lock")
    }

    func testTheCancelledWaitCanBeStartedAgain() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(3))
        rig.blocker.cancelPendingLock()
        rig.blocker.beginLock(delayed(3))
        XCTAssertEqual(rig.blocker.lockCountdown, 3, "a fresh count, not a leftover")
        rig.clock.advance(by: 3)
        XCTAssertTrue(rig.blocker.isActive)
    }

    // MARK: Only one wait, only one lock

    func testAnotherClickDuringTheWaitDoesNotRestartIt() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(5))
        rig.clock.advance(by: 2)
        rig.blocker.beginLock(delayed(5))
        XCTAssertEqual(rig.blocker.lockCountdown, 3, "the running wait keeps counting")
    }

    func testBeginningWhileLockedChangesNothing() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(0, autoUnlock: 60))
        rig.blocker.beginLock(delayed(5, autoUnlock: 600))
        XCTAssertNil(rig.blocker.lockCountdown)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 60)
        XCTAssertEqual(rig.tap.installCount, 1)
    }

    // MARK: Refused at the click, not after the countdown

    func testWithoutPermissionThereIsNoCountdownAndThePromptComesAtOnce() {
        let rig = BlockerRig()
        rig.permission.trusted = false
        rig.blocker.beginLock(delayed(5))
        XCTAssertNil(rig.blocker.lockCountdown)
        XCTAssertEqual(rig.permission.requests, 1)
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    func testSecureInputRefusesAFullLockdownAtTheClick() {
        let rig = BlockerRig()
        rig.secureInput.enabled = true
        rig.blocker.beginLock(delayed(5, mouse: true, autoUnlock: 120))
        XCTAssertNil(rig.blocker.lockCountdown)
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    func testALongFrozenMouseLockWithoutTheEscCheckIsRefusedAtTheClick() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(5, mouse: true, autoUnlock: 900))
        XCTAssertNil(rig.blocker.lockCountdown)
        XCTAssertFalse(rig.blocker.isActive)
        let checked = BlockerRig()
        checked.blocker.beginLock(delayed(5, mouse: true, autoUnlock: 900), escVerified: true)
        XCTAssertEqual(checked.blocker.lockCountdown, 5)
        checked.clock.advance(by: 5)
        XCTAssertTrue(checked.blocker.isActive)
    }

    func testAFullLockdownAfterTheWaitStillEndsWithHoldEsc() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(3, mouse: true, autoUnlock: 120))
        rig.clock.advance(by: 3)
        XCTAssertTrue(rig.blocker.isActive)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3.2)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertFalse(rig.blocker.isActive)
    }

    // MARK: Things that change during the wait

    func testAPermissionTakenAwayDuringTheWaitMeansNoLock() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(3))
        rig.permission.trusted = false
        rig.clock.advance(by: 3)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertNil(rig.blocker.lockCountdown, "the wait is over, with no lock")
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    func testSecureInputTurnedOnDuringTheWaitRefusesAFullLockdown() {
        let rig = BlockerRig()
        rig.blocker.beginLock(delayed(3, mouse: true, autoUnlock: 120))
        rig.secureInput.enabled = true
        rig.clock.advance(by: 3)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertNil(rig.blocker.lockCountdown)
    }

    // MARK: The callers

    func testTheQuickLockMenuUsesTheWait() {
        let rig = BlockerRig()
        let stored = delayed(3)
        let quick = QuickLockController(blocker: rig.blocker, storedConfiguration: { stored }, openPanel: {})
        quick.run(seconds: 300)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lockCountdown, 3)
        rig.clock.advance(by: 3)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 300)
    }

    func testTheShortcutsActionUsesTheWait() {
        let rig = BlockerRig()
        LockKeyboardIntent.run(minutes: 5, blocker: rig.blocker, storedConfiguration: delayed(5), openPanel: {})
        XCTAssertEqual(rig.blocker.lockCountdown, 5)
        rig.clock.advance(by: 5)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 300)
    }

    func testTheShortcutsActionWithoutALengthUsesTheWaitToo() {
        let rig = BlockerRig()
        LockKeyboardIntent.run(minutes: nil, blocker: rig.blocker, storedConfiguration: delayed(3, autoUnlock: 120), openPanel: {})
        XCTAssertEqual(rig.blocker.lockCountdown, 3)
        rig.clock.advance(by: 3)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 120)
    }
}
