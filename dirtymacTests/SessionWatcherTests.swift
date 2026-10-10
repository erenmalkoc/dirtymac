import XCTest
import AppKit
@testable import dirtymac

final class SessionWatcherTests: XCTestCase {
    func testStepAwayEventsMapToTheirReasons() {
        XCTAssertEqual(SessionWatcher.reason(for: NSWorkspace.willSleepNotification), .systemSleep)
        XCTAssertEqual(SessionWatcher.reason(for: SessionWatcher.screenLockedNotification), .screenLocked)
        XCTAssertEqual(SessionWatcher.reason(for: NSWorkspace.sessionDidResignActiveNotification), .userSwitched)
        XCTAssertEqual(
            SessionWatcher.reason(
                for: NSWorkspace.didActivateApplicationNotification,
                activatedBundleID: SessionWatcher.systemSettingsBundleID
            ),
            .systemSettings
        )
    }

    func testOtherEventsLeaveTheLockAlone() {
        // Display sleep and waking are not the user stepping away.
        XCTAssertNil(SessionWatcher.reason(for: NSWorkspace.screensDidSleepNotification))
        XCTAssertNil(SessionWatcher.reason(for: NSWorkspace.didWakeNotification))
        XCTAssertNil(SessionWatcher.reason(
            for: NSWorkspace.didActivateApplicationNotification,
            activatedBundleID: "com.apple.Safari"
        ))
        XCTAssertNil(SessionWatcher.reason(for: NSWorkspace.didActivateApplicationNotification))
    }

    func testPostedNotificationsReachTheCallback() {
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        var reasons: [UnlockReason] = []
        let watcher = SessionWatcher(workspaceCenter: workspace, distributedCenter: distributed) {
            reasons.append($0)
        }
        watcher.start()
        defer { watcher.stop() }

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        distributed.post(name: SessionWatcher.screenLockedNotification, object: nil)
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(reasons, [.systemSleep, .screenLocked, .userSwitched])
    }

    func testAStoppedWatcherHearsNothing() {
        let workspace = NotificationCenter()
        var heard = 0
        let watcher = SessionWatcher(workspaceCenter: workspace, distributedCenter: NotificationCenter()) { _ in
            heard += 1
        }
        watcher.start()
        watcher.stop()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(heard, 0)
    }
}
