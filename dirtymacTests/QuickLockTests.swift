import XCTest
import AppKit
@testable import dirtymac

/// One-click "lock for N minutes".
@MainActor
final class QuickLockTests: XCTestCase {
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    private func stored(
        mode: LockMode = .basic,
        modifiers: Bool = true,
        media: Bool = true,
        mouse: Bool = false,
        seconds: Int = 0
    ) -> LockConfiguration {
        LockConfiguration(
            mode: mode, blockModifierKeys: modifiers, blockMediaKeys: media,
            blockMouseAndTrackpad: mouse, autoUnlockSeconds: seconds
        )
    }

    private func decide(
        _ seconds: Int = 300, active: Bool = false, permission: Bool = true, _ configuration: LockConfiguration
    ) -> QuickLockDecision {
        QuickLock.decide(seconds: seconds, isActive: active, hasPermission: permission, storedConfiguration: configuration)
    }

    // MARK: The lengths

    func testTheLengthsAreSortedKeyboardOnlyChoicesTheSettingsOfferToo() {
        let lengths = QuickLock.durations
        XCTAssertEqual(lengths, lengths.sorted())
        XCTAssertEqual(Set(lengths).count, lengths.count)
        XCTAssertEqual(lengths.first, 60)
        XCTAssertEqual(lengths.last, 28_800, "up to eight hours")
        for seconds in lengths {
            XCTAssertTrue(LockConfiguration.unlockChoices.contains(seconds), "\(seconds) s is a choice in Settings too")
        }
    }

    func testEveryLengthIsALockTheIconCanEndWithAClick() {
        for seconds in QuickLock.durations {
            let configuration = QuickLock.configuration(seconds: seconds, storedConfiguration: stored())
            XCTAssertFalse(configuration.blockMouseAndTrackpad, "\(seconds) s")
            XCTAssertFalse(configuration.requiresEscCheck, "\(seconds) s needs no Esc check")
            XCTAssertEqual(configuration.autoUnlockSeconds, seconds, "the length is kept whole")
        }
    }

    // MARK: Deciding

    func testAnOrdinaryClickLocksWithTheChosenLength() {
        guard case .lock(let configuration) = decide(300, stored()) else { return XCTFail("should lock") }
        XCTAssertEqual(configuration.autoUnlockSeconds, 300)
        XCTAssertFalse(configuration.blockMouseAndTrackpad)
    }

    func testAlreadyLockedStartsNothing() {
        XCTAssertEqual(decide(active: true, stored()), .alreadyLocked)
        XCTAssertEqual(decide(active: true, permission: false, stored(mouse: true)), .alreadyLocked)
    }

    func testWithoutPermissionThePanelIsOpenedForTheUsualPrompt() {
        XCTAssertEqual(decide(permission: false, stored()), .openPanel)
    }

    func testAFrozenMouseNeverLocksFromTheMenu() {
        // The panel asks for the confirmation, and the Esc check above 5 min.
        for seconds in QuickLock.durations {
            XCTAssertEqual(decide(seconds, stored(mode: .advanced, mouse: true, seconds: 120)), .openPanel, "\(seconds) s")
        }
    }

    func testTheMenuIsOfferedOnlyWhileTheMouseStaysFree() {
        XCTAssertTrue(QuickLock.isOffered(storedConfiguration: stored()))
        XCTAssertTrue(QuickLock.isOffered(storedConfiguration: stored(mode: .advanced, mouse: false)))
        XCTAssertFalse(QuickLock.isOffered(storedConfiguration: stored(mode: .advanced, mouse: true)))
        XCTAssertTrue(QuickLock.isOffered(storedConfiguration: stored(mode: .basic, mouse: true)),
                      "Basic never freezes the mouse, whatever was stored")
    }

    // MARK: What gets locked

    func testBasicModeBecomesItsKeyboardOnlySetWithATimer() {
        let configuration = QuickLock.configuration(seconds: 900, storedConfiguration: stored(mode: .basic, seconds: 0))
        XCTAssertEqual(configuration.autoUnlockSeconds, 900)
        XCTAssertTrue(configuration.blockModifierKeys)
        XCTAssertTrue(configuration.blockMediaKeys)
        XCTAssertFalse(configuration.blockMouseAndTrackpad)
    }

    func testBasicIgnoresWhatAdvancedOptionsWereStoredEarlier() {
        let configuration = QuickLock.configuration(
            seconds: 60, storedConfiguration: stored(mode: .basic, modifiers: false, media: false, mouse: true))
        XCTAssertTrue(configuration.blockModifierKeys, "Basic is a fixed set")
        XCTAssertTrue(configuration.blockMediaKeys)
        XCTAssertFalse(configuration.blockMouseAndTrackpad)
    }

    func testAdvancedKeepsItsOwnBlockChoices() {
        let configuration = QuickLock.configuration(
            seconds: 1800, storedConfiguration: stored(mode: .advanced, modifiers: false, media: true, seconds: 30))
        XCTAssertFalse(configuration.blockModifierKeys)
        XCTAssertTrue(configuration.blockMediaKeys)
        XCTAssertEqual(configuration.autoUnlockSeconds, 1800, "the chosen length replaces the stored timer")
    }

    func testTheKeepAwakeChoiceTravelsAlong() {
        var off = stored()
        off.keepDisplayAwake = false
        XCTAssertFalse(QuickLock.configuration(seconds: 60, storedConfiguration: off).keepDisplayAwake)
        XCTAssertTrue(QuickLock.configuration(seconds: 60, storedConfiguration: stored()).keepDisplayAwake)
    }

    // MARK: The controller

    private func controller(
        _ rig: BlockerRig,
        stored configuration: LockConfiguration,
        opened: @escaping () -> Void = {}
    ) -> QuickLockController {
        QuickLockController(blocker: rig.blocker, storedConfiguration: { configuration }, openPanel: opened)
    }

    func testAClickStartsALockOfThatLengthThatEndsByItself() {
        let rig = BlockerRig()
        controller(rig, stored: stored()).run(seconds: 300)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 300)
        XCTAssertEqual(rig.tap.installedMask, EventMask.build(for: QuickLock.configuration(seconds: 300, storedConfiguration: stored())))
        XCTAssertTrue(rig.displayWake.isHeld)

        rig.clock.advance(by: 299)
        XCTAssertTrue(rig.blocker.isActive)
        rig.clock.advance(by: 2)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .autoUnlock)
    }

    func testAQuickLockStillEndsWithHoldEscAndWithTheIconClick() {
        let esc = BlockerRig()
        controller(esc, stored: stored()).run(seconds: 3600)
        esc.tap.send(.escDown)
        esc.clock.advance(by: 3.2)
        esc.tap.send(.escUp)
        esc.clock.advance(by: 0)
        XCTAssertFalse(esc.blocker.isActive)

        let click = BlockerRig()
        controller(click, stored: stored()).run(seconds: 3600)
        click.blocker.stop(reason: .clicked)
        XCTAssertFalse(click.blocker.isActive)
    }

    func testWithoutPermissionTheControllerOpensThePanelAndLocksNothing() {
        let rig = BlockerRig()
        rig.permission.trusted = false
        var opened = 0
        controller(rig, stored: stored(), opened: { opened += 1 }).run(seconds: 300)
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.tap.installCount, 0)
    }

    func testAFrozenMouseOpensThePanelInsteadOfLockingBlind() {
        let rig = BlockerRig()
        var opened = 0
        controller(rig, stored: stored(mode: .advanced, mouse: true, seconds: 900), opened: { opened += 1 }).run(seconds: 900)
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(rig.blocker.isActive, "never a frozen-mouse lock without the confirmation")
        XCTAssertEqual(rig.tap.installCount, 0)
    }

    func testAnotherClickWhileLockedChangesNothing() {
        let rig = BlockerRig()
        var opened = 0
        let quick = controller(rig, stored: stored(), opened: { opened += 1 })
        quick.run(seconds: 300)
        quick.run(seconds: 3600)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 300, "the running lock keeps its length")
        XCTAssertEqual(rig.tap.installCount, 1)
        XCTAssertEqual(opened, 0)
    }

    func testPermissionIsReReadAtClickTime() {
        let rig = BlockerRig()
        rig.permission.trusted = false
        rig.blocker.refreshPermission()
        XCTAssertFalse(rig.blocker.hasPermission)
        rig.permission.trusted = true   // granted since the panel last looked
        controller(rig, stored: stored()).run(seconds: 60)
        XCTAssertTrue(rig.blocker.isActive)
    }

    // MARK: The menu item

    func testTheMenuListsEveryLengthWithItsSecondsAndAnAction() throws {
        let rig = BlockerRig()
        let quick = controller(rig, stored: stored())
        let item = try XCTUnwrap(quick.makeMenuItem(title: "Lock for", locale: Locale(identifier: "en")))
        XCTAssertEqual(item.title, "Lock for")
        let submenu = try XCTUnwrap(item.submenu)
        XCTAssertEqual(submenu.items.map(\.tag), QuickLock.durations)
        XCTAssertEqual(submenu.items.map(\.title), ["1 min", "5 min", "15 min", "30 min", "1 hr", "2 hr", "4 hr", "8 hr"])
        for entry in submenu.items {
            XCTAssertTrue(entry.target === quick)
            XCTAssertNotNil(entry.action)
        }
    }

    func testChoosingAMenuEntryLocksForItsLength() throws {
        let rig = BlockerRig()
        let quick = controller(rig, stored: stored())
        let item = try XCTUnwrap(quick.makeMenuItem(title: "Lock for", locale: Locale(identifier: "en")))
        let entry = try XCTUnwrap(item.submenu?.items.first { $0.tag == 900 })
        // Sent the way AppKit sends a menu action.
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(entry.action), to: entry.target, from: entry))
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 900)
    }

    func testTheEntryIsLeftOutWhileLockedOrWithAFrozenMouse() {
        let locked = BlockerRig()
        let quick = controller(locked, stored: stored())
        quick.run(seconds: 60)
        XCTAssertNil(quick.makeMenuItem(title: "Lock for", locale: Locale(identifier: "en")))

        let frozen = BlockerRig()
        let frozenQuick = controller(frozen, stored: stored(mode: .advanced, mouse: true))
        XCTAssertNil(frozenQuick.makeMenuItem(title: "Lock for", locale: Locale(identifier: "en")))
    }

    func testTheLengthsReadDifferentlyInEveryLanguage() throws {
        let rig = BlockerRig()
        let quick = controller(rig, stored: stored())
        for language in languages {
            let item = try XCTUnwrap(quick.makeMenuItem(title: "x", locale: Locale(identifier: language)))
            let titles = try XCTUnwrap(item.submenu).items.map(\.title)
            XCTAssertEqual(Set(titles).count, titles.count, language)
            XCTAssertFalse(titles.contains(""), language)
        }
    }

    func testTheMenuTitleIsTranslatedInEveryLanguage() {
        for language in LanguagePreference.allCases where language != .system {
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return XCTFail(language.rawValue) }
            let title = bundle.localizedString(forKey: "Lock for", value: "<missing>", table: "Localizable")
            XCTAssertNotEqual(title, "<missing>", language.rawValue)
            XCTAssertFalse(title.isEmpty)
        }
    }

    func testTheDelegateHasAQuickLockWiredToItsBlocker() throws {
        let delegate = try XCTUnwrap(AppDelegate.shared)
        // Built lazily, so reading it must not fail and must not lock anything.
        _ = delegate.quickLock
        XCTAssertFalse(delegate.blocker.isActive)
    }
}
