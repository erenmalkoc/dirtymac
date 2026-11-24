import XCTest
@testable import dirtymac

/// Timers up to a day, a length or a time of day entered by hand, and the confirmation
/// that long locks ask for.
final class LongTimerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    // MARK: Until a time of day

    func testATimeLaterTodayIsTheDifference() {
        let now = date("2026-11-24T10:00:00Z")
        XCTAssertEqual(LockConfiguration.secondsUntil(minutesOfDay: 17 * 60 + 30, from: now, calendar: calendar), 7 * 3600 + 30 * 60)
    }

    func testATimeThatAlreadyPassedMeansTomorrow() {
        let now = date("2026-11-24T18:00:00Z")
        XCTAssertEqual(LockConfiguration.secondsUntil(minutesOfDay: 17 * 60 + 30, from: now, calendar: calendar), 23 * 3600 + 30 * 60)
    }

    func testTheSameMinuteMeansTomorrowNotNow() {
        let now = date("2026-11-24T17:30:20Z")
        XCTAssertEqual(LockConfiguration.secondsUntil(minutesOfDay: 17 * 60 + 30, from: now, calendar: calendar), 24 * 3600 - 20)
        let exact = date("2026-11-24T17:30:00Z")
        XCTAssertEqual(LockConfiguration.secondsUntil(minutesOfDay: 17 * 60 + 30, from: exact, calendar: calendar), 24 * 3600, "exactly now is a full day away")
    }

    func testItIsNeverUnderThirtySecondsOrOverADay() {
        let almost = date("2026-11-24T17:29:50Z")
        XCTAssertEqual(LockConfiguration.secondsUntil(minutesOfDay: 17 * 60 + 30, from: almost, calendar: calendar), 30)
        for hour in 0..<24 {
            let s = LockConfiguration.secondsUntil(minutesOfDay: hour * 60, from: date("2026-11-24T12:34:56Z"), calendar: calendar)
            XCTAssertTrue((30...86_400).contains(s), "\(hour):00 → \(s)")
        }
    }

    func testOutOfRangeMinutesAreHeldInsideTheDay() {
        let now = date("2026-11-24T10:00:00Z")
        XCTAssertEqual(
            LockConfiguration.secondsUntil(minutesOfDay: 5000, from: now, calendar: calendar),
            LockConfiguration.secondsUntil(minutesOfDay: 23 * 60 + 59, from: now, calendar: calendar)
        )
        XCTAssertEqual(
            LockConfiguration.secondsUntil(minutesOfDay: -40, from: now, calendar: calendar),
            LockConfiguration.secondsUntil(minutesOfDay: 0, from: now, calendar: calendar)
        )
    }

    func testAClockChangeOfTheDayLightSavingKindStaysWithinADay() {
        var istanbul = Calendar(identifier: .gregorian)
        istanbul.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // The night the clocks go back (2026-10-25) has 25 hours.
        let now = date("2026-10-24T23:30:00Z")
        for minutes in [0, 120, 180, 600, 1439] {
            let s = LockConfiguration.secondsUntil(minutesOfDay: minutes, from: now, calendar: istanbul)
            XCTAssertTrue((30...86_400).contains(s), "\(minutes) → \(s)")
        }
    }

    func testTheLongDayWhenTheClocksGoBackNeverGivesMoreThanADay() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // 00:10 local on 2026-10-25, a 25 hour day: 00:05 tomorrow is 24 h 55 min away.
        let now = date("2026-10-24T22:10:00Z")
        let seconds = LockConfiguration.secondsUntil(minutesOfDay: 5, from: now, calendar: berlin)
        XCTAssertEqual(seconds, 86_400, "held at a day, not 89 700")
    }

    // MARK: effective

    func testTheClockTimeIsWorkedOutWhenTheEffectiveConfigurationIsAsked() {
        let config = LockConfiguration(mode: .basic, autoUnlockSeconds: 300, autoUnlockAtMinutes: 20 * 60)
        let morning = config.effective(now: date("2026-11-24T08:00:00Z"), calendar: calendar)
        XCTAssertEqual(morning.autoUnlockSeconds, 12 * 3600)
        let evening = config.effective(now: date("2026-11-24T19:00:00Z"), calendar: calendar)
        XCTAssertEqual(evening.autoUnlockSeconds, 3600)
        XCTAssertEqual(evening.autoUnlockAtMinutes, 20 * 60, "kept, so the length is worked out again when the lock starts")
    }

    func testTheClockTimeOverridesTheStoredLengthInBothModes() {
        for mode in [LockMode.basic, .advanced] {
            let c = LockConfiguration(mode: mode, autoUnlockSeconds: 60, autoUnlockAtMinutes: 12 * 60)
            XCTAssertEqual(c.effective(now: date("2026-11-24T10:00:00Z"), calendar: calendar).autoUnlockSeconds, 2 * 3600, "\(mode)")
        }
    }

    func testNoClockTimeLeavesTheLengthAlone() {
        let c = LockConfiguration(mode: .advanced, autoUnlockSeconds: 5400)
        XCTAssertEqual(c.effective.autoUnlockSeconds, 5400)
        XCTAssertNil(c.effective.autoUnlockAtMinutes)
    }

    func testAnAdvancedLengthIsHeldAtADay() {
        XCTAssertEqual(LockConfiguration(mode: .advanced, autoUnlockSeconds: 999_999).effective.autoUnlockSeconds, 86_400)
        XCTAssertEqual(LockConfiguration(mode: .advanced, autoUnlockSeconds: -3).effective.autoUnlockSeconds, 0)
    }

    // MARK: The frozen mouse

    func testAFrozenMouseNowAllowsUpToADayAndStillNeedsATimer() {
        let now = date("2026-11-24T10:00:00Z")
        let clock = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockAtMinutes: 23 * 60)
        XCTAssertEqual(clock.effective(now: now, calendar: calendar).autoUnlockSeconds, 13 * 3600, "no 15 minute cap any more")
        let length = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 28_800, autoUnlockCustom: true)
        XCTAssertEqual(length.effective.autoUnlockSeconds, 28_800)
        XCTAssertEqual(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 999_999).effective.autoUnlockSeconds, 86_400)
        // The timer is still mandatory: never off, never under 30 seconds.
        XCTAssertEqual(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 0).effective.autoUnlockSeconds, 30)
        XCTAssertEqual(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 10).effective.autoUnlockSeconds, 30)
        XCTAssertEqual(LockConfiguration.maxMouseLockSeconds, LockConfiguration.maxAutoUnlockSeconds)
    }

    func testALongFrozenLockStillNeedsTheEscCheckAndNeverTheLongLockOne() {
        let long = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 28_800).effective
        XCTAssertTrue(long.requiresEscCheck, "the way out is checked before any lock over five minutes")
        XCTAssertFalse(long.requiresLongLockConfirm, "a frozen mouse has its own, stronger confirmation")
        XCTAssertFalse(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 300).effective.requiresEscCheck)
    }

    func testTheFrozenMouseOffersEveryLengthButOff() {
        let offered = LockConfiguration.offeredChoices(mouseLocked: true)
        XCTAssertEqual(offered, LockConfiguration.unlockChoices.filter { $0 != 0 })
        XCTAssertEqual(offered.first, 30)
        XCTAssertEqual(offered.last, 86_400)
    }

    // MARK: The confirmation for long locks

    func testOnlyALockOverAnHourWithTheMouseFreeAsksForConfirmation() {
        func asks(_ seconds: Int, mouse: Bool = false, mode: LockMode = .advanced) -> Bool {
            LockConfiguration(mode: mode, blockMouseAndTrackpad: mouse, autoUnlockSeconds: seconds).effective.requiresLongLockConfirm
        }
        XCTAssertFalse(asks(0))
        XCTAssertFalse(asks(1800))
        XCTAssertFalse(asks(3600), "exactly an hour is still without")
        XCTAssertTrue(asks(3601))
        XCTAssertTrue(asks(7200))
        XCTAssertTrue(asks(86_400))
        XCTAssertFalse(asks(86_400, mouse: true), "a frozen mouse never lasts that long, and has its own confirmation")
        XCTAssertTrue(asks(7200, mode: .basic))
        XCTAssertEqual(LockConfiguration.longLockAboveSeconds, 3600)
    }

    func testAnUntilTimeCanNeedTheConfirmationToo() {
        let c = LockConfiguration(mode: .basic, autoUnlockAtMinutes: 23 * 60)
        XCTAssertTrue(c.effective(now: date("2026-11-24T08:00:00Z"), calendar: calendar).requiresLongLockConfirm)
        XCTAssertFalse(c.effective(now: date("2026-11-24T22:30:00Z"), calendar: calendar).requiresLongLockConfirm)
    }

    // MARK: Stored settings

    func testTheClockTimeAndTheCustomFlagLoadFromStorage() throws {
        let defaults = try TestDefaults.make(self)
        XCTAssertNil(LockConfiguration.load(from: defaults).autoUnlockAtMinutes)
        XCTAssertFalse(LockConfiguration.load(from: defaults).autoUnlockCustom)
        defaults.set(17 * 60 + 30, forKey: LockConfiguration.Key.autoUnlockAtMinutes)
        defaults.set(true, forKey: LockConfiguration.Key.autoUnlockCustom)
        let loaded = LockConfiguration.load(from: defaults)
        XCTAssertEqual(loaded.autoUnlockAtMinutes, 17 * 60 + 30)
        XCTAssertTrue(loaded.autoUnlockCustom)
        XCTAssertEqual(LockConfiguration.Key.autoUnlockAtMinutes, "autoUnlockAtMinutes")
    }

    func testANonsenseStoredClockTimeIsIgnored() throws {
        let defaults = try TestDefaults.make(self)
        for bad in [-1, 1440, 99_999] {
            defaults.set(bad, forKey: LockConfiguration.Key.autoUnlockAtMinutes)
            XCTAssertNil(LockConfiguration.load(from: defaults).autoUnlockAtMinutes, "\(bad)")
        }
    }

    // MARK: Shortcuts and the menu

    func testALengthAskedForReplacesAStoredClockTime() {
        let stored = LockConfiguration(mode: .basic, autoUnlockSeconds: 0, autoUnlockAtMinutes: 20 * 60, autoUnlockCustom: true)
        let quick = QuickLock.configuration(seconds: 600, storedConfiguration: stored)
        XCTAssertNil(quick.autoUnlockAtMinutes)
        XCTAssertFalse(quick.autoUnlockCustom)
        XCTAssertEqual(quick.autoUnlockSeconds, 600)
    }

    func testAShortcutWithoutALengthOpensThePanelWhenTheStoredTimerIsLong() {
        func plan(_ stored: LockConfiguration) -> IntentLockPlan {
            IntentLockPlan.plan(minutes: nil, isActive: false, hasPermission: true, secureInputOn: false, storedConfiguration: stored)
        }
        XCTAssertEqual(plan(LockConfiguration(mode: .basic, autoUnlockSeconds: 7200)), .openPanel)
        XCTAssertEqual(plan(LockConfiguration(mode: .basic, autoUnlockSeconds: 1800)), .lock(nil))
        XCTAssertEqual(plan(LockConfiguration(mode: .basic, autoUnlockSeconds: 3600)), .lock(nil))
    }

    func testAShortcutThatAsksForALongLengthLocksWithoutTheConfirmation() {
        let plan = IntentLockPlan.plan(
            minutes: 480, isActive: false, hasPermission: true, secureInputOn: false,
            storedConfiguration: LockConfiguration()
        )
        guard case .lock(let config?) = plan else { return XCTFail("should lock") }
        XCTAssertEqual(config.autoUnlockSeconds, 28_800)
    }
}
