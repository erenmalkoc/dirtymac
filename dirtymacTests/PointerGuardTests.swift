import XCTest
import AppKit
@testable import dirtymac

/// The pointer guard: while the keyboard is locked, scrolling, gestures
/// and clicks go nowhere except on dirtymac's own windows, and moving the
/// cursor stays free.
final class PointerGuardTests: XCTestCase {
    private func mask(_ config: LockConfiguration) -> CGEventMask {
        EventMask.build(for: config.effective)
    }

    private let buttons: [(down: CGEventType, up: CGEventType, drag: CGEventType)] = [
        (.leftMouseDown, .leftMouseUp, .leftMouseDragged),
        (.rightMouseDown, .rightMouseUp, .rightMouseDragged),
        (.otherMouseDown, .otherMouseUp, .otherMouseDragged),
    ]

    // MARK: Configuration

    func testTheGuardIsOnByDefaultInEveryMode() {
        XCTAssertTrue(LockConfiguration().guardPointer)
        XCTAssertTrue(LockConfiguration().effective.guardPointer)
        XCTAssertTrue(LockConfiguration(mode: .advanced).effective.guardPointer)
    }

    func testBasicModeFollowsTheSettingToo() {
        XCTAssertFalse(LockConfiguration(mode: .basic, guardPointer: false).effective.guardPointer)
        XCTAssertTrue(LockConfiguration(mode: .basic, guardPointer: true).effective.guardPointer)
    }

    func testNothingStoredLoadsItOn() throws {
        let defaults = try TestDefaults.make(self)
        XCTAssertTrue(LockConfiguration.load(from: defaults).guardPointer)
    }

    func testTheStoredSettingIsRead() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set(false, forKey: LockConfiguration.Key.guardPointer)
        XCTAssertFalse(LockConfiguration.load(from: defaults).guardPointer)
        defaults.set(true, forKey: LockConfiguration.Key.guardPointer)
        XCTAssertTrue(LockConfiguration.load(from: defaults).guardPointer)
        XCTAssertEqual(LockConfiguration.Key.guardPointer, "guardPointerWhileLocked")
    }

    // MARK: Event mask

    func testTheGuardInterceptsClicksDragsScrollAndGesturesButNotMovement() {
        let m = mask(LockConfiguration())
        for type in EventMask.guardedPointerTypes {
            XCTAssertNotEqual(m & EventMask.bit(type), 0, "event type \(type.rawValue)")
        }
        XCTAssertNotEqual(m & EventMask.gestureBit, 0)
        XCTAssertNotEqual(m & EventMask.bit(.scrollWheel), 0)
        XCTAssertEqual(m & EventMask.bit(.mouseMoved), 0, "the cursor must keep moving")
        XCTAssertEqual(EventMask.guardedPointerTypes.count, EventMask.pointerTypes.count - 1)
    }

    func testTurningTheGuardOffLeavesThePointerAlone() {
        let m = mask(LockConfiguration(guardPointer: false))
        for type in EventMask.pointerTypes {
            XCTAssertEqual(m & EventMask.bit(type), 0, "event type \(type.rawValue)")
        }
        XCTAssertEqual(m & EventMask.gestureBit, 0)
    }

    func testTheFullFreezeStillCatchesMovementEvenWithTheGuardOn() {
        let m = mask(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 60, guardPointer: true))
        XCTAssertNotEqual(m & EventMask.bit(.mouseMoved), 0)
    }

    func testTheGuardDoesNotTouchTheKeyboardBits() {
        let on = mask(LockConfiguration(guardPointer: true))
        let off = mask(LockConfiguration(guardPointer: false))
        var pointerBits = EventMask.gestureBit
        for type in EventMask.guardedPointerTypes { pointerBits |= EventMask.bit(type) }
        XCTAssertEqual(on & ~pointerBits, off)
    }

    func testWhichTypesTheGuardDecides() throws {
        for type in EventMask.guardedPointerTypes { XCTAssertTrue(EventMask.isGuarded(type)) }
        XCTAssertTrue(EventMask.isGuarded(try XCTUnwrap(CGEventType(rawValue: 29))))
        XCTAssertFalse(EventMask.isGuarded(.mouseMoved))
        XCTAssertFalse(EventMask.isGuarded(.keyDown))
        XCTAssertFalse(EventMask.isGuarded(.flagsChanged))
        XCTAssertFalse(EventMask.isGuarded(.tapDisabledByTimeout))
    }

    // MARK: Decisions

    func testScrollingAndGesturesAreAlwaysBlocked() throws {
        var guardian = PointerGuard()
        XCTAssertEqual(guardian.decide(type: .scrollWheel, overOwnWindow: { true }), .block)
        let gesture = try XCTUnwrap(CGEventType(rawValue: 29))
        XCTAssertEqual(guardian.decide(type: gesture, overOwnWindow: { true }), .block)
    }

    func testAClickOutsideOurWindowsIsBlockedWholeAndOneInsideGoesThrough() {
        for b in buttons {
            var guardian = PointerGuard()
            XCTAssertEqual(guardian.decide(type: b.down, overOwnWindow: { false }), .block, "\(b.down.rawValue)")
            XCTAssertEqual(guardian.decide(type: b.drag, overOwnWindow: { true }), .block)
            XCTAssertEqual(guardian.decide(type: b.up, overOwnWindow: { true }), .block)

            XCTAssertEqual(guardian.decide(type: b.down, overOwnWindow: { true }), .pass)
            XCTAssertEqual(guardian.decide(type: b.drag, overOwnWindow: { false }), .pass, "the drag follows its press")
            XCTAssertEqual(guardian.decide(type: b.up, overOwnWindow: { false }), .pass, "the release follows its press")
        }
    }

    func testTheReleaseIsOnlyPassedOnce() {
        var guardian = PointerGuard()
        _ = guardian.decide(type: .leftMouseDown, overOwnWindow: { true })
        XCTAssertEqual(guardian.decide(type: .leftMouseUp, overOwnWindow: { false }), .pass)
        XCTAssertEqual(guardian.decide(type: .leftMouseUp, overOwnWindow: { false }), .block)
        XCTAssertEqual(guardian.decide(type: .leftMouseDragged, overOwnWindow: { true }), .block)
    }

    func testTheButtonsAreTrackedApart() {
        var guardian = PointerGuard()
        XCTAssertEqual(guardian.decide(type: .leftMouseDown, overOwnWindow: { true }), .pass)
        XCTAssertEqual(guardian.decide(type: .rightMouseDown, overOwnWindow: { false }), .block)
        XCTAssertEqual(guardian.decide(type: .rightMouseUp, overOwnWindow: { true }), .block)
        XCTAssertEqual(guardian.decide(type: .otherMouseDragged, overOwnWindow: { true }), .block)
        XCTAssertEqual(guardian.decide(type: .leftMouseUp, overOwnWindow: { false }), .pass)
    }

    func testANewPressForgetsAnOldOne() {
        var guardian = PointerGuard()
        _ = guardian.decide(type: .leftMouseDown, overOwnWindow: { true })
        // The release was lost, and the next press lands outside.
        XCTAssertEqual(guardian.decide(type: .leftMouseDown, overOwnWindow: { false }), .block)
        XCTAssertEqual(guardian.decide(type: .leftMouseUp, overOwnWindow: { true }), .block)
    }

    func testTheWindowIsOnlyLookedUpWhenAButtonGoesDown() {
        var guardian = PointerGuard()
        var lookups = 0
        let ask: () -> Bool = { lookups += 1; return true }
        _ = guardian.decide(type: .scrollWheel, overOwnWindow: ask)
        _ = guardian.decide(type: .leftMouseDragged, overOwnWindow: ask)
        _ = guardian.decide(type: .leftMouseUp, overOwnWindow: ask)
        XCTAssertEqual(lookups, 0)
        _ = guardian.decide(type: .leftMouseDown, overOwnWindow: ask)
        XCTAssertEqual(lookups, 1)
    }

    func testResetForgetsEveryPress() {
        var guardian = PointerGuard()
        for b in buttons { _ = guardian.decide(type: b.down, overOwnWindow: { true }) }
        guardian.reset()
        for b in buttons {
            XCTAssertEqual(guardian.decide(type: b.up, overOwnWindow: { true }), .block)
        }
        XCTAssertEqual(guardian, PointerGuard())
    }

    // MARK: Which window is under the cursor

    private func window(pid: Int32, x: Double, y: Double, w: Double, h: Double, alpha: Double = 1) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: ["X": x, "Y": y, "Width": w, "Height": h] as NSDictionary,
        ]
    }

    func testTheFrontmostWindowAtThePointDecides() {
        let windows = [
            window(pid: 10, x: 0, y: 0, w: 100, h: 24),     // our status item, in front
            window(pid: 1, x: 0, y: 0, w: 1440, h: 24),     // the menu bar behind it
        ]
        XCTAssertEqual(OwnWindowHitTest.frontmostOwner(at: CGPoint(x: 50, y: 10), in: windows), 10)
        XCTAssertEqual(OwnWindowHitTest.frontmostOwner(at: CGPoint(x: 500, y: 10), in: windows), 1)
    }

    func testAnotherAppInFrontOfOurWindowWins() {
        let windows = [
            window(pid: 20, x: 0, y: 0, w: 200, h: 200),
            window(pid: 10, x: 0, y: 0, w: 300, h: 300),
        ]
        XCTAssertEqual(OwnWindowHitTest.frontmostOwner(at: CGPoint(x: 50, y: 50), in: windows), 20)
        XCTAssertEqual(OwnWindowHitTest.frontmostOwner(at: CGPoint(x: 250, y: 250), in: windows), 10)
    }

    func testInvisibleWindowsAreSkippedAndNothingMeansNoOwner() {
        let windows = [
            window(pid: 20, x: 0, y: 0, w: 200, h: 200, alpha: 0),
            window(pid: 10, x: 0, y: 0, w: 300, h: 300),
        ]
        XCTAssertEqual(OwnWindowHitTest.frontmostOwner(at: CGPoint(x: 50, y: 50), in: windows), 10)
        XCTAssertNil(OwnWindowHitTest.frontmostOwner(at: CGPoint(x: 900, y: 900), in: windows))
        XCTAssertNil(OwnWindowHitTest.frontmostOwner(at: .zero, in: []))
    }

    func testAWindowWithoutBoundsIsSkipped() {
        let windows: [[String: Any]] = [
            [kCGWindowOwnerPID as String: NSNumber(value: 20)],
            window(pid: 10, x: 0, y: 0, w: 10, h: 10),
        ]
        XCTAssertEqual(OwnWindowHitTest.frontmostOwner(at: CGPoint(x: 5, y: 5), in: windows), 10)
    }

    func testTheRealLookupFindsOurOwnWindowOnlyForOurPid() {
        // No window of this test host covers a point far outside any
        // display, so nothing is ours there.
        let far = CGPoint(x: -90_000, y: -90_000)
        XCTAssertFalse(OwnWindowHitTest().isOverOwnWindow(at: far))
        XCTAssertFalse(OwnWindowHitTest(pid: -5).isOverOwnWindow(at: far))
    }

    // MARK: The lock installs it

    @MainActor
    func testALockInstallsTheGuardUnlessTheMouseIsFrozenOrTheSettingIsOff() {
        func installed(_ config: LockConfiguration) -> Bool? {
            let rig = BlockerRig()
            rig.permission.trusted = true
            rig.blocker.start(config)
            return rig.tap.installedGuardPointer
        }
        XCTAssertEqual(installed(LockConfiguration()), true)
        XCTAssertEqual(installed(LockConfiguration(guardPointer: false)), false)
        XCTAssertEqual(installed(LockConfiguration(mode: .advanced, guardPointer: true)), true)
        XCTAssertEqual(installed(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 60, guardPointer: true)), false)
    }
}

/// The diagnostics tally and the split of the mask between the session tap
/// and the HID tap.
final class TapTallyTests: XCTestCase {
    func testTheHIDTapGetsEveryPointerTypeButNoGesture() {
        XCTAssertEqual(EventMask.pointerMask & EventMask.gestureBit, 0)
        for type in EventMask.pointerTypes {
            XCTAssertNotEqual(EventMask.pointerMask & EventMask.bit(type), 0, "event type \(type.rawValue)")
        }
        XCTAssertEqual(EventMask.pointerMask & (EventMask.bit(.keyDown) | EventMask.bit(.keyUp) | EventMask.bit(.flagsChanged)), 0)
    }

    func testTheKeyboardMaskLeavesNothingForTheHIDTap() {
        let keyboardOnly = EventMask.build(for: LockConfiguration(guardPointer: false).effective)
        XCTAssertEqual(keyboardOnly & EventMask.pointerMask, 0)
        XCTAssertNotEqual(EventMask.build(for: LockConfiguration().effective) & EventMask.pointerMask, 0)
    }

    func testItCountsByKindAndOutcomeAndStartsOverAfterAFlush() {
        var tally = TapTally()
        XCTAssertTrue(tally.isEmpty)
        XCTAssertNil(tally.flush())
        tally.record("scroll", swallowed: true)
        tally.record("scroll", swallowed: true)
        tally.record("down", swallowed: false)
        tally.record("scroll", swallowed: false)
        XCTAssertFalse(tally.isEmpty)
        XCTAssertEqual(tally.flush(), "down passed 1, scroll blocked 2, scroll passed 1")
        XCTAssertTrue(tally.isEmpty)
        XCTAssertNil(tally.flush())
    }

    func testEveryEventTypeHasAName() throws {
        XCTAssertEqual(TapTally.kind(of: .scrollWheel), "scroll")
        XCTAssertEqual(TapTally.kind(of: .leftMouseDown), "down")
        XCTAssertEqual(TapTally.kind(of: .otherMouseUp), "up")
        XCTAssertEqual(TapTally.kind(of: .rightMouseDragged), "drag")
        XCTAssertEqual(TapTally.kind(of: .mouseMoved), "moved")
        XCTAssertEqual(TapTally.kind(of: .keyUp), "key")
        XCTAssertEqual(TapTally.kind(of: .flagsChanged), "modifier")
        XCTAssertEqual(TapTally.kind(of: .tapDisabledByTimeout), "tap-disabled")
        XCTAssertEqual(TapTally.kind(of: try XCTUnwrap(CGEventType(rawValue: 29))), "gesture")
        let system = try XCTUnwrap(CGEventType(rawValue: kCGEventSystemDefined))
        XCTAssertEqual(TapTally.kind(of: system), "system-?")
        XCTAssertEqual(TapTally.kind(of: system, systemSubtype: kPowerKeySubtype), "system-1")
        XCTAssertEqual(TapTally.kind(of: system, systemSubtype: 8), "system-8")
        XCTAssertEqual(TapTally.kind(of: try XCTUnwrap(CGEventType(rawValue: 21))), "other-21")
    }

    func testTheLogIsOffUnlessAskedFor() {
        XCTAssertEqual(TapTally.defaultsKey, "tapDiagnostics")
        XCTAssertFalse(UserDefaults(suiteName: "tapdiag-\(UUID().uuidString)")!.bool(forKey: TapTally.defaultsKey))
    }
}
