import XCTest
import AppKit
@testable import dirtymac

/// The parts of the real platform layer that can run without an
/// Accessibility permission.
final class LockPlatformTests: XCTestCase {
    func testTimersKeepFiringWhileAMenuIsOpen() {
        let scheduler = RunLoopScheduler()
        var fired = false
        let timer = scheduler.schedule(after: 0.05, repeats: false) { fired = true }
        defer { timer.cancel() }

        // An open menu or a drag runs the main run loop in event-tracking
        // mode; hold-Esc and auto-unlock must not stall then.
        let deadline = Date().addingTimeInterval(2)
        while !fired && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(fired)
    }

    func testCancelledTimersNeverFire() {
        let scheduler = RunLoopScheduler()
        var fired = false
        scheduler.schedule(after: 0.05, repeats: false) { fired = true }.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(fired)
    }

    func testInvalidatingTheTapReleasesItsPortAndSource() throws {
        var context = CFMachPortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let port = try XCTUnwrap(CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil))
        let source = try XCTUnwrap(CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0))
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        SessionEventTap.invalidate(port: port, source: source)

        XCTAssertFalse(CFMachPortIsValid(port))
        XCTAssertFalse(CFRunLoopSourceIsValid(source))
    }
}
