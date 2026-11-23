import XCTest
@testable import dirtymac

/// The pure rules of UpdateCheck: what a reply means, when a check is
/// due, when a reminder is owed. No network and no clock of its own.
final class UpdateCheckTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Response

    private func reply(tag: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["tag_name": tag])) ?? Data()
    }

    func testParsesTheTagWithoutItsLeadingV() {
        XCTAssertEqual(UpdateCheck.parseLatestVersion(from: reply(tag: "v1.4.0")), "1.4.0")
        XCTAssertEqual(UpdateCheck.parseLatestVersion(from: reply(tag: "1.4.0")), "1.4.0")
        XCTAssertEqual(UpdateCheck.parseLatestVersion(from: reply(tag: "v10.20.30")), "10.20.30")
        XCTAssertEqual(UpdateCheck.parseLatestVersion(from: reply(tag: "v2")), "2")
    }

    func testIgnoresTheRestOfTheReply() {
        let data = Data(#"{"id":1,"name":"x","tag_name":"v1.4.0","html_url":"https://evil.example","assets":[]}"#.utf8)
        XCTAssertEqual(UpdateCheck.parseLatestVersion(from: data), "1.4.0")
    }

    func testRefusesAnythingButAPlainVersion() {
        let bad = [
            "", "v", "vv1.0", "latest", "1.4.0-beta", "1.4.0-rc.1", "1.4.0+build",
            "1.4.0/../x", "../1.4.0", "v1..2", "v1.", "v.1", "1.2.3.4.5",
            "1.4.0\"", "v1.4.0 ", " v1.4.0", "1.4.0\n", "1.4.0\nx", "1,4,0", "١.٤.٠",
            "1.4.0?x=1", "1.4.0#a", "1.4.0%2e", "https://example.com/1.4.0",
        ]
        for tag in bad {
            XCTAssertNil(UpdateCheck.parseLatestVersion(from: reply(tag: tag)), "tag \(tag.debugDescription)")
        }
    }

    func testRefusesAReplyThatIsNotAReleaseObject() {
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: Data()))
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: Data("not json".utf8)))
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: Data("[]".utf8)))
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: Data("null".utf8)))
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: Data(#"{"name":"v1.4.0"}"#.utf8)))
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: Data(#"{"tag_name":null}"#.utf8)))
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: reply(tag: 140)))
        XCTAssertNil(UpdateCheck.parseLatestVersion(from: reply(tag: ["1.4.0"])))
    }

    func testPlainVersionShape() {
        for ok in ["1", "1.4", "1.4.0", "1.4.0.1", "0.0.0", "01.4"] {
            XCTAssertTrue(UpdateCheck.isPlainVersion(ok), ok)
        }
        for bad in ["", ".", "1.", "a", "1.a", "1.4.0-1", "1 .4", "1.4.0.1.2"] {
            XCTAssertFalse(UpdateCheck.isPlainVersion(bad), bad)
        }
    }

    func testNewerComparesNumbersNotText() {
        XCTAssertTrue(UpdateCheck.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(UpdateCheck.isNewer("1.3.3", than: "1.3.2"))
        XCTAssertTrue(UpdateCheck.isNewer("2", than: "1.99.99"))
        XCTAssertTrue(UpdateCheck.isNewer("1.4.0.1", than: "1.4.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.3.2", than: "1.3.2"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.3.1", than: "1.3.2"))
        XCTAssertFalse(UpdateCheck.isNewer("1.9.2", than: "1.10.0"))
    }

    // MARK: Addresses

    func testAddressesAreBuiltFromTheVersion() {
        XCTAssertEqual(
            UpdateCheck.notesURL(version: "1.4.0").absoluteString,
            "https://github.com/erenmalkoc/dirtymac/releases/tag/v1.4.0"
        )
        XCTAssertEqual(
            UpdateCheck.dmgURL(version: "1.4.0").absoluteString,
            "https://github.com/erenmalkoc/dirtymac/releases/download/v1.4.0/dirtymac-1.4.0.dmg"
        )
    }

    func testEveryAddressStaysOnGitHubAndOverHTTPS() {
        let urls = [
            UpdateCheck.latestReleaseAPI, UpdateCheck.releasesPage,
            UpdateCheck.notesURL(version: "1.4.0"), UpdateCheck.dmgURL(version: "1.4.0"),
        ]
        for url in urls {
            XCTAssertEqual(url.scheme, "https", url.absoluteString)
            XCTAssertTrue(["github.com", "api.github.com"].contains(url.host ?? ""), url.absoluteString)
            XCTAssertNil(url.query, url.absoluteString)
            XCTAssertNil(url.user, url.absoluteString)
        }
        XCTAssertEqual(UpdateCheck.latestReleaseAPI.absoluteString,
                       "https://api.github.com/repos/erenmalkoc/dirtymac/releases/latest")
    }

    /// The release workflow names the disk image dirtymac-<version>.dmg
    /// and the cask is bumped by hand. If the workflow changes, the
    /// Download button would silently break: keep the two in step.
    func testDownloadAddressMatchesTheReleaseWorkflow() throws {
        let workflow = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
        let text = try String(contentsOf: workflow, encoding: .utf8)
        XCTAssertTrue(text.contains("dirtymac-${{ steps.version.outputs.version }}.dmg"),
                      "release.yml no longer names the DMG dirtymac-<version>.dmg")
        XCTAssertTrue(UpdateCheck.dmgURL(version: "9.9.9").lastPathComponent == "dirtymac-9.9.9.dmg")
    }

    // MARK: Schedule

    func testNothingIsDueWhileChecksAreOff() {
        XCTAssertFalse(UpdateCheck.isCheckDue(enabled: false, lastCheck: nil, now: start))
        XCTAssertFalse(UpdateCheck.isCheckDue(enabled: false, lastCheck: start - 10 * day, now: start))
        XCTAssertFalse(UpdateCheck.isCheckDue(enabled: false, lastCheck: start + 10 * day, now: start))
    }

    func testACheckIsDueOncePerDay() {
        XCTAssertTrue(UpdateCheck.isCheckDue(enabled: true, lastCheck: nil, now: start))
        XCTAssertFalse(UpdateCheck.isCheckDue(enabled: true, lastCheck: start, now: start))
        XCTAssertFalse(UpdateCheck.isCheckDue(enabled: true, lastCheck: start - day + 1, now: start))
        XCTAssertTrue(UpdateCheck.isCheckDue(enabled: true, lastCheck: start - day, now: start))
        XCTAssertTrue(UpdateCheck.isCheckDue(enabled: true, lastCheck: start - 30 * day, now: start))
    }

    func testAClockSetBackDoesNotBlockChecks() {
        XCTAssertTrue(UpdateCheck.isCheckDue(enabled: true, lastCheck: start + 5 * day, now: start))
    }

    // MARK: Reminders

    private func reminder(daysAgo: Double, dismissed: Int = 0, enabled: Bool = false) -> UpdateCheck.Reminder? {
        UpdateCheck.reminder(
            enabled: enabled,
            installedSince: start - daysAgo * day,
            dismissedMilestone: dismissed,
            now: start
        )
    }

    func testNoReminderBeforeSixtyDays() {
        XCTAssertNil(reminder(daysAgo: 0))
        XCTAssertNil(reminder(daysAgo: 1))
        XCTAssertNil(reminder(daysAgo: 59.9))
        XCTAssertNil(reminder(daysAgo: 60 - 1 / day))   // one second short
    }

    func testRemindsAtSixtyThenEverySixtyDays() {
        XCTAssertEqual(reminder(daysAgo: 60), .init(milestone: 60, days: 60))
        XCTAssertEqual(reminder(daysAgo: 63), .init(milestone: 60, days: 63))
        XCTAssertEqual(reminder(daysAgo: 119.9), .init(milestone: 60, days: 119))
        XCTAssertEqual(reminder(daysAgo: 120), .init(milestone: 120, days: 120))
        XCTAssertEqual(reminder(daysAgo: 200), .init(milestone: 180, days: 200))
        XCTAssertEqual(reminder(daysAgo: 360), .init(milestone: 360, days: 360))
        XCTAssertEqual(reminder(daysAgo: 3650), .init(milestone: 3600, days: 3650))
    }

    func testLaterHidesTheReminderUntilTheNextStep() {
        XCTAssertNil(reminder(daysAgo: 60, dismissed: 60))
        XCTAssertNil(reminder(daysAgo: 70, dismissed: 60))
        XCTAssertNil(reminder(daysAgo: 119, dismissed: 60))
        XCTAssertEqual(reminder(daysAgo: 120, dismissed: 60), .init(milestone: 120, days: 120))
    }

    func testASkippedStepShowsTheNewestOnly() {
        // Never opened for 130 days: one reminder, not two.
        XCTAssertEqual(reminder(daysAgo: 130, dismissed: 0), .init(milestone: 120, days: 130))
    }

    func testADismissalAheadOfTheClockStaysDismissed() {
        // The clock went back after a "Later" at step 180.
        XCTAssertNil(reminder(daysAgo: 70, dismissed: 180))
    }

    func testChecksBeingOnReplaceReminders() {
        XCTAssertNil(reminder(daysAgo: 60, enabled: true))
        XCTAssertNil(reminder(daysAgo: 400, enabled: true))
    }

    func testUnknownOrFutureInstallDateGivesNoReminder() {
        XCTAssertNil(UpdateCheck.reminder(enabled: false, installedSince: nil, dismissedMilestone: 0, now: start))
        XCTAssertNil(UpdateCheck.reminder(enabled: false, installedSince: start + day, dismissedMilestone: 0, now: start))
    }

    // MARK: Install date

    func testTheFirstLaunchStartsTheClock() throws {
        let defaults = try TestDefaults.make(self)
        UpdateCheck.recordInstalledVersion("1.4.0", now: start, in: defaults)
        XCTAssertEqual(defaults.string(forKey: UpdateCheck.Key.installedVersion), "1.4.0")
        XCTAssertEqual(defaults.object(forKey: UpdateCheck.Key.installedSince) as? Date, start)
        XCTAssertEqual(defaults.integer(forKey: UpdateCheck.Key.dismissedMilestone), 0)
    }

    func testANewVersionRestartsTheClock() throws {
        let defaults = try TestDefaults.make(self)
        UpdateCheck.recordInstalledVersion("1.4.0", now: start, in: defaults)
        defaults.set(60, forKey: UpdateCheck.Key.dismissedMilestone)

        // The same version again changes nothing.
        UpdateCheck.recordInstalledVersion("1.4.0", now: start + 30 * day, in: defaults)
        XCTAssertEqual(defaults.object(forKey: UpdateCheck.Key.installedSince) as? Date, start)
        XCTAssertEqual(defaults.integer(forKey: UpdateCheck.Key.dismissedMilestone), 60)

        UpdateCheck.recordInstalledVersion("1.4.1", now: start + 90 * day, in: defaults)
        XCTAssertEqual(defaults.object(forKey: UpdateCheck.Key.installedSince) as? Date, start + 90 * day)
        XCTAssertEqual(defaults.integer(forKey: UpdateCheck.Key.dismissedMilestone), 0)
    }

    func testADowngradeAlsoRestartsTheClock() throws {
        let defaults = try TestDefaults.make(self)
        UpdateCheck.recordInstalledVersion("1.5.0", now: start, in: defaults)
        UpdateCheck.recordInstalledVersion("1.4.0", now: start + 10 * day, in: defaults)
        XCTAssertEqual(defaults.object(forKey: UpdateCheck.Key.installedSince) as? Date, start + 10 * day)
    }

    // MARK: Install kind

    func testHomebrewInstallIsRecognisedInEitherPrefix() {
        XCTAssertTrue(UpdateCheck.isHomebrewInstall { $0 == "/opt/homebrew/Caskroom/dirtymac" })
        XCTAssertTrue(UpdateCheck.isHomebrewInstall { $0 == "/usr/local/Caskroom/dirtymac" })
        XCTAssertFalse(UpdateCheck.isHomebrewInstall { _ in false })
        XCTAssertFalse(UpdateCheck.isHomebrewInstall { $0 == "/opt/homebrew/Caskroom/other" })
    }

    func testHomebrewDetectionRunsAgainstTheRealDiskToo() {
        // Either answer is right on a given Mac. It must not crash or hang.
        _ = UpdateCheck.isHomebrewInstall()
    }

    func testTheBrewCommandNamesTheTapSoItBypassesTheDailyCache() {
        // README troubleshooting: the short name can lag a release by a day.
        XCTAssertEqual(UpdateCheck.brewCommand, "brew upgrade --cask erenmalkoc/tap/dirtymac")
    }
}
