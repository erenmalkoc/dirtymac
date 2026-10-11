import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// Decisions the menu bar panel makes about what to show.
final class PanelTests: XCTestCase {
    func testARunningLockAlwaysShowsItsStopControl() {
        XCTAssertTrue(MainView.showsLockControl(isActive: true, hasPermission: false))
        XCTAssertTrue(MainView.showsLockControl(isActive: true, hasPermission: true))
        XCTAssertTrue(MainView.showsLockControl(isActive: false, hasPermission: true))
        XCTAssertFalse(MainView.showsLockControl(isActive: false, hasPermission: false))
    }

    func testTheMenuBarGlyphIsATemplateUntilLockedThenRed() throws {
        let idle = try XCTUnwrap(AppDelegate.statusImage(active: false))
        XCTAssertTrue(idle.isTemplate)

        let locked = try XCTUnwrap(AppDelegate.statusImage(active: true))
        XCTAssertFalse(locked.isTemplate)
        // 1.2.0 drew the locked glyph black; it must really be red.
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        locked.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        var red = 0
        for x in 0..<36 {
            for y in 0..<36 {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                if c.redComponent > 0.7, c.greenComponent < 0.5 { red += 1 }
            }
        }
        XCTAssertGreaterThan(red, 200, "the locked glyph has \(red) red pixels")
    }

    func testOnlyLocksTheSystemEndedAreExplained() {
        let byUser: [UnlockReason] = [.clicked, .escHeld, .autoUnlock, .quit]
        let bySystem: [UnlockReason] = [.systemSleep, .screenLocked, .userSwitched, .systemSettings, .permissionRevoked]
        for reason in byUser { XCTAssertNil(reason.explanation, "\(reason)") }
        for reason in bySystem { XCTAssertNotNil(reason.explanation, "\(reason)") }
    }
}
