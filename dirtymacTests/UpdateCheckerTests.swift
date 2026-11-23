import XCTest
@testable import dirtymac

/// The model with a fake request: what it stores, what it shows, and
/// above all when it stays silent.
@MainActor
final class UpdateCheckerTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Offline: Error {}

    /// A fake request that can be answered by hand, in any order, so a
    /// test decides exactly when each reply arrives.
    private final class FakeServer {
        var requests = 0
        var replies: [Result<String, Error>] = []
        private var waiting: [CheckedContinuation<String, Error>] = []
        var hasOpenRequests: Bool { !waiting.isEmpty }

        /// Answers at once from `replies` (the last one repeats).
        func fetchNow() async throws -> String {
            requests += 1
            let reply = replies.count > 1 ? replies.removeFirst() : (replies.first ?? .success("0"))
            return try reply.get()
        }

        /// Holds the request until `answer` is called.
        func fetchHeld() async throws -> String {
            requests += 1
            return try await withCheckedThrowingContinuation { waiting.append($0) }
        }

        func answer(_ reply: Result<String, Error>, request index: Int = 0) {
            waiting.remove(at: index).resume(with: reply)
        }
    }

    private var clock: Date!

    override func setUp() async throws {
        clock = start
    }

    private func make(
        _ server: FakeServer,
        defaults: UserDefaults,
        current: String = "1.4.0",
        held: Bool = false
    ) -> UpdateChecker {
        UpdateChecker(
            defaults: defaults,
            currentVersion: current,
            now: { [unowned self] in clock },
            fetch: held ? { try await server.fetchHeld() } : { try await server.fetchNow() }
        )
    }

    private func enabled(_ defaults: UserDefaults) {
        defaults.set(true, forKey: UpdateCheck.Key.enabled)
    }

    // MARK: Off means silent

    func testChecksOffMeansNoRequestWhateverIsCalled() async throws {
        let server = FakeServer()
        let defaults = try TestDefaults.make(self)
        let checker = make(server, defaults: defaults)

        checker.start()
        checker.tick()
        checker.refreshReminder()
        await checker.check()
        XCTAssertNil(checker.startCheck())
        clock = start + 400 * day
        checker.tick()
        checker.dismissReminder()
        checker.setEnabled(false)

        XCTAssertEqual(server.requests, 0)
        XCTAssertEqual(checker.status, .idle)
        XCTAssertNil(checker.pendingCheck)
        XCTAssertNil(defaults.object(forKey: UpdateCheck.Key.lastCheck))
    }

    func testAStoredVersionIsNotOfferedWhileChecksAreOff() throws {
        let defaults = try TestDefaults.make(self)
        defaults.set("9.9.9", forKey: UpdateCheck.Key.latestVersion)
        XCTAssertNil(make(FakeServer(), defaults: defaults).availableVersion)
        enabled(defaults)
        XCTAssertEqual(make(FakeServer(), defaults: defaults).availableVersion, "9.9.9")
    }

    // MARK: Turning on

    func testTurningOnChecksAtOnceAndStoresTheAnswer() async throws {
        let server = FakeServer()
        server.replies = [.success("1.5.0")]
        let defaults = try TestDefaults.make(self)
        let checker = make(server, defaults: defaults)

        checker.setEnabled(true)
        XCTAssertEqual(checker.status, .checking)
        await checker.pendingCheck?.value

        XCTAssertEqual(server.requests, 1)
        XCTAssertEqual(checker.availableVersion, "1.5.0")
        XCTAssertEqual(checker.notice, .available("1.5.0"))
        XCTAssertEqual(checker.status, .idle)
        XCTAssertNil(checker.pendingCheck)
        XCTAssertTrue(checker.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: UpdateCheck.Key.offered))
        XCTAssertEqual(defaults.object(forKey: UpdateCheck.Key.lastCheck) as? Date, start)
        XCTAssertEqual(defaults.string(forKey: UpdateCheck.Key.latestVersion), "1.5.0")
    }

    func testUpToDateHasNothingToOffer() async throws {
        let server = FakeServer()
        server.replies = [.success("1.4.0")]
        let defaults = try TestDefaults.make(self)
        let checker = make(server, defaults: defaults)

        checker.setEnabled(true)
        await checker.pendingCheck?.value

        XCTAssertNil(checker.availableVersion)
        XCTAssertNil(checker.notice)
        XCTAssertEqual(checker.status, .upToDate)
        XCTAssertEqual(defaults.object(forKey: UpdateCheck.Key.lastCheck) as? Date, start)
    }

    func testAnOlderReleaseThanTheRunningOneIsNotAnUpdate() async throws {
        let server = FakeServer()
        server.replies = [.success("1.3.0")]
        let checker = make(server, defaults: try TestDefaults.make(self), current: "1.4.0")
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        XCTAssertNil(checker.availableVersion)
        XCTAssertEqual(checker.status, .upToDate)
    }

    func testTheCheckNowButtonAsksAgainRegardlessOfTheDailyLimit() async throws {
        let server = FakeServer()
        server.replies = [.success("1.4.0"), .success("1.5.0")]
        let checker = make(server, defaults: try TestDefaults.make(self))
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        XCTAssertEqual(checker.status, .upToDate)

        await checker.check()   // a minute later, by hand
        XCTAssertEqual(server.requests, 2)
        XCTAssertEqual(checker.availableVersion, "1.5.0")
    }

    // MARK: Failure

    func testAFailureIsShownAndNotRecordedAsACheck() async throws {
        let server = FakeServer()
        server.replies = [.failure(Offline())]
        let defaults = try TestDefaults.make(self)
        let checker = make(server, defaults: defaults)

        checker.setEnabled(true)
        await checker.pendingCheck?.value

        XCTAssertEqual(checker.status, .failed)
        XCTAssertNil(checker.availableVersion)
        XCTAssertNil(checker.pendingCheck)
        XCTAssertNil(defaults.object(forKey: UpdateCheck.Key.lastCheck))
    }

    func testAFailureDoesNotEraseWhatWasFoundBefore() async throws {
        let server = FakeServer()
        server.replies = [.success("1.5.0"), .failure(Offline())]
        let checker = make(server, defaults: try TestDefaults.make(self))
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        await checker.check()
        XCTAssertEqual(checker.status, .failed)
        XCTAssertEqual(checker.availableVersion, "1.5.0")
    }

    func testTheNextLookInRetriesAfterAFailureAndThenStopsAsking() async throws {
        let server = FakeServer()
        server.replies = [.failure(Offline()), .success("1.4.0")]
        let defaults = try TestDefaults.make(self)
        enabled(defaults)
        let checker = make(server, defaults: defaults)

        checker.tick()
        await checker.pendingCheck?.value
        XCTAssertEqual(checker.status, .failed)

        clock = start + 3600
        checker.tick()
        await checker.pendingCheck?.value
        XCTAssertEqual(checker.status, .upToDate)
        XCTAssertEqual(server.requests, 2)

        clock = start + 2 * 3600
        checker.tick()
        XCTAssertNil(checker.pendingCheck)
        XCTAssertEqual(server.requests, 2)
    }

    // MARK: The daily limit

    func testAtMostOneRequestADayFromTheHourlyLookIn() async throws {
        let server = FakeServer()
        server.replies = [.success("1.4.0")]
        let defaults = try TestDefaults.make(self)
        enabled(defaults)
        let checker = make(server, defaults: defaults)

        checker.tick()
        await checker.pendingCheck?.value
        XCTAssertEqual(server.requests, 1)

        for hour in 1..<24 {
            clock = start + Double(hour) * 3600
            checker.tick()
            XCTAssertNil(checker.pendingCheck, "hour \(hour)")
        }
        XCTAssertEqual(server.requests, 1)

        clock = start + day
        checker.tick()
        await checker.pendingCheck?.value
        XCTAssertEqual(server.requests, 2)
    }

    func testLaunchChecksWhenOneIsDueAndNotWhenItIsNot() async throws {
        let server = FakeServer()
        server.replies = [.success("1.4.0")]
        let defaults = try TestDefaults.make(self)
        enabled(defaults)
        defaults.set(start - 3600, forKey: UpdateCheck.Key.lastCheck)
        let recent = make(server, defaults: defaults)
        recent.start()
        XCTAssertNil(recent.pendingCheck)
        XCTAssertEqual(server.requests, 0)

        defaults.set(start - 2 * day, forKey: UpdateCheck.Key.lastCheck)
        let overdue = make(server, defaults: defaults)
        overdue.start()
        await overdue.pendingCheck?.value
        XCTAssertEqual(server.requests, 1)
    }

    // MARK: Overlap and races

    func testTwoCheckersAtOnceMakeOneRequest() async throws {
        let server = FakeServer()
        let checker = make(server, defaults: try TestDefaults.make(self), held: true)
        checker.setEnabled(true)
        let first = checker.startCheck()
        let second = checker.startCheck()
        let third = Task { await checker.check() }
        await Task.yield()

        XCTAssertEqual(server.requests, 1)
        server.answer(.success("1.5.0"))
        await first?.value
        await second?.value
        await third.value
        XCTAssertEqual(checker.availableVersion, "1.5.0")
        XCTAssertEqual(server.requests, 1)
    }

    func testAnAnswerThatArrivesAfterTurningOffIsDropped() async throws {
        let server = FakeServer()
        let defaults = try TestDefaults.make(self)
        let checker = make(server, defaults: defaults, held: true)
        checker.setEnabled(true)
        await Task.yield()
        XCTAssertTrue(server.hasOpenRequests)

        checker.setEnabled(false)
        server.answer(.success("9.9.9"))
        await Task.yield()
        await Task.yield()

        XCTAssertNil(checker.availableVersion)
        XCTAssertEqual(checker.status, .idle)
        XCTAssertNil(defaults.string(forKey: UpdateCheck.Key.latestVersion))
        XCTAssertNil(defaults.object(forKey: UpdateCheck.Key.lastCheck))
    }

    func testAFailureThatArrivesAfterTurningOffIsDropped() async throws {
        let server = FakeServer()
        let checker = make(server, defaults: try TestDefaults.make(self), held: true)
        checker.setEnabled(true)
        await Task.yield()
        checker.setEnabled(false)
        server.answer(.failure(Offline()))
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(checker.status, .idle)
    }

    func testOffThenOnQuicklyIgnoresTheOldAnswerAndKeepsTheNewOne() async throws {
        let server = FakeServer()
        let checker = make(server, defaults: try TestDefaults.make(self), held: true)

        checker.setEnabled(true)
        await Task.yield()
        checker.setEnabled(false)
        checker.setEnabled(true)
        await Task.yield()
        XCTAssertEqual(server.requests, 2)

        server.answer(.success("1.5.0"), request: 0)   // the old one, stale
        await Task.yield()
        await Task.yield()
        XCTAssertNil(checker.availableVersion)
        XCTAssertEqual(checker.status, .checking)
        XCTAssertNotNil(checker.pendingCheck, "the old answer must not clear the new check")

        server.answer(.success("1.6.0"), request: 0)   // the new one
        await checker.pendingCheck?.value
        XCTAssertEqual(checker.availableVersion, "1.6.0")
        XCTAssertEqual(checker.status, .idle)
        XCTAssertNil(checker.pendingCheck)
    }

    // MARK: Turning off

    func testTurningOffClearsWhatWasFoundAndWhatWasStored() async throws {
        let server = FakeServer()
        server.replies = [.success("1.5.0")]
        let defaults = try TestDefaults.make(self)
        let checker = make(server, defaults: defaults)
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        XCTAssertEqual(checker.availableVersion, "1.5.0")

        checker.setEnabled(false)
        XCTAssertNil(checker.availableVersion)
        XCTAssertEqual(checker.status, .idle)
        XCTAssertFalse(checker.isEnabled)
        XCTAssertNil(defaults.string(forKey: UpdateCheck.Key.latestVersion))
        XCTAssertNil(defaults.object(forKey: UpdateCheck.Key.lastCheck))
        // …and a relaunch does not bring it back.
        XCTAssertNil(make(FakeServer(), defaults: defaults).availableVersion)
    }

    func testTurningOnAgainChecksRightAwayEvenWithinADay() async throws {
        let server = FakeServer()
        server.replies = [.success("1.4.0")]
        let checker = make(server, defaults: try TestDefaults.make(self))
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        checker.setEnabled(false)
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        XCTAssertEqual(server.requests, 2)
    }

    // MARK: Found versions

    func testAFoundVersionSurvivesARelaunchUntilInstalled() throws {
        let defaults = try TestDefaults.make(self)
        enabled(defaults)
        defaults.set("1.5.0", forKey: UpdateCheck.Key.latestVersion)
        XCTAssertEqual(make(FakeServer(), defaults: defaults, current: "1.4.0").availableVersion, "1.5.0")
        XCTAssertNil(make(FakeServer(), defaults: defaults, current: "1.5.0").availableVersion)
        XCTAssertNil(make(FakeServer(), defaults: defaults, current: "1.6.0").availableVersion)
    }

    func testAStoredValueThatIsNotAVersionIsIgnored() throws {
        let defaults = try TestDefaults.make(self)
        enabled(defaults)
        for junk in ["../evil", "", "1.5.0\n", "v1.5.0", "1.5.0-beta"] {
            defaults.set(junk, forKey: UpdateCheck.Key.latestVersion)
            XCTAssertNil(make(FakeServer(), defaults: defaults).availableVersion, junk.debugDescription)
        }
    }

    // MARK: Reminders

    func testReminderAppearsAtSixtyDaysAndLaterHidesIt() throws {
        let checker = make(FakeServer(), defaults: try TestDefaults.make(self))
        checker.start()
        XCTAssertNil(checker.reminder)
        XCTAssertNil(checker.notice)

        clock = start + 59 * day
        checker.refreshReminder()
        XCTAssertNil(checker.reminder)

        clock = start + 61 * day
        checker.refreshReminder()
        XCTAssertEqual(checker.reminder, .init(milestone: 60, days: 61))
        XCTAssertEqual(checker.notice, .reminder(days: 61))

        checker.dismissReminder()
        XCTAssertNil(checker.reminder)
        checker.refreshReminder()
        XCTAssertNil(checker.reminder)

        clock = start + 121 * day
        checker.refreshReminder()
        XCTAssertEqual(checker.reminder, .init(milestone: 120, days: 121))
    }

    func testTheHourlyLookInRaisesTheReminderToo() throws {
        let checker = make(FakeServer(), defaults: try TestDefaults.make(self))
        checker.start()
        clock = start + 61 * day
        checker.tick()
        XCTAssertEqual(checker.reminder?.milestone, 60)
    }

    func testLaterIsRememberedAcrossRelaunches() throws {
        let defaults = try TestDefaults.make(self)
        let first = make(FakeServer(), defaults: defaults)
        first.start()
        clock = start + 70 * day
        first.refreshReminder()
        first.dismissReminder()

        let relaunched = make(FakeServer(), defaults: defaults)
        relaunched.start()
        XCTAssertNil(relaunched.reminder)

        clock = start + 125 * day
        relaunched.refreshReminder()
        XCTAssertEqual(relaunched.reminder?.milestone, 120)
    }

    func testAnUpdateRestartsTheCountAndDropsAnyReminder() throws {
        let defaults = try TestDefaults.make(self)
        let old = make(FakeServer(), defaults: defaults, current: "1.4.0")
        old.start()
        clock = start + 100 * day
        old.refreshReminder()
        XCTAssertNotNil(old.reminder)

        let updated = make(FakeServer(), defaults: defaults, current: "1.4.1")
        updated.start()
        XCTAssertNil(updated.reminder)
        clock = start + 100 * day + 59 * day
        updated.refreshReminder()
        XCTAssertNil(updated.reminder)
        clock = start + 100 * day + 61 * day
        updated.refreshReminder()
        XCTAssertEqual(updated.reminder?.milestone, 60)
    }

    func testTurningChecksOnEndsReminders() throws {
        let checker = make(FakeServer(), defaults: try TestDefaults.make(self))
        checker.start()
        clock = start + 70 * day
        checker.refreshReminder()
        XCTAssertNotNil(checker.reminder)
        checker.setEnabled(true)
        XCTAssertNil(checker.reminder)
    }

    func testTurningChecksOffBringsTheDueReminderBack() throws {
        let server = FakeServer()
        server.replies = [.success("1.4.0")]
        let checker = make(server, defaults: try TestDefaults.make(self))
        checker.start()
        clock = start + 70 * day
        checker.setEnabled(true)
        XCTAssertNil(checker.reminder)
        checker.setEnabled(false)
        XCTAssertEqual(checker.reminder?.milestone, 60)
    }

    func testDismissingWithNothingShownChangesNothing() throws {
        let defaults = try TestDefaults.make(self)
        let checker = make(FakeServer(), defaults: defaults)
        checker.start()
        checker.dismissReminder()
        XCTAssertEqual(defaults.integer(forKey: UpdateCheck.Key.dismissedMilestone), 0)
    }

    // MARK: What the panel announces

    func testAFoundVersionOutranksAReminder() throws {
        let defaults = try TestDefaults.make(self)
        enabled(defaults)
        defaults.set("1.5.0", forKey: UpdateCheck.Key.latestVersion)
        UpdateCheck.recordInstalledVersion("1.4.0", now: start - 100 * day, in: defaults)
        let checker = make(FakeServer(), defaults: defaults)
        // Reminders are off while checks are on, but the order is part of the contract.
        XCTAssertEqual(checker.notice, .available("1.5.0"))
        XCTAssertNil(checker.reminder)
    }
}
