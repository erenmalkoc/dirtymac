import SwiftUI
import AppKit

// MARK: - Preferences

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    /// SwiftUI `\.colorScheme` environment override — affects Text and
    /// other SwiftUI primitives that read the environment.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// AppKit-level appearance — required to make `NSPopover`'s
    /// vibrancy backdrop and `Material` views switch modes. Without
    /// this, only text color responds to `colorScheme`.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The saved preference (defaults to `.system`).
    static var current: AppearancePreference {
        AppearancePreference(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "")
            ?? .system
    }

    /// Apply this preference app-wide: pushes the matching NSAppearance
    /// to NSApp, which propagates to the menu bar popover and any
    /// AppKit-hosted windows (e.g. onboarding).
    static func applyCurrent() {
        NSApp?.appearance = current.nsAppearance
    }
}

enum LanguagePreference: String, CaseIterable, Identifiable {
    case system = ""
    case de, en, es, fr, it, tr, ru, ko, ja
    case ptBR = "pt-BR"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: Self { self }

    /// Endonym (native) name. Users always recognise their own language
    /// regardless of the current UI language, so we deliberately do NOT
    /// localise these. The "System" option is the exception — it's a
    /// semantic label that should match the current UI language.
    var nativeName: String {
        switch self {
        case .system: "" // unused — see `label`
        case .de:     "Deutsch"
        case .en:     "English"
        case .es:     "Español"
        case .fr:     "Français"
        case .it:     "Italiano"
        case .ptBR:   "Português (Brasil)"
        case .tr:     "Türkçe"
        case .ru:     "Русский"
        case .ko:     "한국어"
        case .ja:     "日本語"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        }
    }

    var locale: Locale? {
        rawValue.isEmpty ? nil : Locale(identifier: rawValue)
    }

    /// The language's .lproj bundle, for AppKit strings (menus, tooltips,
    /// window titles) that SwiftUI's \.locale override does not reach.
    /// System, or a missing .lproj, falls back to the system language.
    var bundle: Bundle {
        guard self != .system,
              let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    /// The saved preference (defaults to `.system`).
    static var current: LanguagePreference {
        LanguagePreference(rawValue: UserDefaults.standard.string(forKey: "language") ?? "")
            ?? .system
    }

    @ViewBuilder
    var label: some View {
        if self == .system {
            Text("System")
        } else {
            Text(verbatim: nativeName)
        }
    }
}

// MARK: - Lock Configuration

enum LockMode: String, CaseIterable, Identifiable {
    case basic, advanced
    var id: Self { self }
    var label: LocalizedStringKey { self == .basic ? "Basic" : "Advanced" }
}

/// What the keyboard blocker should suppress, plus the auto-unlock
/// timer. `current` reads UserDefaults; `effective` applies the safety
/// rules (Basic is a fixed safe preset; full mouse lockdown forces a
/// minimum auto-unlock so the user is never permanently trapped).
struct LockConfiguration: Equatable {
    /// UserDefaults keys, shared by the Settings toggles and the lock.
    enum Key {
        static let mode = "lockMode"
        static let blockModifierKeys = "blockModifierKeys"
        static let blockMediaKeys = "blockMediaKeys"
        static let blockMouseAndTrackpad = "blockMouseAndTrackpad"
        static let autoUnlockSeconds = "autoUnlockSeconds"
        static let keepDisplayAwake = "keepDisplayAwakeWhileLocked"
        static let startDelaySeconds = "lockStartDelaySeconds"
    }

    var mode: LockMode = .basic
    var blockModifierKeys = true
    var blockMediaKeys = true
    var blockMouseAndTrackpad = false
    var autoUnlockSeconds = 0          // 0 = off
    /// Keep the screen from dimming or sleeping while locked. Not part of
    /// the Basic safety preset: it applies to every lock.
    var keepDisplayAwake = true
    /// Seconds to wait between the click on Lock and the lock, to take
    /// the hands off the keyboard. 0 = lock at once. Like keepDisplayAwake
    /// it is no part of the Basic safety preset.
    var startDelaySeconds = 0

    /// What the Settings picker offers.
    static let startDelayChoices = [0, 3, 5, 10]

    /// Only a value the picker offers counts; anything else (a stale or
    /// hand-edited preference) means no delay.
    static func sanitizedStartDelay(_ seconds: Int) -> Int {
        startDelayChoices.contains(seconds) ? seconds : 0
    }

    /// Auto-unlock is mandatory (and at least this long) once the mouse
    /// is part of the lockdown — the menu bar can no longer be clicked.
    static let minMouseLockSeconds = 30

    /// ...and at most this long. With the mouse frozen the only ways out
    /// are hold-Esc and the timer, so the time someone could be stuck
    /// behind a key that does not work is bounded. With the mouse free,
    /// clicking the menu bar icon always ends the lock, so no bound.
    static let maxMouseLockSeconds = 15 * 60

    /// A frozen-mouse lock longer than this first asks the user to hold
    /// Esc, to prove that the way out works on this keyboard.
    static let escCheckAboveSeconds = 5 * 60

    /// Selectable auto-unlock durations, in seconds. 0 = off.
    static let unlockChoices = [0, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// The auto-unlock the lock really uses for a stored value: once the
    /// mouse is part of the lockdown the menu bar can no longer be
    /// clicked, so it is never off, never shorter than the minimum and
    /// never longer than the maximum.
    static func clampedSeconds(_ seconds: Int, mouseLocked: Bool) -> Int {
        mouseLocked ? min(max(seconds, minMouseLockSeconds), maxMouseLockSeconds) : seconds
    }

    /// Whether starting this lock needs the Esc check first. `self` should
    /// be an `effective` configuration, so the clamps are already applied.
    var requiresEscCheck: Bool {
        blockMouseAndTrackpad && autoUnlockSeconds > Self.escCheckAboveSeconds
    }

    /// A picker label such as "30 sec" or "2 min", in `locale`.
    static func unlockChoiceTitle(_ seconds: Int, locale: Locale) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated).locale(locale))
    }

    /// What the Settings picker offers: never a value the lock would
    /// silently override.
    static func offeredChoices(mouseLocked: Bool) -> [Int] {
        unlockChoices.filter { clampedSeconds($0, mouseLocked: mouseLocked) == $0 }
    }

    var effective: LockConfiguration {
        guard mode == .advanced else {
            return LockConfiguration(
                mode: .basic,
                blockModifierKeys: true,
                blockMediaKeys: true,
                blockMouseAndTrackpad: false,
                autoUnlockSeconds: 0,
                keepDisplayAwake: keepDisplayAwake,
                startDelaySeconds: Self.sanitizedStartDelay(startDelaySeconds)
            )
        }
        var c = self
        c.startDelaySeconds = Self.sanitizedStartDelay(c.startDelaySeconds)
        c.autoUnlockSeconds = Self.clampedSeconds(c.autoUnlockSeconds, mouseLocked: c.blockMouseAndTrackpad)
        return c
    }

    static var current: LockConfiguration { load(from: .standard) }

    /// The stored settings with the safety rules applied.
    static func load(from d: UserDefaults) -> LockConfiguration {
        func boolOr(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        let cfg = LockConfiguration(
            mode: LockMode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .basic,
            blockModifierKeys: boolOr(Key.blockModifierKeys, true),
            blockMediaKeys: boolOr(Key.blockMediaKeys, true),
            blockMouseAndTrackpad: boolOr(Key.blockMouseAndTrackpad, false),
            autoUnlockSeconds: d.integer(forKey: Key.autoUnlockSeconds),
            keepDisplayAwake: boolOr(Key.keepDisplayAwake, true),
            startDelaySeconds: d.integer(forKey: Key.startDelaySeconds)
        )
        return cfg.effective
    }

    /// 1.1.x let "Off" be picked while mouse lockdown was on. 1.2's
    /// picker no longer offers it and showed a blank selection, so such a
    /// stored value is raised to what the lock uses. Idempotent.
    static func normalizeStoredAutoUnlock(in d: UserDefaults) {
        guard d.bool(forKey: Key.blockMouseAndTrackpad) else { return }
        let stored = d.integer(forKey: Key.autoUnlockSeconds)
        let clamped = clampedSeconds(stored, mouseLocked: true)
        if clamped != stored { d.set(clamped, forKey: Key.autoUnlockSeconds) }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("language") private var language: LanguagePreference = .system
    @AppStorage(LockConfiguration.Key.mode) private var lockMode: LockMode = .basic
    @AppStorage(LockConfiguration.Key.blockModifierKeys) private var blockModifierKeys = true
    @AppStorage(LockConfiguration.Key.blockMediaKeys) private var blockMediaKeys = true
    @AppStorage(LockConfiguration.Key.blockMouseAndTrackpad) private var blockMouseAndTrackpad = false
    @AppStorage(LockConfiguration.Key.autoUnlockSeconds) private var autoUnlockSeconds = 0
    @AppStorage(SystemSounds.enabledKey) private var playSounds = true
    @AppStorage(LockConfiguration.Key.keepDisplayAwake) private var keepDisplayAwake = true
    @Binding var isPresented: Bool
    /// The in-app language (set by the popover), for the duration labels.
    @Environment(\.locale) private var locale

    // Mirrors SMAppService, which the user can also change from System
    // Settings — re-read on appear instead of persisting it ourselves.
    @AppStorage(HotKeyPreset.defaultsKey) private var hotKey: HotKeyPreset = HotKeyPreset.defaultValue
    @AppStorage(AppDelegate.hotKeyConflictKey) private var hotKeyConflict = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginItemNeedsApproval = LaunchAtLogin.requiresApproval

    @EnvironmentObject private var updates: UpdateChecker
    @State private var updateChecksOn: Bool

    /// How tall the settings may grow before they scroll.
    private let maxContentHeight: CGFloat

    /// The panel hangs from the menu bar and must fit under it: the visible
    /// screen height less room for the header, the footer and the popover's
    /// own margin. A small MacBook screen ends up near 700 points.
    static var defaultMaxContentHeight: CGFloat {
        max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 190)
    }

    init(
        isPresented: Binding<Bool>,
        updateChecksOn: Bool = UserDefaults.standard.bool(forKey: UpdateCheck.Key.enabled),
        maxContentHeight: CGFloat = SettingsView.defaultMaxContentHeight
    ) {
        _isPresented = isPresented
        _updateChecksOn = State(initialValue: updateChecksOn)
        self.maxContentHeight = maxContentHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Taller than the screen allows, the settings scroll instead
            // of running off its bottom edge.
            ScrollView { content }
                .frame(maxHeight: maxContentHeight)
            Divider()
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Settings")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Mode") {
                Picker("Mode", selection: $lockMode) {
                    ForEach(LockMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if lockMode == .advanced {
                    advancedControls
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            section("While locked") {
                Toggle("Keep the screen awake", isOn: $keepDisplayAwake)
                    .font(.callout)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("Stops the screen from dimming or going to sleep while the keyboard is locked, so the screen saver or a screen lock does not end the lock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Sound") {
                Toggle("Play sounds", isOn: $playSounds)
                    .font(.callout)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(LanguagePreference.allCases) { lang in
                        lang.label.tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            section("Quick Access") {
                startupControls
            }

            section("Updates") {
                updateControls
            }

            section("Help") {
                HStack(spacing: 8) {
                    Button("Show Welcome Screen") {
                        isPresented = false
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    }

                    if !WhatsNew.allNotes(current: WhatsNew.currentVersion).isEmpty {
                        Button("What's New") {
                            isPresented = false
                            NotificationCenter.default.post(name: .showWhatsNew, object: nil)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(18)
        .animation(.easeInOut(duration: 0.2), value: lockMode)
        .animation(.easeInOut(duration: 0.2), value: blockMouseAndTrackpad)
    }

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Block modifier keys", isOn: $blockModifierKeys)
            Toggle("Block media & brightness keys", isOn: $blockMediaKeys)
            Toggle("Block mouse & trackpad", isOn: $blockMouseAndTrackpad)
                .onChange(of: blockMouseAndTrackpad) { _, on in
                    // Mouse lockdown removes the click-to-unlock exit, so
                    // force a minimum auto-unlock timer.
                    let clamped = LockConfiguration.clampedSeconds(autoUnlockSeconds, mouseLocked: on)
                    if clamped != autoUnlockSeconds { autoUnlockSeconds = clamped }
                }

            HStack {
                Text("Auto-unlock")
                    .font(.callout)
                Spacer()
                Picker("Auto-unlock", selection: $autoUnlockSeconds) {
                    ForEach(offeredUnlockChoices, id: \.self) { s in
                        autoUnlockLabel(s)
                            .tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .onChange(of: autoUnlockSeconds) { _, seconds in
                    // LockConfiguration.effective clamps this anyway, so
                    // without the clamp here the picker would keep showing
                    // a duration the lock is not going to use.
                    let clamped = LockConfiguration.clampedSeconds(seconds, mouseLocked: blockMouseAndTrackpad)
                    if clamped != seconds { autoUnlockSeconds = clamped }
                }
            }

            if blockMouseAndTrackpad {
                Label("Mouse will be frozen. Hold Esc for 3s to force unlock.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

                Text("With the mouse frozen, the lock lasts at most \(LockConfiguration.unlockChoiceTitle(LockConfiguration.maxMouseLockSeconds, locale: locale)). Above \(LockConfiguration.unlockChoiceTitle(LockConfiguration.escCheckAboveSeconds, locale: locale)), dirtymac asks you to hold Esc first to check your way out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var startupControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Global shortcut")
                Spacer()
                Picker("Global shortcut", selection: $hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        preset.label.tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            if hotKey != .off && hotKeyConflict {
                Label("Another app is using this shortcut. Pick a different one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    guard on != LaunchAtLogin.isEnabled else { return }
                    LaunchAtLogin.set(on)
                    LaunchAtLogin.markOffered()
                    refreshLoginItemState()
                }

            if loginItemNeedsApproval {
                Button("Allow in Login Items…") {
                    LaunchAtLogin.openLoginItemsSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear(perform: refreshLoginItemState)
    }

    /// The only switch that lets dirtymac use the network, so the
    /// sentence under it says exactly what that means.
    private var updateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Check for updates", isOn: $updateChecksOn)
                .font(.callout)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: updateChecksOn) { _, on in
                    updates.setEnabled(on)
                }

            Text("dirtymac takes your privacy seriously, so it stays offline by default. If you like, you can allow it to check once a day whether a new version is out. Only the latest version number is requested from GitHub. No personal data or usage information leaves your Mac. As with any web request, GitHub can see your IP address.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if updateChecksOn {
                HStack(spacing: 10) {
                    Button("Check now") {
                        Task { await updates.check() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updates.status == .checking)

                    updateStatus
                }
            }
        }
        // Settings can be opened right after the toggle was changed from
        // the reminder: show what the model holds, not what was cached.
        .onAppear { updateChecksOn = updates.isEnabled }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.status {
        case .checking:
            Text("Checking…")
        case .upToDate:
            Text("dirtymac is up to date.")
        case .failed:
            Text("Couldn't check for updates. Try again later.")
        case .idle:
            EmptyView()
        }
    }

    private func refreshLoginItemState() {
        launchAtLogin = LaunchAtLogin.isEnabled
        loginItemNeedsApproval = LaunchAtLogin.requiresApproval
    }

    /// Once the mouse is part of the lockdown the menu bar can no longer
    /// be clicked, so "Off" and anything under the minimum are not
    /// offered — the lock would silently override them anyway.
    private var offeredUnlockChoices: [Int] {
        LockConfiguration.offeredChoices(mouseLocked: blockMouseAndTrackpad)
    }

    @ViewBuilder
    private func autoUnlockLabel(_ seconds: Int) -> some View {
        if seconds == 0 {
            Text("Off")
        } else {
            Text(LockConfiguration.unlockChoiceTitle(seconds, locale: locale))
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(versionString)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(short)"
    }
}

#Preview {
    SettingsView(isPresented: .constant(true))
        .environmentObject(UpdateChecker())
        .frame(width: 300)
}
