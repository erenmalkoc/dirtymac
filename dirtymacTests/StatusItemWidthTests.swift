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
        XCTAssertEqual(counting, ["wait 10", "888:88", "Esc 3"], "counting up can pass 99 minutes")
    }

    func testTheTitleIsPackedToTheLeft() {
        let b = button()
        LockStatusTitle.apply("04:59", to: b)
        XCTAssertEqual(b.alignment, .left)
        XCTAssertEqual(b.imagePosition, .imageLeft)
    }

    func testNoTitleThatCanOccurIsWiderThanTheReservedWidth() {
        for language in languages {
            for total in [0, 60, 3600] {
                let b = button()
                let reserved = LockStatusTitle.reservedWidth(
                    for: b,
                    texts: LockStatusTitle.widestTexts(autoUnlockTotal: total) { self.pendingText($0, language) }
                )
                var shown = (1...10).map { pendingText($0, language) }
                shown += ["00:00", "04:59", total > 0 ? "59:59" : "99:59", "Esc 3", "Esc 2", "Esc 1", "Esc 0"]
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
