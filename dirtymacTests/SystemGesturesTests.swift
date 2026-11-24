import XCTest
@testable import dirtymac

/// The trackpad's system gestures are turned off for a lock and put back
/// exactly as they were.
final class FakeGesturePreferences: GesturePreferences {
    var store: [String: Any] = [:]
    private(set) var writes = 0

    private func id(_ s: GestureSetting) -> String { "\(s.domain)/\(s.key)" }
    func value(for setting: GestureSetting) -> Any? { store[id(setting)] }
    func set(_ value: Any?, for setting: GestureSetting) {
        writes += 1
        if let value { store[id(setting)] = value } else { store.removeValue(forKey: id(setting)) }
    }
}

final class FakeDock: DockRestarting {
    private(set) var restarts = 0
    func restart() { restarts += 1 }
}

@MainActor
final class SystemGesturesTests: XCTestCase {
    private let four = GestureSetting(domain: "com.apple.AppleMultitouchTrackpad", key: "TrackpadFourFingerVertSwipeGesture", isBoolean: false)
    private let edge = GestureSetting(domain: "com.apple.AppleMultitouchTrackpad", key: "TrackpadTwoFingerFromRightEdgeSwipeGesture", isBoolean: false)
    private let mission = GestureSetting(domain: "com.apple.dock", key: "showMissionControlGestureEnabled", isBoolean: true)

    private func make(_ preferences: FakeGesturePreferences = FakeGesturePreferences()) throws -> (GestureSuppressor, FakeGesturePreferences, FakeDock, UserDefaults) {
        let defaults = try TestDefaults.make(self)
        let dock = FakeDock()
        let suppressor = GestureSuppressor(preferences: preferences, dock: dock, defaults: defaults, settings: [four, edge, mission])
        return (suppressor, preferences, dock, defaults)
    }

    func testItTurnsEveryGestureOffAndRestartsTheDockOnce() throws {
        let (suppressor, prefs, dock, _) = try make()
        prefs.store = ["\(four.domain)/\(four.key)": 2, "\(edge.domain)/\(edge.key)": 3]
        suppressor.suppress()
        XCTAssertEqual(prefs.value(for: four) as? Int, 0)
        XCTAssertEqual(prefs.value(for: edge) as? Int, 0)
        XCTAssertEqual(prefs.value(for: mission) as? Bool, false)
        XCTAssertEqual(dock.restarts, 1)
        XCTAssertTrue(suppressor.isSuppressed)
    }

    func testRestoreWritesBackExactlyWhatWasThere() throws {
        let (suppressor, prefs, dock, _) = try make()
        prefs.store = ["\(four.domain)/\(four.key)": 2, "\(edge.domain)/\(edge.key)": 3, "\(mission.domain)/\(mission.key)": true]
        suppressor.suppress()
        suppressor.restore()
        XCTAssertEqual(prefs.value(for: four) as? Int, 2)
        XCTAssertEqual(prefs.value(for: edge) as? Int, 3)
        XCTAssertEqual(prefs.value(for: mission) as? Bool, true)
        XCTAssertEqual(dock.restarts, 2)
        XCTAssertFalse(suppressor.isSuppressed)
    }

    func testASettingThatWasNotSetIsRemovedAgainNotLeftAtZero() throws {
        let (suppressor, prefs, _, _) = try make()
        prefs.store = ["\(four.domain)/\(four.key)": 2]
        suppressor.suppress()
        XCTAssertNotNil(prefs.value(for: mission))
        suppressor.restore()
        XCTAssertNil(prefs.value(for: mission), "the Dock's default is on, so an unset key must stay unset")
        XCTAssertNil(prefs.value(for: edge))
        XCTAssertEqual(prefs.value(for: four) as? Int, 2)
    }

    func testSuppressingTwiceNeverWritesTheZerosDownAsTheOriginals() throws {
        let (suppressor, prefs, dock, _) = try make()
        prefs.store = ["\(four.domain)/\(four.key)": 2]
        suppressor.suppress()
        suppressor.suppress()
        XCTAssertEqual(dock.restarts, 1)
        suppressor.restore()
        XCTAssertEqual(prefs.value(for: four) as? Int, 2)
    }

    func testRestoringWhenNothingWasSuppressedChangesNothing() throws {
        let (suppressor, prefs, dock, _) = try make()
        prefs.store = ["\(four.domain)/\(four.key)": 2]
        suppressor.restore()
        XCTAssertEqual(prefs.writes, 0)
        XCTAssertEqual(dock.restarts, 0)
        XCTAssertEqual(prefs.value(for: four) as? Int, 2)
    }

    func testRestoreOnlyHappensOnce() throws {
        let (suppressor, prefs, dock, _) = try make()
        suppressor.suppress()
        suppressor.restore()
        let writes = prefs.writes
        suppressor.restore()
        XCTAssertEqual(prefs.writes, writes)
        XCTAssertEqual(dock.restarts, 2)
    }

    func testTheValuesAreWrittenDownBeforeAnythingIsChanged() throws {
        // A crash right after the first write must still be recoverable.
        final class Spy: GesturePreferences {
            let inner = FakeGesturePreferences()
            var defaults: UserDefaults!
            var savedWhenFirstWritten: Bool?
            func value(for setting: GestureSetting) -> Any? { inner.value(for: setting) }
            func set(_ value: Any?, for setting: GestureSetting) {
                if savedWhenFirstWritten == nil { savedWhenFirstWritten = defaults.array(forKey: GestureSuppressor.savedKey) != nil }
                inner.set(value, for: setting)
            }
        }
        let defaults = try TestDefaults.make(self)
        let spy = Spy()
        spy.defaults = defaults
        spy.inner.store = ["\(four.domain)/\(four.key)": 2]
        let suppressor = GestureSuppressor(preferences: spy, dock: FakeDock(), defaults: defaults, settings: [four])
        suppressor.suppress()
        XCTAssertEqual(spy.savedWhenFirstWritten, true)
    }

    func testANewSuppressorFindsTheValuesAfterACrashAndPutsThemBack() throws {
        let (first, prefs, _, defaults) = try make()
        prefs.store = ["\(four.domain)/\(four.key)": 2, "\(edge.domain)/\(edge.key)": 3]
        first.suppress()
        // The app dies here. The next launch has a fresh object.
        let dock = FakeDock()
        let afterRestart = GestureSuppressor(preferences: prefs, dock: dock, defaults: defaults, settings: [four, edge, mission])
        XCTAssertTrue(afterRestart.isSuppressed)
        afterRestart.restore()
        XCTAssertEqual(prefs.value(for: four) as? Int, 2)
        XCTAssertEqual(prefs.value(for: edge) as? Int, 3)
        XCTAssertNil(prefs.value(for: mission))
        XCTAssertEqual(dock.restarts, 1)
    }

    func testTheListCoversBothTrackpadsAndTheDock() {
        let all = GestureSetting.all
        XCTAssertEqual(all.count, GestureSetting.trackpadDomains.count * GestureSetting.trackpadKeys.count + GestureSetting.dockKeys.count)
        XCTAssertTrue(all.contains(GestureSetting(domain: "com.apple.AppleMultitouchTrackpad", key: "TrackpadFourFingerVertSwipeGesture", isBoolean: false)))
        XCTAssertTrue(all.contains(GestureSetting(domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad", key: "TrackpadThreeFingerHorizSwipeGesture", isBoolean: false)))
        XCTAssertTrue(all.contains(GestureSetting(domain: "com.apple.dock", key: "showMissionControlGestureEnabled", isBoolean: true)))
        XCTAssertEqual(Set(all.map { "\($0.domain)/\($0.key)" }).count, all.count, "no setting twice")
        XCTAssertTrue(all.filter { $0.domain == "com.apple.dock" }.allSatisfy(\.isBoolean))
        XCTAssertTrue(all.filter { $0.domain != "com.apple.dock" }.allSatisfy { !$0.isBoolean })
    }

    func testTheOffValueMatchesTheKind() {
        XCTAssertEqual(four.offValue as? Int, 0)
        XCTAssertEqual(mission.offValue as? Bool, false)
    }

    // MARK: The real preferences, on a domain of their own

    func testTheRealPreferencesKeepNumbersAndBooleansApartAndCanRemoveAKey() {
        let domain = "tech.erenium.dirtymac.tests.gestures-\(UUID().uuidString)"
        let number = GestureSetting(domain: domain, key: "Swipe", isBoolean: false)
        let flag = GestureSetting(domain: domain, key: "Enabled", isBoolean: true)
        let prefs = SystemGesturePreferences()
        defer {
            prefs.set(nil, for: number)
            prefs.set(nil, for: flag)
        }
        XCTAssertNil(prefs.value(for: number))
        prefs.set(2, for: number)
        prefs.set(false, for: flag)
        XCTAssertEqual(prefs.value(for: number) as? Int, 2)
        XCTAssertEqual(prefs.value(for: flag) as? Bool, false)
        XCTAssertEqual(CFGetTypeID(prefs.value(for: flag) as CFTypeRef), CFBooleanGetTypeID(), "a boolean stays a boolean")
        XCTAssertEqual(CFGetTypeID(prefs.value(for: number) as CFTypeRef), CFNumberGetTypeID())
        prefs.set(nil, for: number)
        XCTAssertNil(prefs.value(for: number))
    }

    func testAFullSuppressAndRestoreOnTheRealPreferencesLeavesNothingBehind() throws {
        let domain = "tech.erenium.dirtymac.tests.roundtrip-\(UUID().uuidString)"
        let number = GestureSetting(domain: domain, key: "Swipe", isBoolean: false)
        let flag = GestureSetting(domain: domain, key: "Enabled", isBoolean: true)
        let prefs = SystemGesturePreferences()
        defer { prefs.set(nil, for: number); prefs.set(nil, for: flag) }
        prefs.set(3, for: number)
        let suppressor = GestureSuppressor(
            preferences: prefs, dock: FakeDock(), defaults: try TestDefaults.make(self), settings: [number, flag]
        )
        suppressor.suppress()
        XCTAssertEqual(prefs.value(for: number) as? Int, 0)
        XCTAssertEqual(prefs.value(for: flag) as? Bool, false)
        suppressor.restore()
        XCTAssertEqual(prefs.value(for: number) as? Int, 3)
        XCTAssertNil(prefs.value(for: flag), "unset before, unset after")
    }

    // MARK: The setting

    func testItIsOnByDefaultInBothModesAndReadFromStorage() throws {
        XCTAssertTrue(LockConfiguration().suppressGestures)
        XCTAssertTrue(LockConfiguration().effective.suppressGestures)
        XCTAssertTrue(LockConfiguration(mode: .advanced).effective.suppressGestures)
        XCTAssertFalse(LockConfiguration(mode: .basic, suppressGestures: false).effective.suppressGestures)
        let defaults = try TestDefaults.make(self)
        XCTAssertTrue(LockConfiguration.load(from: defaults).suppressGestures)
        defaults.set(false, forKey: LockConfiguration.Key.suppressGestures)
        XCTAssertFalse(LockConfiguration.load(from: defaults).suppressGestures)
        XCTAssertEqual(LockConfiguration.Key.suppressGestures, "suppressGesturesWhileLocked")
    }

    // MARK: The lock uses it

    func testALockTurnsTheGesturesOffAndEveryEndTurnsThemOn() {
        for reason in [UnlockReason.clicked, .escHeld, .autoUnlock, .quit, .systemSleep, .screenLocked, .permissionRevoked] {
            let rig = BlockerRig()
            rig.blocker.start(LockConfiguration())
            XCTAssertTrue(rig.gestures.isSuppressed)
            rig.blocker.stop(reason: reason)
            XCTAssertFalse(rig.gestures.isSuppressed, "\(reason)")
        }
    }

    func testWithTheSettingOffTheGesturesAreLeftAlone() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(suppressGestures: false))
        XCTAssertTrue(rig.blocker.isActive)
        XCTAssertEqual(rig.gestures.suppressCalls, 0)
    }

    func testARefusedLockNeverTouchesTheGestures() {
        let rig = BlockerRig()
        rig.tap.refuses = true
        rig.blocker.start(LockConfiguration())
        XCTAssertEqual(rig.gestures.suppressCalls, 0)
        let noPermission = BlockerRig()
        noPermission.permission.trusted = false
        noPermission.blocker.start(LockConfiguration())
        XCTAssertEqual(noPermission.gestures.suppressCalls, 0)
    }

    func testTheAutoUnlockPutsTheGesturesBack() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, autoUnlockSeconds: 30))
        XCTAssertTrue(rig.gestures.isSuppressed)
        rig.clock.advance(by: 31)
        XCTAssertFalse(rig.gestures.isSuppressed)
    }

    func testAFrozenMouseTurnsThemOffToo() {
        let rig = BlockerRig()
        rig.blocker.start(LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true, autoUnlockSeconds: 60))
        XCTAssertTrue(rig.gestures.isSuppressed)
    }
}
