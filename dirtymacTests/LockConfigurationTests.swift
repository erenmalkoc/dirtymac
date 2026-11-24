import XCTest
@testable import dirtymac

final class LockConfigurationTests: XCTestCase {
    func testBasicModeIsAFixedSafePreset() {
        let c = LockConfiguration(
            mode: .basic,
            blockModifierKeys: false,
            blockMediaKeys: false,
            blockMouseAndTrackpad: true,
            autoUnlockSeconds: 60
        ).effective
        XCTAssertTrue(c.blockModifierKeys)
        XCTAssertTrue(c.blockMediaKeys)
        XCTAssertFalse(c.blockMouseAndTrackpad)
        // The timer is the user's own choice, not part of the preset.
        XCTAssertEqual(c.autoUnlockSeconds, 60)
    }

    func testBasicModeKeepsTheChosenTimerAndDropsOneThePickerDoesNotOffer() {
        for seconds in LockConfiguration.unlockChoices {
            XCTAssertEqual(LockConfiguration(mode: .basic, autoUnlockSeconds: seconds).effective.autoUnlockSeconds, seconds)
        }
        for odd in [-5, 7, 29, 86_401, 999_999] {
            XCTAssertEqual(LockConfiguration(mode: .basic, autoUnlockSeconds: odd).effective.autoUnlockSeconds, 0, "\(odd) s")
        }
        // A length entered by hand is any whole number of seconds from 30 to a day.
        for entered in [30, 45, 61, 4000, 5400, 86_400] {
            XCTAssertEqual(LockConfiguration.sanitizedAutoUnlock(entered), entered, "\(entered) s")
        }
        XCTAssertEqual(LockConfiguration.sanitizedAutoUnlock(86_401), 0)
    }

    func testABasicTimerIsLoadedFromStorageAndNeverNeedsTheEscCheck() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(LockMode.basic.rawValue, forKey: LockConfiguration.Key.mode)
        defaults.set(3600, forKey: LockConfiguration.Key.autoUnlockSeconds)
        let c = LockConfiguration.load(from: defaults)
        XCTAssertEqual(c.autoUnlockSeconds, 3600)
        XCTAssertFalse(c.blockMouseAndTrackpad)
        XCTAssertFalse(c.requiresEscCheck, "the mouse is free, clicking the icon always ends it")
    }

    func testMouseLockdownForcesTheMinimumAutoUnlock() {
        for seconds in [0, 10] {
            let c = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: seconds).effective
            XCTAssertEqual(c.autoUnlockSeconds, LockConfiguration.minMouseLockSeconds)
        }
        let longer = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 120).effective
        XCTAssertEqual(longer.autoUnlockSeconds, 120)
    }

    func testAdvancedWithoutMouseKeepsTimerOff() {
        let c = LockConfiguration(mode: .advanced, autoUnlockSeconds: 0).effective
        XCTAssertEqual(c.autoUnlockSeconds, 0)
    }

    // MARK: Picker and lock agree

    func testThePickerOffersTheMinimumForMouseLockdown() {
        XCTAssertTrue(LockConfiguration.unlockChoices.contains(LockConfiguration.minMouseLockSeconds))
        XCTAssertFalse(LockConfiguration.offeredChoices(mouseLocked: true).contains(0))
        XCTAssertEqual(LockConfiguration.offeredChoices(mouseLocked: false), LockConfiguration.unlockChoices)
    }

    /// The 1.2.0 bug class: the picker showing a value the lock overrides.
    func testEveryStoredValueClampsToAnOfferedChoice() {
        for mouseLocked in [false, true] {
            let offered = LockConfiguration.offeredChoices(mouseLocked: mouseLocked)
            for seconds in LockConfiguration.unlockChoices {
                let clamped = LockConfiguration.clampedSeconds(seconds, mouseLocked: mouseLocked)
                XCTAssertTrue(offered.contains(clamped), "\(seconds) s → \(clamped) s, mouse \(mouseLocked)")
            }
        }
    }

    // MARK: Loading stored settings

    func testNothingStoredLoadsTheBasicPreset() throws {
        let defaults = try TestDefaults.make(self)
        XCTAssertEqual(LockConfiguration.load(from: defaults), LockConfiguration().effective)
    }

    func testAnUnknownModeLoadsAsBasic() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set("garbage", forKey: LockConfiguration.Key.mode)
        defaults.set(true, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        let c = LockConfiguration.load(from: defaults)
        XCTAssertEqual(c.mode, .basic)
        XCTAssertFalse(c.blockMouseAndTrackpad)
    }

    func testStoredAdvancedSettingsLoadWithTheSafetyRules() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(LockMode.advanced.rawValue, forKey: LockConfiguration.Key.mode)
        defaults.set(false, forKey: LockConfiguration.Key.blockModifierKeys)
        defaults.set(false, forKey: LockConfiguration.Key.blockMediaKeys)
        defaults.set(true, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        defaults.set(0, forKey: LockConfiguration.Key.autoUnlockSeconds)
        let c = LockConfiguration.load(from: defaults)
        XCTAssertEqual(c.mode, .advanced)
        XCTAssertFalse(c.blockModifierKeys)
        XCTAssertFalse(c.blockMediaKeys)
        XCTAssertTrue(c.blockMouseAndTrackpad)
        XCTAssertEqual(c.autoUnlockSeconds, LockConfiguration.minMouseLockSeconds)
    }

    // MARK: Upgrading from 1.1.x

    func testMouseLockdownWithTimerOffIsRaisedToTheMinimum() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(true, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        defaults.set(0, forKey: LockConfiguration.Key.autoUnlockSeconds)
        LockConfiguration.normalizeStoredAutoUnlock(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: LockConfiguration.Key.autoUnlockSeconds), LockConfiguration.minMouseLockSeconds)
    }

    func testLongerTimersAndKeyboardOnlyLocksAreLeftAlone() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(true, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        defaults.set(120, forKey: LockConfiguration.Key.autoUnlockSeconds)
        LockConfiguration.normalizeStoredAutoUnlock(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: LockConfiguration.Key.autoUnlockSeconds), 120)

        defaults.set(false, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        defaults.set(0, forKey: LockConfiguration.Key.autoUnlockSeconds)
        LockConfiguration.normalizeStoredAutoUnlock(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: LockConfiguration.Key.autoUnlockSeconds), 0)
    }

    func testNormalizingAnEmptyStoreWritesNothing() throws {
        let defaults = try TestDefaults.make(self)
        LockConfiguration.normalizeStoredAutoUnlock(in: defaults)
        XCTAssertNil(defaults.object(forKey: LockConfiguration.Key.autoUnlockSeconds))
    }

    // MARK: Longer locks

    func testTheChoicesAreSortedUniqueAndStartAtOff() {
        let choices = LockConfiguration.unlockChoices
        XCTAssertEqual(choices.first, 0)
        XCTAssertEqual(choices, Array(Set(choices)).sorted())
        XCTAssertEqual(choices.last, 86_400, "a keyboard-only lock can last a day")
        XCTAssertEqual(choices.last, LockConfiguration.maxAutoUnlockSeconds)
        for choice in [3600, 7200, 14_400, 28_800, 43_200] {
            XCTAssertTrue(choices.contains(choice), "\(choice) s is offered")
        }
        for choice in [30, 60, 120, 300] {
            XCTAssertTrue(choices.contains(choice), "\(choice) s stays on offer")
        }
    }

    func testAFrozenMouseLockIsCappedAtFifteenMinutes() {
        XCTAssertEqual(LockConfiguration.maxMouseLockSeconds, 900)
        for seconds in [901, 1800, 3600, 86_400] {
            let c = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: seconds).effective
            XCTAssertEqual(c.autoUnlockSeconds, 900, "\(seconds) s")
        }
        let atTheCap = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 900).effective
        XCTAssertEqual(atTheCap.autoUnlockSeconds, 900)
    }

    func testAKeyboardOnlyLockKeepsItsFullLength() {
        for seconds in [0, 300, 900, 1800, 3600] {
            let c = LockConfiguration(mode: .advanced, autoUnlockSeconds: seconds).effective
            XCTAssertEqual(c.autoUnlockSeconds, seconds)
        }
    }

    func testThePickerOffersNothingAboveTheCapForAFrozenMouse() {
        let offered = LockConfiguration.offeredChoices(mouseLocked: true)
        XCTAssertEqual(offered.max(), 900)
        XCTAssertEqual(offered, [30, 60, 120, 300, 600, 900])
        XCTAssertEqual(LockConfiguration.offeredChoices(mouseLocked: false).max(), 86_400)
    }

    func testTurningTheMouseFreezeOnPullsALongTimerDownToTheCap() {
        // What the Settings toggle does through clampedSeconds.
        XCTAssertEqual(LockConfiguration.clampedSeconds(3600, mouseLocked: true), 900)
        XCTAssertEqual(LockConfiguration.clampedSeconds(3600, mouseLocked: false), 3600)
    }

    func testEveryChoiceAndEveryStoredValueEndsOnAnOfferedChoice() {
        for mouseLocked in [false, true] {
            let offered = LockConfiguration.offeredChoices(mouseLocked: mouseLocked)
            for seconds in [-5, 0, 1, 29, 31, 299, 301, 899, 901, 5000, 1_000_000] {
                let clamped = LockConfiguration.clampedSeconds(seconds, mouseLocked: mouseLocked)
                if mouseLocked {
                    XCTAssertTrue((30...900).contains(clamped), "\(seconds) → \(clamped)")
                } else {
                    XCTAssertEqual(clamped, seconds)
                }
            }
            XCTAssertFalse(offered.isEmpty)
        }
    }

    func testAStoredLongTimerLoadsClampedWhenTheMouseIsFrozen() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(LockMode.advanced.rawValue, forKey: LockConfiguration.Key.mode)
        defaults.set(true, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        defaults.set(3600, forKey: LockConfiguration.Key.autoUnlockSeconds)
        XCTAssertEqual(LockConfiguration.load(from: defaults).autoUnlockSeconds, 900)
    }

    func testNormalizingLowersATimerThatNowExceedsTheCap() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(true, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        defaults.set(3600, forKey: LockConfiguration.Key.autoUnlockSeconds)
        LockConfiguration.normalizeStoredAutoUnlock(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: LockConfiguration.Key.autoUnlockSeconds), 900)
    }

    func testTheDurationLabelsReadNaturallyInEveryLanguage() {
        for language in LanguagePreference.allCases where language != .system {
            let locale = Locale(identifier: language.rawValue)
            let titles = LockConfiguration.unlockChoices.filter { $0 > 0 }.map {
                LockConfiguration.unlockChoiceTitle($0, locale: locale)
            }
            XCTAssertEqual(Set(titles).count, titles.count, "\(language.rawValue): every choice reads differently")
            for title in titles { XCTAssertFalse(title.isEmpty, language.rawValue) }
        }
        let en = Locale(identifier: "en")
        XCTAssertEqual(LockConfiguration.unlockChoiceTitle(30, locale: en), "30 sec")
        XCTAssertEqual(LockConfiguration.unlockChoiceTitle(300, locale: en), "5 min")
        XCTAssertEqual(LockConfiguration.unlockChoiceTitle(3600, locale: en), "1 hr")
    }

    // MARK: When the Esc check is needed

    func testOnlyALongFrozenMouseLockNeedsTheEscCheck() {
        func needs(_ seconds: Int, mouse: Bool, mode: LockMode = .advanced) -> Bool {
            LockConfiguration(mode: mode, blockMouseAndTrackpad: mouse, autoUnlockSeconds: seconds).effective.requiresEscCheck
        }
        XCTAssertFalse(needs(30, mouse: true))
        XCTAssertFalse(needs(300, mouse: true), "exactly five minutes is still without the check")
        XCTAssertTrue(needs(301, mouse: true))
        XCTAssertTrue(needs(600, mouse: true))
        XCTAssertTrue(needs(900, mouse: true))
        XCTAssertTrue(needs(3600, mouse: true), "clamped to 15 minutes, which is above five")
        for seconds in [0, 300, 600, 3600] {
            XCTAssertFalse(needs(seconds, mouse: false), "the mouse is free: clicking the icon is the way out")
        }
        XCTAssertFalse(needs(900, mouse: true, mode: .basic), "Basic is a fixed preset")
    }
}
