import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// The countdown beside the menu bar icon and in the locked panel.
@MainActor
final class LockStatusTests: XCTestCase {
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    private func title(
        active: Bool = true,
        hold: EscHoldState = .idle,
        total: Int = 0,
        elapsed: TimeInterval = 0
    ) -> String? {
        LockStatusTitle.text(isActive: active, escHold: hold, autoUnlockTotal: total, elapsed: elapsed)
    }

    // MARK: The text

    func testNothingIsShownWhileUnlocked() {
        XCTAssertNil(title(active: false))
        XCTAssertNil(title(active: false, hold: .holding(remaining: 2, progress: 0.4)))
        XCTAssertNil(title(active: false, hold: .letGo, total: 300, elapsed: 20))
    }

    func testAnAutoUnlockShowsTheTimeLeft() {
        XCTAssertEqual(title(total: 300, elapsed: 0), "05:00")
        XCTAssertEqual(title(total: 300, elapsed: 10.5), "04:50")
        XCTAssertEqual(title(total: 300, elapsed: 299), "00:01")
        XCTAssertEqual(title(total: 3599, elapsed: 0), "59:59")
        XCTAssertEqual(title(total: 3600, elapsed: 0), "1:00:00")
        XCTAssertEqual(title(total: 86_400, elapsed: 0), "24:00:00")
        XCTAssertEqual(title(total: 30, elapsed: 0), "00:30")
    }

    func testThePastTheDeadlineNeverGoesNegative() {
        XCTAssertEqual(title(total: 30, elapsed: 30), "00:00")
        XCTAssertEqual(title(total: 30, elapsed: 500), "00:00")
    }

    func testWithoutATimerItShowsHowLongTheKeyboardHasBeenLocked() {
        XCTAssertEqual(title(total: 0, elapsed: 0), "00:00")
        XCTAssertEqual(title(total: 0, elapsed: 125.7), "02:05")
        XCTAssertEqual(title(total: 0, elapsed: 4510), "1:15:10")
    }

    func testHoldingEscOutranksTheTimerAndCountsDown() {
        for remaining in [3, 2, 1] {
            XCTAssertEqual(
                title(hold: .holding(remaining: remaining, progress: 0.2), total: 300, elapsed: 20),
                "Esc \(remaining)"
            )
        }
        XCTAssertEqual(title(hold: .letGo, total: 300, elapsed: 20), "Esc 0")
        XCTAssertEqual(title(hold: .letGo, total: 0, elapsed: 20), "Esc 0")
    }

    func testTheClockHelper() {
        XCTAssertEqual(LockStatusTitle.clock(0), "00:00")
        XCTAssertEqual(LockStatusTitle.clock(59), "00:59")
        XCTAssertEqual(LockStatusTitle.clock(60), "01:00")
        XCTAssertEqual(LockStatusTitle.clock(-7), "00:00")
        XCTAssertEqual(LockStatusTitle.clock(3599), "59:59")
        XCTAssertEqual(LockStatusTitle.clock(3600), "1:00:00")
        XCTAssertEqual(LockStatusTitle.clock(4510), "1:15:10")
        XCTAssertEqual(LockStatusTitle.clock(86_399), "23:59:59")
        XCTAssertEqual(LockStatusTitle.clock(86_400), "24:00:00")
    }

    func testTheTitleNeedsNoTranslation() {
        // Digits, a colon and the key's own name, which is printed on the
        // key in every language: nothing a translation would change.
        for text in ["05:00", "Esc 3", "Esc 0"] {
            let withoutKeyName = text.replacingOccurrences(of: LockStatusTitle.escLabel, with: "")
            XCTAssertTrue(withoutKeyName.allSatisfy { $0.isNumber || $0 == ":" || $0 == " " }, text)
        }
    }

    // MARK: The same as the blocker's own countdown

    func testTheTitleAgreesWithThePanelsCountdownThroughARealLock() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, autoUnlockSeconds: 120))
        for seconds in [1.0, 10.0, 50.0] {
            rig.clock.advance(by: seconds)
            let shown = title(total: rig.blocker.autoUnlockTotal, elapsed: rig.blocker.elapsed)
            XCTAssertEqual(shown, rig.blocker.autoUnlockRemainingDisplay, "after \(seconds) s")
        }
    }

    func testTheTitleFollowsAHoldThroughARealLock() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, autoUnlockSeconds: 120))
        func shown() -> String? {
            title(hold: rig.blocker.escHold, total: rig.blocker.autoUnlockTotal, elapsed: rig.blocker.elapsed)
        }
        XCTAssertEqual(shown(), "02:00")
        rig.tap.send(.escDown)
        XCTAssertEqual(shown(), "Esc 3")
        rig.clock.advance(by: 1.5)
        XCTAssertEqual(shown(), "Esc 2")
        rig.clock.advance(by: 1)
        XCTAssertEqual(shown(), "Esc 1")
        rig.clock.advance(by: 0.6)
        XCTAssertEqual(shown(), "Esc 0")
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertNil(title(active: rig.blocker.isActive), "the lock is over: no title")
    }

    func testAnEarlyReleaseBringsTheTimerBack() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, autoUnlockSeconds: 120))
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1.5)
        rig.tap.send(.escUp)
        let back = title(hold: rig.blocker.escHold, total: rig.blocker.autoUnlockTotal, elapsed: rig.blocker.elapsed)
        XCTAssertEqual(back, "01:59", "the timer kept running behind the hold")
    }

    // MARK: Drawing

    func testDigitsHaveTheSameWidthSoTheItemDoesNotJitter() {
        let widths = ["00:00", "11:11", "88:88", "59:59", "Esc 1", "Esc 3", "Esc 0"].map {
            LockStatusTitle.attributed($0).size().width
        }
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.01)
        XCTAssertEqual(widths[0], widths[2], accuracy: 0.01)
        XCTAssertEqual(widths[0], widths[3], accuracy: 0.01)
        XCTAssertEqual(widths[4], widths[5], accuracy: 0.01)
        XCTAssertEqual(widths[4], widths[6], accuracy: 0.01)
    }

    func testTheTitleIsPutBesideTheIconAndTakenAwayAgain() {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        LockStatusTitle.apply(nil, to: button)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.attributedTitle.string, "")

        LockStatusTitle.apply("14:32", to: button)
        XCTAssertEqual(button.imagePosition, .imageLeft)
        XCTAssertEqual(button.attributedTitle.string.trimmingCharacters(in: .whitespaces), "14:32")

        LockStatusTitle.apply("Esc 2", to: button)
        XCTAssertEqual(button.attributedTitle.string.trimmingCharacters(in: .whitespaces), "Esc 2")

        LockStatusTitle.apply(nil, to: button)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.attributedTitle.string, "")
    }

    /// The icon with each title on a light and a dark bar, enlarged, to look at.
    func testMenuBarStripPicture() throws {
        let titles: [String?] = [nil, "14:32", "Esc 3", "Esc 0"]
        func cell(_ text: String?, active: Bool, badged: Bool, dark: Bool) -> NSView {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
            button.isBordered = false
            button.image = AppDelegate.statusImage(active: active, badged: badged)
            LockStatusTitle.apply(text, to: button)
            button.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            button.sizeToFit()
            return button
        }
        for dark in [false, true] {
            for (index, text) in titles.enumerated() {
                let button = cell(text, active: text != nil, badged: false, dark: dark)
                let background = NSView(frame: NSRect(x: 0, y: 0, width: 110, height: 28))
                background.wantsLayer = true
                background.layer?.backgroundColor = (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).cgColor
                button.frame.origin = NSPoint(x: 8, y: 2)
                background.addSubview(button)
                background.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                XCTAssertGreaterThan(button.frame.width, text == nil ? 10 : 40, "the title makes the item wider")
                ViewHost.snapshot(background, named: "menubar-title-\(dark ? "dark" : "light")-\(index)")
            }
        }
    }

    // MARK: The locked panel

    private func lockedPanel(_ rig: BlockerRig, language: String) throws -> NSHostingView<some View> {
        let defaults = try TestDefaults.make(self)
        return ViewHost.host(
            MainView(showingSettings: .constant(false))
                .environmentObject(rig.blocker)
                .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
                .environment(\.locale, Locale(identifier: language))
        )
    }

    func testThePanelDoesNotChangeHeightAsTheHoldRuns() throws {
        for language in languages {
            let rig = BlockerRig()
            rig.blocker.start(LockConfiguration(mode: .advanced, autoUnlockSeconds: 120))
            let idle = try lockedPanel(rig, language: language)
            ViewHost.snapshot(idle, named: "locked-idle-\(language)")

            rig.tap.send(.escDown)
            rig.clock.advance(by: 1.5)
            let holding = try lockedPanel(rig, language: language)
            ViewHost.snapshot(holding, named: "locked-holding-\(language)")

            rig.clock.advance(by: 1.7)
            let letGo = try lockedPanel(rig, language: language)
            ViewHost.snapshot(letGo, named: "locked-letgo-\(language)")

            XCTAssertEqual(holding.frame.height, idle.frame.height, accuracy: 0.5, "\(language): idle → holding")
            XCTAssertEqual(letGo.frame.height, idle.frame.height, accuracy: 0.5, "\(language): idle → let go")
        }
    }

    func testTheLockedPanelWithoutATimerAlsoHoldsItsHeight() throws {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration())
        let idle = try lockedPanel(rig, language: "en")
        rig.tap.send(.escDown)
        rig.clock.advance(by: 1.5)
        let holding = try lockedPanel(rig, language: "en")
        XCTAssertEqual(holding.frame.height, idle.frame.height, accuracy: 0.5)
        ViewHost.snapshot(holding, named: "locked-notimer-holding-en")
    }
}
