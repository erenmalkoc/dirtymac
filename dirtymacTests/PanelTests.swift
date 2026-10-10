import XCTest
import SwiftUI
@testable import dirtymac

/// Decisions the menu bar panel makes about what to show.
final class PanelTests: XCTestCase {
    func testARunningLockAlwaysShowsItsStopControl() {
        XCTAssertTrue(MainView.showsLockControl(isActive: true, hasPermission: false))
        XCTAssertTrue(MainView.showsLockControl(isActive: true, hasPermission: true))
        XCTAssertTrue(MainView.showsLockControl(isActive: false, hasPermission: true))
        XCTAssertFalse(MainView.showsLockControl(isActive: false, hasPermission: false))
    }

    func testOnlyLocksTheSystemEndedAreExplained() {
        let byUser: [UnlockReason] = [.clicked, .escHeld, .autoUnlock, .quit]
        let bySystem: [UnlockReason] = [.systemSleep, .screenLocked, .userSwitched, .systemSettings, .permissionRevoked]
        for reason in byUser { XCTAssertNil(reason.explanation, "\(reason)") }
        for reason in bySystem { XCTAssertNotNil(reason.explanation, "\(reason)") }
    }
}
