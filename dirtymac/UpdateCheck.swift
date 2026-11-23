import Foundation

/// Update awareness for an app that promises to stay offline.
///
/// Nothing here touches the network unless the user turned update checks
/// on: the only request dirtymac can make is one GET for the latest
/// release number, once a day at most. Everyone else gets a reminder
/// every 60 days that a newer version may exist, which needs no network
/// at all. The decisions live in pure functions so they are tested
/// without a connection.
nonisolated enum UpdateCheck {
    enum Key {
        static let enabled = "updateChecksEnabled"
        static let offered = "updateChecksOffered"
        static let lastCheck = "updateLastCheck"
        static let latestVersion = "updateLatestVersion"
        static let installedVersion = "updateInstalledVersion"
        static let installedSince = "updateInstalledSince"
        static let dismissedMilestone = "updateDismissedMilestone"
    }

    static let repository = "erenmalkoc/dirtymac"
    static let brewCommand = "brew upgrade --cask erenmalkoc/tap/dirtymac"

    /// A day between checks, and a reminder every `reminderInterval` days
    /// for people who left the checks off.
    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let reminderInterval = 60

    // MARK: Addresses

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    /// Addresses are built from the version number instead of taken from
    /// the response, so a reply can never point the app elsewhere.
    static func notesURL(version: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/tag/v\(version)")!
    }

    static func dmgURL(version: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/download/v\(version)/dirtymac-\(version).dmg")!
    }

    // MARK: Response

    /// The version number of a GitHub "latest release" reply: its
    /// `tag_name` without the leading "v". Anything that is not a plain
    /// dotted number is refused, which also rules out a version that
    /// could alter the addresses built from it.
    static func parseLatestVersion(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isPlainVersion(version) ? version : nil
    }

    static func isPlainVersion(_ text: String) -> Bool {
        // \z, not $: ICU's $ also matches before a trailing newline.
        text.range(of: #"\A[0-9]+(\.[0-9]+){0,3}\z"#, options: .regularExpression) != nil
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        WhatsNew.compare(latest, current) == .orderedDescending
    }

    // MARK: Schedule

    /// A check is due when the user allowed it and none ran in the last
    /// day. A clock set back counts as due rather than waiting out a
    /// timestamp that lies in the future.
    static func isCheckDue(enabled: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    struct Reminder: Equatable {
        /// The 60-day step this reminder belongs to (60, 120, 180…).
        let milestone: Int
        /// Days since this version first ran, for the text.
        let days: Int
    }

    /// The reminder to show now, if any: the newest 60-day step passed
    /// since this version was installed that the user has not dismissed.
    /// Checks being on replaces reminders, so they are never due then.
    static func reminder(
        enabled: Bool,
        installedSince: Date?,
        dismissedMilestone: Int,
        now: Date
    ) -> Reminder? {
        guard !enabled, let installedSince, installedSince <= now else { return nil }
        let days = Int(now.timeIntervalSince(installedSince) / 86_400)
        let milestone = days / reminderInterval * reminderInterval
        guard milestone >= reminderInterval, milestone > dismissedMilestone else { return nil }
        return Reminder(milestone: milestone, days: days)
    }

    /// Starts the clock over when a different version runs than last time:
    /// the reminder counts from the day this version was installed, and an
    /// earlier "later" no longer applies.
    static func recordInstalledVersion(_ current: String, now: Date, in defaults: UserDefaults) {
        guard defaults.string(forKey: Key.installedVersion) != current else { return }
        defaults.set(current, forKey: Key.installedVersion)
        defaults.set(now, forKey: Key.installedSince)
        defaults.set(0, forKey: Key.dismissedMilestone)
    }

    // MARK: Install kind

    /// Homebrew keeps a Caskroom entry for every cask it installed, in
    /// either prefix. The app itself is copied to /Applications, so its
    /// own path says nothing.
    static func isHomebrewInstall(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        ["/opt/homebrew/Caskroom/dirtymac", "/usr/local/Caskroom/dirtymac"].contains(where: fileExists)
    }

    // MARK: Request

    enum CheckError: Error { case badStatus, badBody }

    /// One GET for the latest release number. The session is ephemeral
    /// (no cookies or cache kept) and the request names only the app.
    static func fetchLatestVersion(session: URLSession = makeSession()) async throws -> String {
        var request = URLRequest(url: latestReleaseAPI, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("dirtymac-update-check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CheckError.badStatus }
        guard let version = parseLatestVersion(from: data) else { throw CheckError.badBody }
        return version
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
