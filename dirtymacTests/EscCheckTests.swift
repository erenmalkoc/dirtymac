import XCTest
import AppKit
@testable import dirtymac

/// The value type behind the "hold Esc" check, run against a hand-set clock.
final class EscCheckTests: XCTestCase {
    private var check = EscCheck()

    override func setUp() { check = EscCheck() }

    func testItIsAsLongAsTheRealExit() {
        XCTAssertEqual(EscCheck.defaultHoldDuration, KeyboardBlocker.escHoldDuration)
        XCTAssertEqual(EscCheck().holdDuration, 3)
    }

    func testHoldingForTheFullDurationPasses() {
        check.escDown(at: 10)
        check.tick(at: 12.99)
        XCTAssertFalse(check.passed)
        check.tick(at: 13)
        XCTAssertTrue(check.passed)
        XCTAssertEqual(check.progress(at: 99), 1)
    }

    func testReleasingEarlyStartsOver() {
        check.escDown(at: 10)
        check.tick(at: 12)
        XCTAssertEqual(check.progress(at: 12), 2.0 / 3, accuracy: 0.001)
        check.escUp(at: 12.5)
        XCTAssertFalse(check.passed)
        XCTAssertEqual(check.progress(at: 20), 0)

        // The next press counts from its own start.
        check.escDown(at: 20)
        check.tick(at: 22.9)
        XCTAssertFalse(check.passed)
        check.tick(at: 23)
        XCTAssertTrue(check.passed)
    }

    func testTheKeyRepeatDoesNotRestartTheTimer() {
        check.escDown(at: 10)
        for t in stride(from: 10.5, through: 12.5, by: 0.5) { check.escDown(at: t) }
        check.tick(at: 13)
        XCTAssertTrue(check.passed, "the repeats of one press must not move its start")
    }

    func testReleasingAfterTheDurationWithoutATickStillPasses() {
        check.escDown(at: 10)
        check.escUp(at: 13.2)
        XCTAssertTrue(check.passed)
    }

    func testAPassStaysAfterTheReleaseAndLaterPressesChangeNothing() {
        check.escDown(at: 10)
        check.tick(at: 13)
        check.escUp(at: 13.1)
        check.escDown(at: 20)
        check.escUp(at: 20.1)
        XCTAssertTrue(check.passed)
        XCTAssertNil(check.heldSince)
    }

    func testProgressIsClampedAndSurvivesAClockThatWentBack() {
        XCTAssertEqual(check.progress(at: 5), 0, "nothing held")
        check.escDown(at: 10)
        XCTAssertEqual(check.progress(at: 9), 0, "clock behind the press")
        XCTAssertEqual(check.progress(at: 10), 0)
        XCTAssertEqual(check.progress(at: 11.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(check.progress(at: 12.9), 0.9667, accuracy: 0.001)
        check.tick(at: 9)
        XCTAssertFalse(check.passed, "a clock that went back passes nothing")
    }

    func testResetForgetsEverything() {
        check.escDown(at: 10)
        check.tick(at: 14)
        XCTAssertTrue(check.passed)
        check.reset()
        XCTAssertFalse(check.passed)
        XCTAssertEqual(check.progress(at: 14), 0)
        check.escDown(at: 14)
        XCTAssertEqual(check.heldSince, 14)
    }

    func testAShorterDurationCanBeSetForTests() {
        var quick = EscCheck(holdDuration: 0.5)
        quick.escDown(at: 0)
        quick.tick(at: 0.49)
        XCTAssertFalse(quick.passed)
        quick.tick(at: 0.5)
        XCTAssertTrue(quick.passed)
    }
}

/// The listener: what it takes from the keyboard, what it leaves, and that
/// it lets go.
@MainActor
final class EscCheckModelTests: XCTestCase {
    private let esc: UInt16 = 53
    private var clock: TimeInterval = 100

    private func make(holdDuration: TimeInterval = 3) -> EscCheckModel {
        EscCheckModel(holdDuration: holdDuration, now: { [unowned self] in clock })
    }

    private func hold(_ model: EscCheckModel, for seconds: TimeInterval) {
        model.handle(keyCode: esc, isDown: true, isRepeat: false)
        clock += seconds
        model.refresh()
    }

    // MARK: The key logic

    func testHoldingEscFillsTheBarThenPasses() {
        let model = make()
        model.handle(keyCode: esc, isDown: true, isRepeat: false)
        clock += 1.5
        model.refresh()
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.01)
        XCTAssertFalse(model.passed)
        clock += 1.5
        model.refresh()
        XCTAssertTrue(model.passed)
        XCTAssertEqual(model.progress, 1)
    }

    func testReleasingEarlyEmptiesTheBar() {
        let model = make()
        hold(model, for: 2)
        model.handle(keyCode: esc, isDown: false, isRepeat: false)
        XCTAssertEqual(model.progress, 0)
        XCTAssertFalse(model.passed)
    }

    func testOtherKeysAreNeitherTakenNorCounted() {
        let model = make()
        for keyCode: UInt16 in [0, 36, 48, 49, 51, 123] {
            XCTAssertFalse(model.handle(keyCode: keyCode, isDown: true, isRepeat: false), "key \(keyCode)")
            XCTAssertFalse(model.handle(keyCode: keyCode, isDown: false, isRepeat: false), "key \(keyCode)")
        }
        clock += 10
        model.refresh()
        XCTAssertFalse(model.passed)
        XCTAssertEqual(model.progress, 0)
    }

    func testEscIsTakenWhileTheCheckRuns() {
        let model = make()
        XCTAssertTrue(model.handle(keyCode: esc, isDown: true, isRepeat: false))
        XCTAssertTrue(model.handle(keyCode: esc, isDown: true, isRepeat: true))
        XCTAssertTrue(model.handle(keyCode: esc, isDown: false, isRepeat: false))
    }

    func testRepeatsDoNotRestartTheCount() {
        let model = make()
        model.handle(keyCode: esc, isDown: true, isRepeat: false)
        for _ in 0..<5 {
            clock += 0.7
            model.handle(keyCode: esc, isDown: true, isRepeat: true)
        }
        model.refresh()
        XCTAssertTrue(model.passed, "more than three seconds of repeats of one press")
    }

    /// The popover closes on Esc, and a held key repeats. If the repeats
    /// after the pass reached the popover it would close at the moment of
    /// success, and reopening would start the check over.
    func testTheHeldPressStaysTakenUntilItIsReleased() {
        let model = make()
        hold(model, for: 3)
        XCTAssertTrue(model.passed)
        XCTAssertTrue(model.handle(keyCode: esc, isDown: true, isRepeat: true), "a repeat of the held press")
        XCTAssertTrue(model.handle(keyCode: esc, isDown: true, isRepeat: true))
        XCTAssertTrue(model.handle(keyCode: esc, isDown: false, isRepeat: false), "its release")
    }

    func testAfterTheReleaseEscBelongsToThePanelAgain() {
        let model = make()
        hold(model, for: 3)
        model.handle(keyCode: esc, isDown: false, isRepeat: false)
        XCTAssertFalse(model.handle(keyCode: esc, isDown: true, isRepeat: false), "a fresh press closes the panel as usual")
        XCTAssertFalse(model.handle(keyCode: esc, isDown: false, isRepeat: false))
        XCTAssertTrue(model.passed, "and the pass stays")
    }

    func testAReleaseOfAPressWeNeverSawIsLeftAlone() {
        let model = make()
        hold(model, for: 3)
        model.handle(keyCode: esc, isDown: false, isRepeat: false)
        XCTAssertFalse(model.handle(keyCode: esc, isDown: false, isRepeat: false))
    }

    func testResetStartsAFreshCheck() {
        let model = make()
        hold(model, for: 3)
        XCTAssertTrue(model.passed)
        model.reset()
        XCTAssertFalse(model.passed)
        XCTAssertEqual(model.progress, 0)
        XCTAssertTrue(model.handle(keyCode: esc, isDown: true, isRepeat: false), "taken again")
    }

    // MARK: Listening

    func testItListensOnlyBetweenStartAndStop() {
        let model = make()
        XCTAssertFalse(model.isListening)
        model.start()
        XCTAssertTrue(model.isListening)
        model.stop()
        XCTAssertFalse(model.isListening)
        model.stop()   // a second stop is harmless
        XCTAssertFalse(model.isListening)
    }

    func testStartingTwiceLeavesOneListenerAndStartsOver() {
        let model = make()
        model.start()
        hold(model, for: 3)
        XCTAssertTrue(model.passed)
        model.start()
        XCTAssertFalse(model.passed, "a new start is a new check")
        XCTAssertEqual(model.progress, 0)
        model.stop()
        XCTAssertFalse(model.isListening, "one stop ends it: there was only one monitor")
    }

    func testARealEscEventReachesTheCheckAndIsTaken() throws {
        let model = make()
        model.start()
        defer { model.stop() }

        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: esc))
        }
        // Dispatched the way macOS delivers it, through the app's event
        // handling, so the local monitor is really in the path. A taken
        // event goes no further (and so makes no beep in the test run).
        NSApp.sendEvent(try event(.keyDown))
        clock += 1
        model.refresh()
        XCTAssertGreaterThan(model.progress, 0.3, "the monitor passed the key to the check")
        NSApp.sendEvent(try event(.keyUp))
        XCTAssertEqual(model.progress, 0, "released early")
    }

    func testAStoppedCheckHearsNothing() throws {
        let model = make()
        model.start()
        model.stop()
        // handle() is the monitor's body: with no monitor installed it is
        // never called, so nothing can reach the check from the keyboard.
        XCTAssertFalse(model.isListening)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        // A non-Esc key up reaches no check and makes no beep.
        NSApp.sendEvent(event)
        XCTAssertEqual(model.progress, 0)
    }

    func testTheTimerAdvancesTheBarOnItsOwn() async throws {
        let model = EscCheckModel(holdDuration: 0.15)   // the real clock
        model.start()
        defer { model.stop() }
        model.handle(keyCode: esc, isDown: true, isRepeat: false)
        for _ in 0..<40 where !model.passed {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(model.passed, "the timer, not a manual refresh, finished the hold")
    }
}
