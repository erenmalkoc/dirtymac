import Foundation
import Combine

/// What the panel, the menu bar icon and Settings show about updates.
/// Owned by the AppDelegate; see UpdateCheck for the rules.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle, checking, upToDate, failed
    }

    /// What the panel announces. A found version outranks a reminder,
    /// though both never show at once: reminders exist only while the
    /// checks are off.
    enum Notice: Equatable {
        case available(String)
        case reminder(days: Int)
    }

    /// A newer version found by a check, nil when running the newest.
    @Published private(set) var availableVersion: String?
    @Published private(set) var reminder: UpdateCheck.Reminder?
    @Published private(set) var status: Status = .idle

    private let defaults: UserDefaults
    private let currentVersion: String
    private let now: () -> Date
    private let fetch: () async throws -> String
    private var timer: Timer?
    /// The check running now, so callers (and tests) can wait for it.
    private(set) var pendingCheck: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil,
        now: @escaping () -> Date = Date.init,
        fetch: (() async throws -> String)? = nil
    ) {
        let current = currentVersion ?? WhatsNew.currentVersion
        self.defaults = defaults
        self.currentVersion = current
        self.now = now
        self.fetch = fetch ?? { try await UpdateCheck.fetchLatestVersion() }
        availableVersion = Self.storedAvailable(defaults: defaults, current: current)
    }

    /// A version found earlier stays on offer until it is installed.
    private static func storedAvailable(defaults: UserDefaults, current: String) -> String? {
        guard defaults.bool(forKey: UpdateCheck.Key.enabled),
              let stored = defaults.string(forKey: UpdateCheck.Key.latestVersion),
              UpdateCheck.isPlainVersion(stored),
              UpdateCheck.isNewer(stored, than: current)
        else { return nil }
        return stored
    }

    var isEnabled: Bool { defaults.bool(forKey: UpdateCheck.Key.enabled) }

    var notice: Notice? {
        if let availableVersion { return .available(availableVersion) }
        if let reminder { return .reminder(days: reminder.days) }
        return nil
    }

    // MARK: Lifecycle

    /// Called once at launch. With checks off this only does arithmetic
    /// on dates, so an offline app stays offline.
    func start() {
        UpdateCheck.recordInstalledVersion(currentVersion, now: now(), in: defaults)
        tick()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        // Run in every mode so the hourly look-in survives an open menu.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-evaluates the reminder and starts a check when one is due.
    func tick() {
        refreshReminder()
        let lastCheck = defaults.object(forKey: UpdateCheck.Key.lastCheck) as? Date
        if UpdateCheck.isCheckDue(enabled: isEnabled, lastCheck: lastCheck, now: now()) {
            startCheck()
        }
    }

    func refreshReminder() {
        let next = UpdateCheck.reminder(
            enabled: isEnabled,
            installedSince: defaults.object(forKey: UpdateCheck.Key.installedSince) as? Date,
            dismissedMilestone: defaults.integer(forKey: UpdateCheck.Key.dismissedMilestone),
            now: now()
        )
        if next != reminder { reminder = next }
    }

    // MARK: Actions

    func setEnabled(_ on: Bool) {
        // Answering the question, either way, ends the one-time offer.
        UpdateCheck.markOffered(in: defaults)
        // Setting what is already set must not start another request.
        guard on != isEnabled else { return }
        defaults.set(on, forKey: UpdateCheck.Key.enabled)
        refreshReminder()
        if on {
            startCheck()
        } else {
            // Whatever was found while on would otherwise stay on screen
            // as a result that is no longer renewed.
            generation += 1
            pendingCheck?.cancel()
            pendingCheck = nil
            defaults.removeObject(forKey: UpdateCheck.Key.latestVersion)
            defaults.removeObject(forKey: UpdateCheck.Key.lastCheck)
            availableVersion = nil
            status = .idle
        }
    }

    /// "Later": hides this reminder until the next 60-day step.
    func dismissReminder() {
        guard let reminder else { return }
        defaults.set(reminder.milestone, forKey: UpdateCheck.Key.dismissedMilestone)
        self.reminder = nil
    }

    /// Starts a check unless one is already running.
    @discardableResult
    func startCheck() -> Task<Void, Never>? {
        guard isEnabled, status != .checking else { return pendingCheck }
        status = .checking
        generation += 1
        let mine = generation
        let task = Task { await self.performCheck(generation: mine) }
        pendingCheck = task
        return task
    }

    /// One request, whatever the schedule says. Only ever reached with
    /// the user's consent: the Settings toggle or its button.
    func check() async {
        await startCheck()?.value
    }

    /// Bumped by every check and by turning the checks off, so an answer
    /// that arrives after either is recognised as stale and dropped.
    private var generation = 0

    private func performCheck(generation mine: Int) async {
        let result: Result<String, Error>
        do { result = .success(try await fetch()) } catch { result = .failure(error) }
        guard mine == generation else { return }
        pendingCheck = nil
        switch result {
        case .success(let latest):
            defaults.set(now(), forKey: UpdateCheck.Key.lastCheck)
            defaults.set(latest, forKey: UpdateCheck.Key.latestVersion)
            availableVersion = UpdateCheck.isNewer(latest, than: currentVersion) ? latest : nil
            status = availableVersion == nil ? .upToDate : .idle
        case .failure:
            // A failed attempt is not recorded as a check, so the next
            // hourly look-in tries again.
            status = .failed
        }
    }
}
