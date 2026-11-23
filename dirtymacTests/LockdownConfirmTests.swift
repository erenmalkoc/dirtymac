import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// The confirmation before a full lockdown, the Settings note beside the
/// timer, and the pieces that tie the Esc check to them.
@MainActor
final class LockdownConfirmTests: XCTestCase {
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    private func frozen(_ seconds: Int) -> LockConfiguration {
        LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: seconds)
    }

    // MARK: Decisions

    func testTheCheckListensOnlyWhileALongLockIsBeingConfirmed() {
        let long = frozen(900), short = frozen(300), keyboardOnly = LockConfiguration(mode: .advanced, autoUnlockSeconds: 3600)
        XCTAssertTrue(MainView.escCheckShouldListen(confirming: true, configuration: long))
        XCTAssertFalse(MainView.escCheckShouldListen(confirming: false, configuration: long), "not confirming")
        XCTAssertFalse(MainView.escCheckShouldListen(confirming: true, configuration: short), "five minutes needs no check")
        XCTAssertFalse(MainView.escCheckShouldListen(confirming: true, configuration: keyboardOnly), "the mouse is free")
        XCTAssertFalse(MainView.escCheckShouldListen(confirming: true, configuration: LockConfiguration()), "Basic")
    }

    func testTheLockButtonWaitsForSecureInputAndForTheCheck() {
        func disabled(_ secure: Bool, _ needs: Bool, _ passed: Bool) -> Bool {
            MainView.lockButtonDisabled(secureInputOn: secure, requiresEscCheck: needs, escPassed: passed)
        }
        XCTAssertFalse(disabled(false, false, false), "a short lock starts at once")
        XCTAssertTrue(disabled(false, true, false), "a long lock waits for the check")
        XCTAssertFalse(disabled(false, true, true), "and starts once it passed")
        XCTAssertTrue(disabled(true, false, false), "secure input still blocks")
        XCTAssertTrue(disabled(true, true, true), "even after a pass")
        XCTAssertFalse(disabled(false, false, true), "a stray pass changes nothing")
    }

    func testClosingThePanelAnnouncesItSoAnOpenConfirmationEnds() throws {
        let delegate = try XCTUnwrap(AppDelegate.shared)
        let announced = expectation(forNotification: .panelDidClose, object: nil)
        delegate.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        wait(for: [announced], timeout: 1)
    }

    // MARK: The confirmation on screen

    /// Owns the fake permission that is "granted". Without a granted
    /// permission the panel shows its permission prompt and the
    /// confirmation is never reached.
    private let rig = BlockerRig()

    private func confirm(_ configuration: LockConfiguration, language: String, dark: Bool = false) throws -> NSHostingView<some View> {
        let defaults = try TestDefaults.make(self)
        rig.blocker.refreshPermission()
        XCTAssertTrue(rig.blocker.hasPermission)
        return ViewHost.host(
            MainView(showingSettings: .constant(false), confirming: true, configuration: configuration)
                .environmentObject(rig.blocker)
                .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
                .environment(\.locale, Locale(identifier: language)),
            dark: dark
        )
    }

    func testTheConfirmationFitsInEveryLanguageForShortAndLongLocks() throws {
        var tallest: (String, CGFloat) = ("", 0)
        for language in languages {
            for (name, seconds) in [("short", 120), ("long", 900)] {
                let view = try confirm(frozen(seconds), language: language)
                if view.frame.height > tallest.1 { tallest = (language + " " + name, view.frame.height) }
                XCTAssertGreaterThan(view.frame.height, 250, "\(language) \(name)")
                ViewHost.snapshot(view, named: "confirm-\(name)-\(language)")
            }
        }
        print("tallest confirmation: \(tallest.0) \(tallest.1) pt")
        XCTAssertLessThan(tallest.1, 620, "the confirmation in \(tallest.0) is \(tallest.1) pt tall")
    }

    func testALongLockShowsTheCheckAndAShortOneDoesNot() throws {
        let short = try confirm(frozen(120), language: "en")
        let long = try confirm(frozen(900), language: "en")
        XCTAssertGreaterThan(long.frame.height, short.frame.height + 20, "the check row takes room")
    }

    func testTheConfirmationInDarkAppearanceIsDrawn() throws {
        let view = try confirm(frozen(900), language: "en", dark: true)
        XCTAssertGreaterThan(view.frame.height, 250)
        ViewHost.snapshot(view, named: "confirm-long-dark")
    }

    // MARK: Settings

    private func settings(mouseFrozen: Bool, language: String = "en", maxContentHeight: CGFloat = 10_000) throws -> NSHostingView<some View> {
        let defaults = try TestDefaults.make(self)
        defaults.set(LockMode.advanced.rawValue, forKey: LockConfiguration.Key.mode)
        defaults.set(mouseFrozen, forKey: LockConfiguration.Key.blockMouseAndTrackpad)
        defaults.set(mouseFrozen ? 900 : 3600, forKey: LockConfiguration.Key.autoUnlockSeconds)
        return ViewHost.host(
            SettingsView(isPresented: .constant(true), maxContentHeight: maxContentHeight)
                .defaultAppStorage(defaults)
                .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
                .environment(\.locale, Locale(identifier: language))
        )
    }

    func testTheCapNoteAppearsOnlyWithAFrozenMouse() throws {
        let free = try settings(mouseFrozen: false)
        let frozen = try settings(mouseFrozen: true)
        XCTAssertGreaterThan(frozen.frame.height, free.frame.height + 30, "the warning and the note are added")
        ViewHost.snapshot(free, named: "settings-timer-free")
        ViewHost.snapshot(frozen, named: "settings-timer-frozen")
    }

    func testSettingsScrollInsteadOfOutgrowingTheScreenInEveryLanguage() throws {
        // A small MacBook leaves roughly 700 points for the content.
        let limit: CGFloat = 640
        var natural: (String, CGFloat) = ("", 0)
        for language in languages {
            let unlimited = try settings(mouseFrozen: true, language: language)
            if unlimited.frame.height > natural.1 { natural = (language, unlimited.frame.height) }
            let limited = try settings(mouseFrozen: true, language: language, maxContentHeight: limit)
            // The header and the footer are outside the scrolling part.
            XCTAssertLessThanOrEqual(limited.frame.height, limit + 140, "\(language): \(limited.frame.height)")
            ViewHost.snapshot(limited, named: "settings-frozen-\(language)")
        }
        print("natural Settings height with the note, tallest: \(natural.0) \(natural.1) pt")
        XCTAssertGreaterThan(natural.1, limit + 140, "the test only means something if the content really is taller than the limit")
    }

    func testShortSettingsAreNotStretchedByTheScrollArea() throws {
        func basicHeight(max: CGFloat) throws -> CGFloat {
            let defaults = try TestDefaults.make(self)
            return ViewHost.host(
                SettingsView(isPresented: .constant(true), maxContentHeight: max)
                    .defaultAppStorage(defaults)
                    .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
            ).frame.height
        }
        let roomy = try basicHeight(max: 10_000)
        // Basic mode is tall now (delay, screen, updates). A small screen scrolls it,
        // which the limit in the other tests covers: here it only must not run away.
        XCTAssertLessThan(roomy, 1100, "Basic mode does not grow without bound")
        XCTAssertGreaterThan(roomy, 400, "and is not collapsed to nothing")
        XCTAssertEqual(try basicHeight(max: roomy + 500), roomy, "extra room is not filled")
    }

    func testTheLimitIsTheScreenLessRoomForTheChrome() {
        XCTAssertEqual(SettingsView.maxContentHeight(forVisibleHeight: 840), 650)
        XCTAssertEqual(SettingsView.maxContentHeight(forVisibleHeight: 1152), 962)
        XCTAssertEqual(SettingsView.maxContentHeight(forVisibleHeight: 300), 360, "never collapses to nothing")
    }

    func testTheDefaultLimitFollowsTheScreen() {
        let limit = SettingsView.defaultMaxContentHeight
        XCTAssertGreaterThanOrEqual(limit, 360)
        if let screen = NSScreen.main {
            XCTAssertLessThanOrEqual(limit, max(360, screen.visibleFrame.height - 190))
        }
    }
}
