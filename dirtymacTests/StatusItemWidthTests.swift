import XCTest
import AppKit
@testable import dirtymac

/// The menu bar item keeps one width while a lock runs, so the panel that
/// hangs from it does not slide sideways as the counter changes.
@MainActor
final class StatusItemWidthTests: XCTestCase {
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    private func pendingText(_ n: Int, _ language: String) -> String {
        String(localized: "Locking in \(n)…", bundle: LanguagePreference(rawValue: language)?.bundle ?? .main)
    }

    private func button() -> NSButton {
        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        return button
    }

    func testTheWidestTextsCoverTheStartDelayTheClockAndTheEscCountdown() {
        let withTimer = LockStatusTitle.widestTexts(autoUnlockTotal: 300) { "wait \($0)" }
        XCTAssertEqual(withTimer, ["wait 10", "88:88", "Esc 3"])
        let counting = LockStatusTitle.widestTexts(autoUnlockTotal: 0) { "wait \($0)" }
        XCTAssertEqual(counting, ["wait 10", "88:88:88", "Esc 3"], "counting up has no end")
        let hours = LockStatusTitle.widestTexts(autoUnlockTotal: 3600) { "wait \($0)" }
        XCTAssertEqual(hours[1], "8:88:88", "from an hour on the clock shows hours")
        let longer = LockStatusTitle.widestTexts(autoUnlockTotal: 36_000) { "wait \($0)" }
        XCTAssertEqual(longer[1], "88:88:88", "ten hours and more need two digits of hours")
        XCTAssertEqual(LockStatusTitle.widestTexts(autoUnlockTotal: 3599) { "wait \($0)" }[1], "88:88")
    }

    func testTheTitleIsPackedToTheLeft() {
        let b = button()
        LockStatusTitle.apply("04:59", to: b)
        XCTAssertEqual(b.alignment, .left)
        XCTAssertEqual(b.imagePosition, .imageLeft)
    }

    func testNoTitleThatCanOccurIsWiderThanTheReservedWidth() {
        for language in languages {
            for total in [0, 60, 3600, 36_000, 86_400] {
                let b = button()
                let reserved = LockStatusTitle.reservedWidth(
                    for: b,
                    texts: LockStatusTitle.widestTexts(autoUnlockTotal: total) { self.pendingText($0, language) }
                )
                var shown = (1...10).map { pendingText($0, language) }
                shown += ["00:00", "04:59", total > 0 && total < 3600 ? "59:59" : "99:59", "Esc 3", "Esc 2", "Esc 1", "Esc 0"]
                if total >= 3600 { shown += ["1:00:00", "8:59:59"] }
                if total >= 36_000 || total == 0 { shown += ["23:59:59", "24:00:00"] }
                for text in shown {
                    LockStatusTitle.apply(text, to: b)
                    XCTAssertLessThanOrEqual(b.fittingSize.width, reserved + 0.5, "\(language) \(total) s \"\(text)\"")
                }
            }
        }
    }

    func testTheReservedWidthIsRoomForTheIconAndTheText() {
        let b = button()
        let bare = b.fittingSize.width
        let reserved = LockStatusTitle.reservedWidth(for: b, texts: ["88:88"])
        XCTAssertGreaterThan(reserved, bare + 20)
    }

    func testAFixedLengthItemKeepsItsWidthWhateverTheTitleSays() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let b = try XCTUnwrap(item.button)
        b.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        let texts = LockStatusTitle.widestTexts(autoUnlockTotal: 300) { "Locking in \($0)…" }
        item.length = LockStatusTitle.reservedWidth(for: b, texts: texts)
        XCTAssertNotEqual(item.length, NSStatusItem.variableLength)

        var widths = Set<CGFloat>()
        for text in ["Locking in 5…", "05:00", "Esc 3", "04:59"] {
            LockStatusTitle.apply(text, to: b)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if let w = b.window?.frame.width { widths.insert(w.rounded()) }
        }
        LockStatusTitle.apply(nil, to: b)
        XCTAssertLessThanOrEqual(widths.count, 1, "the item moved: \(widths)")
    }
}

/// The panel's arrow points at the icon, not at the middle of a button
/// that is wider than the icon.
@MainActor
final class StatusItemAnchorTests: XCTestCase {
    func testTheAnchorIsTheIconsOwnSpanAtTheFullHeight() {
        let bounds = NSRect(x: 0, y: 0, width: 120, height: 24)
        let image = NSRect(x: 6, y: 4, width: 18, height: 16)
        XCTAssertEqual(StatusItemAnchor.rect(buttonBounds: bounds, imageRect: image), NSRect(x: 6, y: 0, width: 18, height: 24))
    }

    func testWithoutAUsableImageRectTheWholeButtonIsTheTarget() {
        let bounds = NSRect(x: 0, y: 0, width: 40, height: 24)
        XCTAssertEqual(StatusItemAnchor.rect(buttonBounds: bounds, imageRect: .zero), bounds)
        XCTAssertEqual(StatusItemAnchor.rect(buttonBounds: bounds, imageRect: NSRect(x: 100, y: 0, width: 18, height: 16)), bounds)
        XCTAssertEqual(StatusItemAnchor.rect(buttonBounds: bounds, imageRect: NSRect(x: -30, y: 0, width: 18, height: 16)), bounds)
    }

    func testAWideButtonWithTextPointsAtTheIconNotTheMiddle() {
        let b = NSButton(frame: .zero)
        b.isBordered = false
        b.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        let texts = LockStatusTitle.widestTexts(autoUnlockTotal: 300) { "Locking in \($0)…" }
        let width = LockStatusTitle.reservedWidth(for: b, texts: texts)
        b.frame = NSRect(x: 0, y: 0, width: width, height: 24)
        LockStatusTitle.apply("04:59", to: b)
        let anchor = StatusItemAnchor.rect(for: b)
        XCTAssertLessThan(anchor.midX, b.bounds.midX - 10, "the arrow must not sit in the middle of the wide button")
        XCTAssertEqual(anchor.height, 24)
        XCTAssertLessThan(anchor.width, 40)
    }

    func testAnIconOnlyButtonPointsAtTheMiddleAsBefore() {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        b.isBordered = false
        b.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        b.imagePosition = .imageOnly
        let anchor = StatusItemAnchor.rect(for: b)
        XCTAssertEqual(anchor.midX, b.bounds.midX, accuracy: 1.5)
    }
}
