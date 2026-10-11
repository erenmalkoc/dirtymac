import XCTest
import Carbon.HIToolbox
@testable import dirtymac

final class SecureInputTests: XCTestCase {
    private let me = getuid()

    // MARK: Finding the holder in IOConsoleUsers

    func testFindsTheHolderInTheUsersOwnSession() {
        let users: [[String: Any]] = [
            ["kCGSSessionUserIDKey": NSNumber(value: me + 1), "kCGSSessionSecureInputPID": NSNumber(value: 111)],
            ["kCGSSessionUserIDKey": NSNumber(value: me), "kCGSSessionSecureInputPID": NSNumber(value: 222)],
        ]
        XCTAssertEqual(SecureInputOwner.pid(in: users, userID: me), 222)
    }

    func testPlainSwiftNumbersParseToo() {
        let users: [[String: Any]] = [["kCGSSessionUserIDKey": Int(me), "kCGSSessionSecureInputPID": 333]]
        XCTAssertEqual(SecureInputOwner.pid(in: users, userID: me), 333)
    }

    func testNoHolderWhenTheKeyIsMissingZeroOrMalformed() {
        XCTAssertNil(SecureInputOwner.pid(in: [], userID: me))
        XCTAssertNil(SecureInputOwner.pid(in: [["kCGSSessionUserIDKey": Int(me)]], userID: me))
        XCTAssertNil(SecureInputOwner.pid(
            in: [["kCGSSessionUserIDKey": Int(me), "kCGSSessionSecureInputPID": 0]], userID: me))
        XCTAssertNil(SecureInputOwner.pid(
            in: [["kCGSSessionUserIDKey": Int(me), "kCGSSessionSecureInputPID": "Terminal"]], userID: me))
        // Another user's secure input is not ours to report.
        XCTAssertNil(SecureInputOwner.pid(
            in: [["kCGSSessionUserIDKey": Int(me) + 1, "kCGSSessionSecureInputPID": 444]], userID: me))
    }

    // MARK: Policy

    func testAFieldFocusedForAMomentIsIgnored() {
        XCTAssertEqual(SecureInputPolicy.duringLock(readings: 0, mouseLocked: false), .none)
        XCTAssertEqual(SecureInputPolicy.duringLock(readings: 1, mouseLocked: true), .none)
    }

    func testKeyboardLocksWarnAndFullLockdownLetsGo() {
        XCTAssertEqual(SecureInputPolicy.duringLock(readings: 2, mouseLocked: false), .warn)
        XCTAssertEqual(SecureInputPolicy.duringLock(readings: 9, mouseLocked: false), .warn)
        XCTAssertEqual(SecureInputPolicy.duringLock(readings: 2, mouseLocked: true), .release)
    }

    func testOnlyFullLockdownRefusesToStart() {
        XCTAssertTrue(SecureInputPolicy.canStart(secureInputOn: false, mouseLocked: true))
        XCTAssertTrue(SecureInputPolicy.canStart(secureInputOn: true, mouseLocked: false))
        XCTAssertFalse(SecureInputPolicy.canStart(secureInputOn: true, mouseLocked: true))
    }

    // MARK: Spotlight and Shortcuts

    func testTheIntentLocksBlindOnlyWhenNothingNeedsTheUser() {
        func decide(_ active: Bool, _ permission: Bool, _ mouse: Bool, _ secure: Bool) -> IntentLockDecision {
            IntentLockDecision.decide(isActive: active, hasPermission: permission, mouseLocked: mouse, secureInputOn: secure)
        }
        XCTAssertEqual(decide(false, true, false, false), .lock)
        XCTAssertEqual(decide(false, false, false, false), .openPanel)
        XCTAssertEqual(decide(false, true, true, false), .openPanel)
        XCTAssertEqual(decide(false, true, false, true), .openPanel)
        for permission in [false, true] {
            for mouse in [false, true] {
                for secure in [false, true] {
                    XCTAssertEqual(decide(true, permission, mouse, secure), .alreadyLocked)
                }
            }
        }
    }

    // MARK: The real thing (needs no permission)

    func testDetectsSecureInputTurnedOnByThisProcess() throws {
        let detector = SystemSecureInput()
        try XCTSkipIf(detector.isEnabled, "secure input already on; can't tell our own call apart")
        EnableSecureEventInput()
        defer { DisableSecureEventInput() }
        try XCTSkipUnless(detector.isEnabled, "this machine ignores EnableSecureEventInput")

        // IOConsoleUsers' holder pid is undocumented and can name another
        // process (seen on CI), so it is only read, never trusted here;
        // the panel names an app only when the pid is a regular app.
        _ = SecureInputOwner.pid(in: SystemSecureInput.consoleUsers(), userID: getuid())
    }
}
