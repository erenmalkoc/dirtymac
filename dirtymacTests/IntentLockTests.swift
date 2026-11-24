import XCTest
import AppIntents
@testable import dirtymac

/// The Shortcuts action with and without its optional length.
@MainActor
final class IntentLockTests: XCTestCase {
    private let basic = LockConfiguration()
    private func advanced(modifiers: Bool = true, seconds: Int = 0, mouse: Bool = false) -> LockConfiguration {
        LockConfiguration(mode: .advanced, blockModifierKeys: modifiers, blockMouseAndTrackpad: mouse, autoUnlockSeconds: seconds)
    }

    private func plan(
        _ minutes: Int?, active: Bool = false, permission: Bool = true, secure: Bool = false,
        _ stored: LockConfiguration
    ) -> IntentLockPlan {
        IntentLockPlan.plan(minutes: minutes, isActive: active, hasPermission: permission, secureInputOn: secure, storedConfiguration: stored)
    }

    // MARK: The lengths

    func testMinutesBecomeSecondsAndAreKeptInsideTheRange() {
        XCTAssertEqual(IntentLockPlan.seconds(forMinutes: 1), 60)
        XCTAssertEqual(IntentLockPlan.seconds(forMinutes: 5), 300)
        XCTAssertEqual(IntentLockPlan.seconds(forMinutes: 60), 3600)
        XCTAssertEqual(IntentLockPlan.seconds(forMinutes: 480), 28_800)
        XCTAssertEqual(IntentLockPlan.seconds(forMinutes: 1440), 86_400, "a whole day")
        for tooSmall in [0, -1, -600, Int.min] {
            XCTAssertEqual(IntentLockPlan.seconds(forMinutes: tooSmall), 60, "\(tooSmall)")
        }
        for tooBig in [1441, 100_000, Int.max] {
            XCTAssertEqual(IntentLockPlan.seconds(forMinutes: tooBig), 86_400, "\(tooBig)")
        }
    }

    func testTheRangeStartsWhereTheQuickLockMenuDoesAndEndsAtTheDay() {
        XCTAssertEqual(IntentLockPlan.minMinutes * 60, QuickLock.durations.first)
        XCTAssertEqual(IntentLockPlan.maxMinutes * 60, LockConfiguration.maxAutoUnlockSeconds)
    }

    // MARK: Without a length: exactly as before

    func testNoLengthLocksWithTheStoredSettings() {
        XCTAssertEqual(plan(nil, basic), .lock(nil))
        XCTAssertEqual(plan(nil, advanced(seconds: 120)), .lock(nil))
    }

    func testTheOldGatesStillSendTheUserToThePanel() {
        XCTAssertEqual(plan(nil, permission: false, basic), .openPanel)
        XCTAssertEqual(plan(nil, secure: true, basic), .openPanel)
        XCTAssertEqual(plan(nil, advanced(seconds: 120, mouse: true)), .openPanel)
        XCTAssertEqual(plan(nil, active: true, basic), .alreadyLocked)
    }

    // MARK: With a length

    func testALengthLocksForThatLong() {
        guard case .lock(let configuration?) = plan(15, basic) else { return XCTFail("should lock with a configuration") }
        XCTAssertEqual(configuration.autoUnlockSeconds, 900)
        XCTAssertFalse(configuration.blockMouseAndTrackpad)
        XCTAssertTrue(configuration.blockModifierKeys)
    }

    func testALengthKeepsAdvancedBlockChoices() {
        guard case .lock(let configuration?) = plan(30, advanced(modifiers: false, seconds: 60)) else { return XCTFail("should lock") }
        XCTAssertFalse(configuration.blockModifierKeys)
        XCTAssertEqual(configuration.autoUnlockSeconds, 1800)
    }

    func testAnOutOfRangeLengthIsClampedNotRefused() {
        guard case .lock(let tiny?) = plan(0, basic), case .lock(let huge?) = plan(10_000, basic) else {
            return XCTFail("should lock")
        }
        XCTAssertEqual(tiny.autoUnlockSeconds, 60)
        XCTAssertEqual(huge.autoUnlockSeconds, 86_400)
        XCTAssertFalse(huge.requiresEscCheck)
    }

    func testALengthNeverGetsAroundTheGates() {
        for minutes in [1, 15, 60] {
            XCTAssertEqual(plan(minutes, permission: false, basic), .openPanel, "no permission, \(minutes) min")
            XCTAssertEqual(plan(minutes, secure: true, basic), .openPanel, "secure input, \(minutes) min")
            XCTAssertEqual(plan(minutes, advanced(seconds: 120, mouse: true)), .openPanel, "frozen mouse, \(minutes) min")
            XCTAssertEqual(plan(minutes, active: true, basic), .alreadyLocked, "already locked, \(minutes) min")
        }
    }

    func testALengthAboveFiveMinutesNeverReachesAFrozenMouse() {
        // The Esc check cannot be asked of a Shortcut: a frozen mouse goes
        // to the panel whatever length was passed.
        let frozen = advanced(seconds: 900, mouse: true)
        for minutes in [6, 15, 60] {
            XCTAssertEqual(plan(minutes, frozen), .openPanel)
        }
    }

    // MARK: Running it

    private func run(_ rig: BlockerRig, minutes: Int?, stored: LockConfiguration, opened: @escaping () -> Void = {}) {
        LockKeyboardIntent.run(minutes: minutes, blocker: rig.blocker, storedConfiguration: stored, openPanel: opened)
    }

    func testRunningWithoutALengthLocksLikeItAlwaysDid() {
        let rig = BlockerRig()
        run(rig, minutes: nil, stored: basic)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 0, "Basic has no timer")

        let timed = BlockerRig()
        run(timed, minutes: nil, stored: advanced(seconds: 120))
        XCTAssertEqual(timed.blocker.autoUnlockTotal, 120)
    }

    func testRunningWithALengthLocksForThatLongAndEnds() {
        let rig = BlockerRig()
        run(rig, minutes: 10, stored: basic)
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 600)
        XCTAssertTrue(rig.displayWake.isHeld)
        rig.clock.advance(by: 601)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .autoUnlock)
    }

    func testRunningWithAnOutOfRangeLengthStillLocksWithinTheRange() {
        let rig = BlockerRig()
        run(rig, minutes: 99_999, stored: basic)
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 86_400)
    }

    func testRunningWithoutPermissionOpensThePanelAndLocksNothing() {
        let rig = BlockerRig()
        rig.permission.trusted = false
        var opened = 0
        run(rig, minutes: 5, stored: basic, opened: { opened += 1 })
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.tap.installCount, 0)
    }

    func testRunningWithSecureInputOnOpensThePanel() {
        let rig = BlockerRig()
        rig.secureInput.enabled = true
        var opened = 0
        run(rig, minutes: 5, stored: basic, opened: { opened += 1 })
        XCTAssertEqual(opened, 1)
        XCTAssertFalse(rig.blocker.isActive)
    }

    func testRunningWithAFrozenMouseOpensThePanelWhateverTheLength() {
        for minutes in [nil, 1, 15, 60] as [Int?] {
            let rig = BlockerRig()
            var opened = 0
            run(rig, minutes: minutes, stored: advanced(seconds: 900, mouse: true), opened: { opened += 1 })
            XCTAssertEqual(opened, 1, "\(String(describing: minutes))")
            XCTAssertFalse(rig.blocker.isActive)
        }
    }

    func testRunningWhileLockedChangesNothing() {
        let rig = BlockerRig()
        var opened = 0
        run(rig, minutes: 5, stored: basic, opened: { opened += 1 })
        run(rig, minutes: 60, stored: basic, opened: { opened += 1 })
        XCTAssertEqual(rig.blocker.autoUnlockTotal, 300)
        XCTAssertEqual(rig.tap.installCount, 1)
        XCTAssertEqual(opened, 0)
    }

    func testAShortcutLockStillEndsWithHoldEsc() {
        let rig = BlockerRig()
        run(rig, minutes: 60, stored: basic)
        rig.tap.send(.escDown)
        rig.clock.advance(by: 3.2)
        rig.tap.send(.escUp)
        rig.clock.advance(by: 0)
        XCTAssertFalse(rig.blocker.isActive)
        XCTAssertEqual(rig.blocker.lastUnlockReason, .escHeld)
    }

    // MARK: The action as Shortcuts sees it

    func testTheLengthIsOptionalAndEmptyByDefault() {
        XCTAssertNil(LockKeyboardIntent().minutes)
        let intent = LockKeyboardIntent()
        intent.minutes = 5
        XCTAssertEqual(intent.minutes, 5)
    }

    func testTheActionStillOpensTheAppAndKeepsItsTitle() {
        XCTAssertTrue(LockKeyboardIntent.openAppWhenRun)
        XCTAssertEqual(String(localized: LockKeyboardIntent.title), String(localized: "Lock Keyboard for Cleaning"))
    }

    func testTheNewParameterTextIsTranslatedInEveryLanguage() {
        let keys = ["Minutes", "How long to lock, from 1 to 60. Leave it empty to use the timer from Settings."]
        for language in LanguagePreference.allCases where language != .system {
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return XCTFail(language.rawValue) }
            for key in keys {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: "Localizable"), "<missing>", "\(language.rawValue): \(key)")
            }
        }
    }
}
