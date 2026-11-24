import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// The auto-unlock choice, its entry box and the confirmation for long locks as drawn.
@MainActor
final class LongTimerUITests: XCTestCase {
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    private func panel(
        seconds: Int, atMinutes: Int? = nil, custom: Bool = false, confirmingLong: Bool = false,
        mode: LockMode = .basic, mouse: Bool = false, language: String = "en", settings: Bool = false
    ) throws -> NSHostingView<some View> {
        let defaults = try TestDefaults.make(self)
        defaults.set(mode.rawValue, forKey: LockConfiguration.Key.mode)
        defaults.set(seconds, forKey: LockConfiguration.Key.autoUnlockSeconds)
        defaults.set(atMinutes ?? -1, forKey: LockConfiguration.Key.autoUnlockAtMinutes)
        defaults.set(custom, forKey: LockConfiguration.Key.autoUnlockCustom)
        defaults.set(mouse, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        let rig = BlockerRig()
        return ViewHost.host(
            Group {
                if settings {
                    SettingsView(isPresented: .constant(true), maxContentHeight: 10_000)
                } else {
                    MainView(
                        showingSettings: .constant(false), confirmingLong: confirmingLong,
                        configuration: LockConfiguration(
                            mode: mode, blockMouseAndTrackpad: mouse, autoUnlockSeconds: seconds,
                            autoUnlockAtMinutes: atMinutes, autoUnlockCustom: custom
                        )
                    )
                }
            }
            .defaultAppStorage(defaults)
            .environmentObject(rig.blocker)
            .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
            .environment(\.locale, Locale(identifier: language))
        )
    }

    func testThePanelShowsThePickedLengthWithoutAnEntryBox() throws {
        let plain = try panel(seconds: 3600)
        let custom = try panel(seconds: 5400, custom: true)
        XCTAssertGreaterThan(custom.frame.height, plain.frame.height + 20, "the entry box adds a row or two")
        ViewHost.snapshot(plain, named: "timer-panel-1h")
        ViewHost.snapshot(custom, named: "timer-panel-custom-for")
    }

    func testAnUntilTimeShowsItsOwnBox() throws {
        let until = try panel(seconds: 3600, atMinutes: 23 * 60 + 30, custom: true)
        ViewHost.snapshot(until, named: "timer-panel-custom-until")
        let forLength = try panel(seconds: 3600, custom: true)
        XCTAssertGreaterThan(until.frame.height, 0)
        XCTAssertGreaterThan(forLength.frame.height, 0)
    }

    func testAFrozenMouseHasNoEntryBox() throws {
        let frozen = try panel(seconds: 420, custom: true, mode: .advanced, mouse: true)
        let plain = try panel(seconds: 300, mode: .advanced, mouse: true)
        XCTAssertEqual(frozen.frame.height, plain.frame.height, accuracy: 0.5, "no box, whatever was entered before")
    }

    func testTheLongLockConfirmationFitsInEveryLanguage() throws {
        var tallest: (String, CGFloat) = ("", 0)
        for language in languages {
            let view = try panel(seconds: 28_800, confirmingLong: true, language: language)
            if view.frame.height > tallest.1 { tallest = (language, view.frame.height) }
            ViewHost.snapshot(view, named: "timer-long-confirm-\(language)")
        }
        print("tallest long-lock confirmation: \(tallest.0) \(tallest.1) pt")
        XCTAssertLessThan(tallest.1, 700, "Long lock confirmation in \(tallest.0) is \(tallest.1) pt tall")
    }

    func testSettingsShowTheControlInBothModesInEveryLanguage() throws {
        for language in languages {
            for mode in [LockMode.basic, .advanced] {
                let view = try panel(seconds: 86_400, mode: mode, language: language, settings: true)
                XCTAssertGreaterThan(view.frame.height, 300, "\(language) \(mode)")
            }
        }
        ViewHost.snapshot(try panel(seconds: 5400, custom: true, settings: true), named: "timer-settings-basic-custom")
    }

    func testThePowerButtonAsksBeforeALongLockAndNotBefore() {
        func tap(longLock: Bool, mouse: Bool = false) -> MainView.PowerTapAction {
            MainView.powerTapAction(isActive: false, isWaiting: false, mouseLocked: mouse, longLock: longLock)
        }
        XCTAssertEqual(tap(longLock: true), .confirmLongLock)
        XCTAssertEqual(tap(longLock: false), .beginLock)
        XCTAssertEqual(tap(longLock: true, mouse: true), .confirmLockdown, "the frozen mouse has its own confirmation")
        XCTAssertEqual(MainView.powerTapAction(isActive: true, isWaiting: false, mouseLocked: false, longLock: true), .stop, "an unlock never asks")
        XCTAssertEqual(MainView.powerTapAction(isActive: false, isWaiting: true, mouseLocked: false, longLock: true), .cancelWait)
    }
}

/// The rules of the entry box, apart from drawing it.
@MainActor
final class AutoUnlockEntryTests: XCTestCase {
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    func testAPickedLengthIsItsOwnSelection() {
        for s in LockConfiguration.unlockChoices {
            XCTAssertEqual(AutoUnlockEntry(seconds: s, atMinutes: nil, custom: false).selection(mouseFrozen: false), s)
        }
    }

    func testACustomFlagAnUntilTimeOrAnUnofferedLengthSelectCustom() {
        XCTAssertEqual(AutoUnlockEntry(seconds: 3600, atMinutes: nil, custom: true).selection(mouseFrozen: false), AutoUnlockEntry.customTag)
        XCTAssertEqual(AutoUnlockEntry(seconds: 3600, atMinutes: 600, custom: false).selection(mouseFrozen: false), AutoUnlockEntry.customTag)
        XCTAssertEqual(AutoUnlockEntry(seconds: 5400, atMinutes: nil, custom: false).selection(mouseFrozen: false), AutoUnlockEntry.customTag)
    }

    func testAFrozenMouseSelectsTheLengthTheLockWillUse() {
        let offered = LockConfiguration.offeredChoices(mouseLocked: true)
        for seconds in [0, 10, 420, 3600, 86_400] {
            let tag = AutoUnlockEntry(seconds: seconds, atMinutes: nil, custom: true).selection(mouseFrozen: true)
            XCTAssertTrue(offered.contains(tag), "\(seconds) s → \(tag)")
        }
    }

    func testPickingALengthEndsAnyEntry() {
        let entry = AutoUnlockEntry(seconds: 5400, atMinutes: 600, custom: true).choosing(7200)
        XCTAssertEqual(entry, AutoUnlockEntry(seconds: 7200, atMinutes: nil, custom: false))
        XCTAssertEqual(AutoUnlockEntry(seconds: 5400, atMinutes: 600, custom: true).choosing(0).seconds, 0)
    }

    func testChoosingCustomKeepsTheLengthOrStartsAtAnHour() {
        let kept = AutoUnlockEntry(seconds: 14_400, atMinutes: nil, custom: false).choosing(AutoUnlockEntry.customTag)
        XCTAssertEqual(kept, AutoUnlockEntry(seconds: 14_400, atMinutes: nil, custom: true))
        let fromOff = AutoUnlockEntry(seconds: 0, atMinutes: nil, custom: false).choosing(AutoUnlockEntry.customTag)
        XCTAssertEqual(fromOff.seconds, 3600)
        XCTAssertTrue(fromOff.custom)
        let clock = AutoUnlockEntry(seconds: 0, atMinutes: 900, custom: true).choosing(AutoUnlockEntry.customTag)
        XCTAssertEqual(clock.atMinutes, 900, "an until time stays")
        XCTAssertEqual(clock.seconds, 0)
    }

    func testHoursAndMinutesRoundTripAndStayInRange() {
        XCTAssertEqual(AutoUnlockEntry.length(hours: 3, minutes: 15), 3 * 3600 + 15 * 60)
        XCTAssertEqual(AutoUnlockEntry.length(hours: 0, minutes: 0), 60, "never under a minute")
        XCTAssertEqual(AutoUnlockEntry.length(hours: 24, minutes: 30), 86_400, "a day has no minutes on top")
        XCTAssertEqual(AutoUnlockEntry.length(hours: 99, minutes: 99), 86_400)
        XCTAssertEqual(AutoUnlockEntry.length(hours: -3, minutes: -9), 60)
        XCTAssertEqual(AutoUnlockEntry.length(hours: 1, minutes: 75), 3600 + 59 * 60)
        XCTAssertTrue(AutoUnlockEntry.hoursAndMinutes(of: 5400) == (1, 30))
        XCTAssertTrue(AutoUnlockEntry.hoursAndMinutes(of: 86_400) == (24, 0))
        XCTAssertTrue(AutoUnlockEntry.hoursAndMinutes(of: 999_999) == (24, 0))
    }

    func testSwitchingToUntilGivesTheTimeTheLengthEndsAt() {
        let now = date("2026-11-24T10:10:00Z")
        let entry = AutoUnlockEntry(seconds: 3 * 3600, atMinutes: nil, custom: true).switchedToClock(now: now, calendar: utc)
        XCTAssertEqual(entry.atMinutes, 13 * 60 + 10)
        XCTAssertTrue(entry.custom)
    }

    func testSwitchingToForGivesTheLengthUntilTheTime() {
        let now = date("2026-11-24T10:10:00Z")
        let entry = AutoUnlockEntry(seconds: 0, atMinutes: 13 * 60 + 10, custom: true).switchedToLength(now: now, calendar: utc)
        XCTAssertNil(entry.atMinutes)
        XCTAssertEqual(entry.seconds, 3 * 3600)
        let past = AutoUnlockEntry(seconds: 0, atMinutes: 9 * 60, custom: true).switchedToLength(now: now, calendar: utc)
        XCTAssertEqual(past.seconds, 22 * 3600 + 50 * 60, "a time that passed is tomorrow's")
    }

    func testTheEndOfALockIsTheStartPlusItsLengthOrTheNextTime() {
        let now = date("2026-11-24T10:00:00Z")
        XCTAssertEqual(AutoUnlockEntry(seconds: 7200, atMinutes: nil, custom: false).unlockDate(now: now, calendar: utc), date("2026-11-24T12:00:00Z"))
        XCTAssertEqual(AutoUnlockEntry(seconds: 0, atMinutes: 23 * 60 + 30, custom: true).unlockDate(now: now, calendar: utc), date("2026-11-24T23:30:00Z"))
        XCTAssertEqual(AutoUnlockEntry(seconds: 0, atMinutes: 7 * 60, custom: true).unlockDate(now: now, calendar: utc), date("2026-11-25T07:00:00Z"))
        XCTAssertNil(AutoUnlockEntry(seconds: 0, atMinutes: nil, custom: false).unlockDate(now: now, calendar: utc))
    }

    func testTheEndShowsTheDayOnlyWhenItIsNotToday() {
        let now = date("2026-11-24T10:00:00Z")
        let en = Locale(identifier: "en_US")
        let today = AutoUnlockEntry.endTitle(date("2026-11-24T23:30:00Z"), now: now, locale: en, calendar: utc)
        XCTAssertTrue(today.contains("11:30"), today)
        XCTAssertFalse(today.contains("Tue"), today)
        let tomorrow = AutoUnlockEntry.endTitle(date("2026-11-25T07:00:00Z"), now: now, locale: en, calendar: utc)
        XCTAssertTrue(tomorrow.contains("Wed"), tomorrow)
        XCTAssertTrue(tomorrow.contains("7:00"), tomorrow)
    }
}
