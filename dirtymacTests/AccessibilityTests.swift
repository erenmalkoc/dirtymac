import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// What VoiceOver is told, and what stands still when motion is reduced.
@MainActor
final class AccessibilityTests: XCTestCase {
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    private final class FakeAnnouncer: Announcing {
        private(set) var said: [String] = []
        func announce(_ text: String) { said.append(text) }
    }

    private func words(_ announcement: StatusAnnouncement) -> String {
        switch announcement {
        case .waitingToLock(let s): return "wait \(s)"
        case .locked: return "locked"
        case .unlocked: return "unlocked"
        case .escHold(let r): return "esc \(r)"
        case .letGoOfEsc: return "let go"
        case .autoUnlockIn(let s): return "auto \(s)"
        }
    }

    private func make(enabled: @escaping () -> Bool = { true }) -> (BlockerRig, FakeAnnouncer, StatusAnnouncer) {
        let rig = BlockerRig()
        let announcer = FakeAnnouncer()
        let coordinator = StatusAnnouncer(blocker: rig.blocker, announcer: announcer, isEnabled: enabled, words: words)
        return (rig, announcer, coordinator)
    }

    // MARK: Reduce Motion

    func testMotionIsLeftOutWhenReduced() {
        XCTAssertNil(MotionPolicy.animation(.easeInOut, reduceMotion: true))
        XCTAssertNotNil(MotionPolicy.animation(.easeInOut, reduceMotion: false))
    }

    func testTheLockedIconOnlyBreathesWithMotionAllowed() {
        XCTAssertTrue(MotionPolicy.iconBreathes(isLocked: true, reduceMotion: false))
        XCTAssertFalse(MotionPolicy.iconBreathes(isLocked: true, reduceMotion: true))
        XCTAssertFalse(MotionPolicy.iconBreathes(isLocked: false, reduceMotion: false))
        XCTAssertFalse(MotionPolicy.iconBreathes(isLocked: false, reduceMotion: true))
    }

    func testTheBreathingAnimationIsAddedOnceAndRemovedCleanly() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        view.wantsLayer = true
        XCTAssertNil(view.layer?.animation(forKey: "breathe"))

        AppDelegate.setBreathing(true, on: view)
        let first = view.layer?.animation(forKey: "breathe")
        XCTAssertNotNil(first)
        AppDelegate.setBreathing(true, on: view)   // every icon refresh asks again
        XCTAssertTrue(view.layer?.animation(forKey: "breathe") === first, "not restarted on every refresh")

        view.alphaValue = 0.4
        AppDelegate.setBreathing(false, on: view)
        XCTAssertNil(view.layer?.animation(forKey: "breathe"))
        XCTAssertEqual(view.alphaValue, 1, "the icon is back at full strength")
    }

    func testReducedMotionStopsTheBreathingAnimationThatWasRunning() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        view.wantsLayer = true
        AppDelegate.setBreathing(MotionPolicy.iconBreathes(isLocked: true, reduceMotion: false), on: view)
        XCTAssertNotNil(view.layer?.animation(forKey: "breathe"))
        // The user switches Reduce motion on while the lock runs.
        AppDelegate.setBreathing(MotionPolicy.iconBreathes(isLocked: true, reduceMotion: true), on: view)
        XCTAssertNil(view.layer?.animation(forKey: "breathe"))
    }

    func testTheSystemSettingCanBeRead() {
        _ = MotionPolicy.systemReducesMotion   // either answer is right on a given Mac
    }

    // MARK: What is said

    func testNothingChangedSaysNothing() {
        let snapshot = StatusSnapshot(isActive: true, escHold: .idle, lockCountdown: nil, autoUnlockRemaining: 100)
        XCTAssertEqual(StatusAnnouncements.changes(from: snapshot, to: snapshot), [])
        XCTAssertEqual(StatusAnnouncements.changes(from: StatusSnapshot(), to: StatusSnapshot()), [])
    }

    func testTheLockBeginningAndEndingAreSaid() {
        let idle = StatusSnapshot()
        let locked = StatusSnapshot(isActive: true)
        XCTAssertEqual(StatusAnnouncements.changes(from: idle, to: locked), [.locked])
        XCTAssertEqual(StatusAnnouncements.changes(from: locked, to: idle), [.unlocked])
    }

    func testTheWaitIsCountedOutLoudOncePerSecond() {
        var old = StatusSnapshot()
        var said: [StatusAnnouncement] = []
        for seconds in [5, 5, 4, 3, 3, 2, 1] {
            var next = old
            next.lockCountdown = seconds
            said += StatusAnnouncements.changes(from: old, to: next)
            old = next
        }
        XCTAssertEqual(said, [.waitingToLock(seconds: 5), .waitingToLock(seconds: 4), .waitingToLock(seconds: 3),
                              .waitingToLock(seconds: 2), .waitingToLock(seconds: 1)])
    }

    func testTheEscHoldIsCountedAndTheReleaseIsAsked() {
        var old = StatusSnapshot(isActive: true)
        var said: [StatusAnnouncement] = []
        let states: [EscHoldState] = [
            .holding(remaining: 3, progress: 0), .holding(remaining: 3, progress: 0.3),
            .holding(remaining: 2, progress: 0.4), .holding(remaining: 2, progress: 0.6),
            .holding(remaining: 1, progress: 0.7), .letGo, .letGo,
        ]
        for state in states {
            var next = old
            next.escHold = state
            said += StatusAnnouncements.changes(from: old, to: next)
            old = next
        }
        XCTAssertEqual(said, [.escHold(remaining: 3), .escHold(remaining: 2), .escHold(remaining: 1), .letGoOfEsc])
    }

    func testAnEarlyReleaseSaysNothingMoreAndAFreshHoldStartsAgain() {
        let holding = StatusSnapshot(isActive: true, escHold: .holding(remaining: 2, progress: 0.4))
        let released = StatusSnapshot(isActive: true, escHold: .idle)
        XCTAssertEqual(StatusAnnouncements.changes(from: holding, to: released), [])
        let again = StatusSnapshot(isActive: true, escHold: .holding(remaining: 3, progress: 0))
        XCTAssertEqual(StatusAnnouncements.changes(from: released, to: again), [.escHold(remaining: 3)])
    }

    func testTheAutoUnlockIsAnnouncedAtAMinuteAndAtTenSecondsOnly() {
        var old = StatusSnapshot(isActive: true, autoUnlockRemaining: 120)
        var said: [StatusAnnouncement] = []
        for remaining in stride(from: 119, through: 0, by: -1) {
            var next = old
            next.autoUnlockRemaining = remaining
            said += StatusAnnouncements.changes(from: old, to: next)
            old = next
        }
        XCTAssertEqual(said, [.autoUnlockIn(seconds: 60), .autoUnlockIn(seconds: 10)])
    }

    func testAMilestoneIsNotRepeatedWhileTheNumberStaysPut() {
        let a = StatusSnapshot(isActive: true, autoUnlockRemaining: 60)
        XCTAssertEqual(StatusAnnouncements.changes(from: a, to: a), [])
        let b = StatusSnapshot(isActive: true, autoUnlockRemaining: 59)
        XCTAssertEqual(StatusAnnouncements.changes(from: a, to: b), [])
    }

    func testTheTimerIsSilentOnceTheLockIsOver() {
        let running = StatusSnapshot(isActive: true, autoUnlockRemaining: 11)
        let over = StatusSnapshot(isActive: false, autoUnlockRemaining: 10)
        XCTAssertEqual(StatusAnnouncements.changes(from: running, to: over), [.unlocked])
    }

    // MARK: The coordinator against a real blocker

    func testAWholeLockIsNarratedInOrder() {
        let (rig, announcer, coordinator) = make()
        withExtendedLifetime(coordinator) {
            rig.blocker.beginLock(LockConfiguration(mode: .advanced, autoUnlockSeconds: 120, startDelaySeconds: 3))
            rig.clock.advance(by: 3)      // the wait ends, the lock starts
            rig.clock.advance(by: 60)     // a minute into a 120 s lock: 60 s left
            rig.clock.advance(by: 50)     // 10 s left
            rig.tap.send(.escDown)
            rig.clock.advance(by: 3.2)
            rig.tap.send(.escUp)
            rig.clock.advance(by: 0)
        }
        XCTAssertEqual(announcer.said, [
            "wait 3", "wait 2", "wait 1", "locked", "auto 60", "auto 10",
            "esc 3", "esc 2", "esc 1", "let go", "unlocked",
        ])
    }

    func testNothingIsSaidWithoutVoiceOver() {
        let (rig, announcer, coordinator) = make(enabled: { false })
        withExtendedLifetime(coordinator) {
            rig.blocker.beginLock(LockConfiguration(mode: .advanced, startDelaySeconds: 3))
            rig.clock.advance(by: 3)
            rig.blocker.stop(reason: .clicked)
        }
        XCTAssertEqual(announcer.said, [])
    }

    func testTurningVoiceOverOnMidLockOnlySaysWhatHappensNext() {
        var enabled = false
        let (rig, announcer, coordinator) = make(enabled: { enabled })
        withExtendedLifetime(coordinator) {
            rig.blocker.start(LockConfiguration(mode: .advanced, autoUnlockSeconds: 120))
            enabled = true
            rig.clock.advance(by: 10)
            XCTAssertEqual(announcer.said, [], "the lock began before anyone was listening")
            rig.blocker.stop(reason: .clicked)
        }
        XCTAssertEqual(announcer.said, ["unlocked"])
    }

    func testACancelledWaitSaysWhatItCountedAndNothingAfter() {
        let (rig, announcer, coordinator) = make()
        withExtendedLifetime(coordinator) {
            rig.blocker.beginLock(LockConfiguration(mode: .advanced, startDelaySeconds: 5))
            rig.clock.advance(by: 1)
            rig.blocker.cancelPendingLock()
            rig.clock.advance(by: 10)
        }
        XCTAssertEqual(announcer.said, ["wait 5", "wait 4"])
    }

    func testTheCoordinatorStopsListeningWhenItGoesAway() {
        let rig = BlockerRig()
        let announcer = FakeAnnouncer()
        var coordinator: StatusAnnouncer? = StatusAnnouncer(blocker: rig.blocker, announcer: announcer, isEnabled: { true }, words: words)
        rig.blocker.start(LockConfiguration())
        coordinator = nil
        rig.blocker.stop(reason: .clicked)
        XCTAssertEqual(announcer.said, ["locked"], "nothing after it was dropped")
        XCTAssertNil(coordinator)
    }

    // MARK: The words

    func testEveryAnnouncementReadsInEveryLanguageWithItsNumber() {
        let announcements: [StatusAnnouncement] = [
            .waitingToLock(seconds: 4), .locked, .unlocked, .escHold(remaining: 2), .letGoOfEsc, .autoUnlockIn(seconds: 60),
        ]
        for language in languages {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return XCTFail(language) }
            var seen = Set<String>()
            for announcement in announcements {
                let text = announcement.text(bundle: bundle)
                XCTAssertFalse(text.isEmpty, "\(language) \(announcement)")
                XCTAssertFalse(text.contains("%"), "\(language) \(announcement): \(text)")
                seen.insert(text)
                switch announcement {
                case .waitingToLock: XCTAssertTrue(text.contains("4"), "\(language): \(text)")
                case .escHold: XCTAssertTrue(text.contains("2"), "\(language): \(text)")
                case .autoUnlockIn: XCTAssertTrue(text.contains("01:00"), "\(language): \(text)")
                default: break
                }
            }
            XCTAssertEqual(seen.count, announcements.count, "\(language): each says something different")
        }
    }

    func testTheRealAnnouncerCanBeCalled() {
        // Posts to the system. With VoiceOver off nothing is heard, and it must not crash.
        VoiceOverAnnouncer().announce("test")
    }

    // MARK: Labels

    func testTheUpdateNoticeHidesItsDecorativeIconFromVoiceOver() throws {
        // Looked at in the source: the glyph carries no meaning of its own.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dirtymac/UpdateNoticeView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains(".accessibilityHidden(true)"))
    }
}
