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
}
