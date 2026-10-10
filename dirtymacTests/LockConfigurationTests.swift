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
        XCTAssertEqual(c.autoUnlockSeconds, 0)
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
}
