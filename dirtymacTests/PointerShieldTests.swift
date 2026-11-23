import XCTest
import AppKit
@testable import dirtymac

/// The cover over the screens that takes the scrolling the event taps
/// cannot see on macOS 27.
@MainActor
final class PointerShieldTests: XCTestCase {
    // MARK: Geometry

    func testTheCoverStopsBelowTheMenuBar() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = NSRect(x: 0, y: 80, width: 1512, height: 869) // Dock below, menu bar above
        let frame = ShieldGeometry.frame(screenFrame: screen, visibleFrame: visible, menuBarThickness: 24)
        XCTAssertEqual(frame, NSRect(x: 0, y: 0, width: 1512, height: 982 - 33))
        XCTAssertEqual(frame.minY, 0, "it covers the Dock too")
    }

    func testAMenuBarThatHidesStillLeavesRoomForIt() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = ShieldGeometry.frame(screenFrame: screen, visibleFrame: screen, menuBarThickness: 24)
        XCTAssertEqual(frame.height, 1080 - 24)
    }

    func testASecondScreenKeepsItsOrigin() {
        let screen = NSRect(x: 1512, y: -170, width: 2048, height: 1152)
        let frame = ShieldGeometry.frame(screenFrame: screen, visibleFrame: screen, menuBarThickness: 24)
        XCTAssertEqual(frame.origin, screen.origin)
        XCTAssertEqual(frame.width, 2048)
    }

    func testNeverANegativeHeight() {
        let screen = NSRect(x: 0, y: 0, width: 100, height: 10)
        XCTAssertEqual(ShieldGeometry.frame(screenFrame: screen, visibleFrame: screen, menuBarThickness: 24).height, 0)
    }

    func testTheLevelIsJustBelowTheMenuBarAndAboveTheDock() {
        XCTAssertEqual(ShieldGeometry.level.rawValue, Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        XCTAssertGreaterThan(ShieldGeometry.level.rawValue, Int(CGWindowLevelForKey(.dockWindow)))
        XCTAssertLessThan(ShieldGeometry.level.rawValue, Int(CGWindowLevelForKey(.statusWindow)), "the menu bar icon stays above it")
        XCTAssertLessThan(ShieldGeometry.level.rawValue, NSWindow.Level.popUpMenu.rawValue, "so does the panel")
    }

    // MARK: The windows

    func testShowCoversEveryScreenAndHideRemovesIt() {
        let shield = ScreenShield()
        defer { shield.hide() }
        XCTAssertTrue(shield.windows.isEmpty)
        shield.show()
        XCTAssertEqual(shield.windows.count, NSScreen.screens.count)
        for window in shield.windows {
            XCTAssertEqual(window.level, ShieldGeometry.level)
            XCTAssertFalse(window.ignoresMouseEvents)
            XCTAssertFalse(window.canBecomeKey)
            XCTAssertFalse(window.canBecomeMain)
            XCTAssertFalse(window.isOpaque)
            XCTAssertTrue(window.contentView is ShieldView)
            XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
            XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
            XCTAssertFalse(window.hasShadow)
        }
        shield.hide()
        XCTAssertTrue(shield.windows.isEmpty)
    }

    func testTheCoverIsNotFullyClear() {
        // A window with nothing drawn lets the events through.
        XCTAssertGreaterThan(ScreenShield.tint.alphaComponent, 0)
        XCTAssertLessThanOrEqual(ScreenShield.tint.alphaComponent, 0.02, "and still cannot be seen")
    }

    func testShowingAgainStartsOverInsteadOfStacking() {
        let shield = ScreenShield()
        defer { shield.hide() }
        shield.show()
        shield.show()
        XCTAssertEqual(shield.windows.count, NSScreen.screens.count)
    }

    func testHidingWhenNothingIsShownIsHarmless() {
        let shield = ScreenShield()
        shield.hide()
        shield.hide()
        XCTAssertTrue(shield.windows.isEmpty)
    }

    func testTheCoverFollowsAChangeOfScreens() {
        let shield = ScreenShield()
        defer { shield.hide() }
        shield.show()
        let before = shield.windows
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(shield.windows.count, NSScreen.screens.count)
        XCTAssertFalse(zip(before, shield.windows).contains { $0 === $1 }, "rebuilt for the new screens")
    }

    func testTheViewTakesEveryPointerEventAndPassesNoneOn() throws {
        let view = ShieldView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        XCTAssertFalse(view.acceptsFirstResponder)
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        // Handled here, not forwarded up the responder chain to an app.
        view.mouseDown(with: down)
        view.scrollWheel(with: down)
        view.rightMouseDown(with: down)
        view.magnify(with: down)
    }

    // MARK: Our window, but not the cover

    func testTheCoverIsNotACLickOnDirtymac() {
        let layer = Int(ShieldGeometry.level.rawValue)
        XCTAssertFalse(OwnWindowHitTest.isOwn((owner: 10, layer: layer), pid: 10, shieldLayer: layer))
        XCTAssertTrue(OwnWindowHitTest.isOwn((owner: 10, layer: 25), pid: 10, shieldLayer: layer), "the menu bar icon")
        XCTAssertTrue(OwnWindowHitTest.isOwn((owner: 10, layer: 101), pid: 10, shieldLayer: layer), "the panel")
        XCTAssertFalse(OwnWindowHitTest.isOwn((owner: 20, layer: 25), pid: 10, shieldLayer: layer), "someone else's")
    }

    func testTheFrontmostWindowReportsItsLevel() {
        func window(pid: Int32, layer: Int) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: NSNumber(value: pid),
                kCGWindowLayer as String: NSNumber(value: layer),
                kCGWindowAlpha as String: 1.0,
                kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 100, "Height": 100] as NSDictionary,
            ]
        }
        let front = OwnWindowHitTest.frontmostWindow(at: CGPoint(x: 5, y: 5), in: [window(pid: 10, layer: 23), window(pid: 20, layer: 0)])
        XCTAssertEqual(front?.owner, 10)
        XCTAssertEqual(front?.layer, 23)
        XCTAssertNil(OwnWindowHitTest.frontmostWindow(at: CGPoint(x: 500, y: 500), in: [window(pid: 10, layer: 23)]))
    }

    // MARK: The lock uses it

    func testTheCoverGoesUpWithAGuardedLockAndComesDownWithIt() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration())
        XCTAssertTrue(rig.shield.isShown)
        XCTAssertEqual(rig.shield.showCalls, 1)
        rig.blocker.stop(reason: .clicked)
        XCTAssertFalse(rig.shield.isShown)
        XCTAssertEqual(rig.shield.hideCalls, 1)
    }

    func testAFrozenMouseIsCoveredToo() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 60, guardPointer: false))
        XCTAssertTrue(rig.shield.isShown)
    }

    func testWithTheGuardOffAndTheMouseFreeNothingIsCovered() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(guardPointer: false))
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.shield.showCalls, 0)
    }

    func testARefusedLockNeverCoversTheScreen() {
        let rig = BlockerRig()
        rig.tap.refuses = true
        rig.blocker.start(LockConfiguration())
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.shield.showCalls, 0)
        let noPermission = BlockerRig()
        noPermission.permission.trusted = false
        noPermission.blocker.start(LockConfiguration())
        XCTAssertEqual(noPermission.shield.showCalls, 0)
    }

    func testEveryWayOfEndingALockUncoversTheScreen() {
        for reason in [UnlockReason.clicked, .escHeld, .autoUnlock, .quit, .systemSleep, .screenLocked, .permissionRevoked] {
            let rig = BlockerRig()
            rig.blocker.start(LockConfiguration())
            rig.blocker.stop(reason: reason)
            XCTAssertFalse(rig.shield.isShown, "\(reason)")
        }
    }

    func testTheAutoUnlockUncoversTheScreenByItself() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, autoUnlockSeconds: 30))
        XCTAssertTrue(rig.shield.isShown)
        rig.clock.advance(by: 31)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertFalse(rig.shield.isShown)
    }
}
