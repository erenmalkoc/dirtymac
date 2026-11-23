import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// The start delay as the user sees it: the power button, the panel, the
/// menu bar and Settings.
@MainActor
final class StartDelayUITests: XCTestCase {
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    // MARK: The power button

    func testThePowerButtonDoesTheRightThingInEveryState() {
        func tap(_ active: Bool, _ waiting: Bool, _ mouse: Bool) -> MainView.PowerTapAction {
            MainView.powerTapAction(isActive: active, isWaiting: waiting, mouseLocked: mouse)
        }
        XCTAssertEqual(tap(false, false, false), .beginLock)
        XCTAssertEqual(tap(false, false, true), .confirmLockdown, "a frozen mouse asks first")
        XCTAssertEqual(tap(false, true, false), .cancelWait, "a click during the wait calls it off")
        XCTAssertEqual(tap(false, true, true), .cancelWait)
        XCTAssertEqual(tap(true, false, false), .stop)
        XCTAssertEqual(tap(true, false, true), .stop)
        XCTAssertEqual(tap(true, true, false), .stop, "a lock that runs always unlocks first")
    }

    // MARK: The menu bar

    func testTheMenuBarShowsTheWaitOnlyWhileNothingIsLockedYet() {
        let wait = "Locking in 4…"
        XCTAssertEqual(
            LockStatusTitle.text(isActive: false, escHold: .idle, autoUnlockTotal: 0, elapsed: 0, pendingLockText: wait),
            wait
        )
        XCTAssertNil(LockStatusTitle.text(isActive: false, escHold: .idle, autoUnlockTotal: 0, elapsed: 0))
        // Once locked the wait is over: the lock's own counter shows.
        XCTAssertEqual(
            LockStatusTitle.text(isActive: true, escHold: .idle, autoUnlockTotal: 120, elapsed: 20, pendingLockText: wait),
            "01:40"
        )
    }

    func testTheMenuBarFollowsAWaitThroughARealBlocker() {
        let rig = BlockerRig()
        rig.blocker.beginLock(LockConfiguration(mode: .advanced, autoUnlockSeconds: 120, startDelaySeconds: 3))
        func shown() -> String? {
            let pending = rig.blocker.lockCountdown.map { "wait \($0)" }
            return LockStatusTitle.text(
                isActive: rig.blocker.isActive, escHold: rig.blocker.escHold,
                autoUnlockTotal: rig.blocker.autoUnlockTotal, elapsed: rig.blocker.elapsed, pendingLockText: pending)
        }
        XCTAssertEqual(shown(), "wait 3")
        rig.clock.advance(by: 1)
        XCTAssertEqual(shown(), "wait 2")
        rig.clock.advance(by: 2)
        XCTAssertEqual(shown(), "02:00", "locked: the lock's own counter takes over")
        rig.blocker.stop(reason: .clicked)
        XCTAssertNil(shown())
    }

    // MARK: The panel

    private func panel(_ rig: BlockerRig, language: String) throws -> NSHostingView<some View> {
        let defaults = try TestDefaults.make(self)
        return ViewHost.host(
            MainView(showingSettings: .constant(false))
                .environmentObject(rig.blocker)
                .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
                .environment(\.locale, Locale(identifier: language))
        )
    }

    func testThePanelDoesNotChangeHeightWhileItWaits() throws {
        for language in languages {
            let rig = BlockerRig()
            let idle = try panel(rig, language: language)
            // The hosted view is live: take each picture before the state moves on.
            ViewHost.snapshot(idle, named: "delay-idle-\(language)")
            rig.blocker.beginLock(LockConfiguration(mode: .advanced, startDelaySeconds: 5))
            XCTAssertEqual(rig.blocker.lockCountdown, 5)
            let waiting = try panel(rig, language: language)
            ViewHost.snapshot(waiting, named: "delay-waiting-\(language)")
            XCTAssertEqual(waiting.frame.height, idle.frame.height, accuracy: 1.5, "\(language): idle → waiting")
        }
    }

    func testThePanelFollowsTheCountdownAndGoesBackWhenCancelled() throws {
        let rig = BlockerRig()
        rig.blocker.beginLock(LockConfiguration(mode: .advanced, startDelaySeconds: 10))
        let ten = try panel(rig, language: "en")
        rig.clock.advance(by: 4)
        let six = try panel(rig, language: "en")
        ViewHost.snapshot(six, named: "delay-waiting-six-en")
        XCTAssertEqual(ten.frame.height, six.frame.height, accuracy: 0.5, "the number changing does not move anything")
        rig.blocker.cancelPendingLock()
        let after = try panel(rig, language: "en")
        XCTAssertNil(rig.blocker.lockCountdown)
        XCTAssertEqual(after.frame.height, ten.frame.height, accuracy: 1.5)
    }

    func testTheWaitingPanelInDarkAppearanceIsDrawn() throws {
        let rig = BlockerRig()
        rig.blocker.beginLock(LockConfiguration(mode: .advanced, startDelaySeconds: 5))
        let defaults = try TestDefaults.make(self)
        let view = ViewHost.host(
            MainView(showingSettings: .constant(false))
                .environmentObject(rig.blocker)
                .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0")),
            dark: true
        )
        XCTAssertGreaterThan(view.frame.height, 250)
        ViewHost.snapshot(view, named: "delay-waiting-dark")
    }

    // MARK: Settings

    func testSettingsOfferTheDelayChoicesInEveryLanguage() throws {
        var tallest: (String, CGFloat) = ("", 0)
        for language in languages {
            let defaults = try TestDefaults.make(self)
            defaults.set(5, forKey: LockConfiguration.Key.startDelaySeconds)
            let view = ViewHost.host(
                SettingsView(isPresented: .constant(true), maxContentHeight: 10_000)
                    .defaultAppStorage(defaults)
                    .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
                    .environment(\.locale, Locale(identifier: language))
            )
            if view.frame.height > tallest.1 { tallest = (language, view.frame.height) }
            ViewHost.snapshot(view, named: "settings-delay-\(language)")
        }
        print("tallest Settings with the delay: \(tallest.0) \(tallest.1) pt")
        XCTAssertGreaterThan(tallest.1, 700, "the new section is part of the layout")
    }

    func testTheDelayLabelsAreDistinctInEveryLanguage() {
        for language in languages {
            let locale = Locale(identifier: language)
            let labels = LockConfiguration.startDelayChoices.filter { $0 > 0 }.map {
                LockConfiguration.unlockChoiceTitle($0, locale: locale)
            }
            XCTAssertEqual(Set(labels).count, labels.count, language)
        }
    }

    func testTheStoredChoiceSelectsAPickerTagThatExists() throws {
        // A stored value outside the choices would leave the picker blank.
        for stored in [0, 3, 5, 10, 7, -2, 99] {
            let defaults = try TestDefaults.make(self)
            defaults.set(stored, forKey: LockConfiguration.Key.startDelaySeconds)
            let loaded = LockConfiguration.load(from: defaults).startDelaySeconds
            XCTAssertTrue(LockConfiguration.startDelayChoices.contains(loaded), "stored \(stored) → \(loaded)")
        }
    }
}
