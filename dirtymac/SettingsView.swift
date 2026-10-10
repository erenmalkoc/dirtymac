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
    }

    var mode: LockMode = .basic
    var blockModifierKeys = true
    var blockMediaKeys = true
    var blockMouseAndTrackpad = false
    var autoUnlockSeconds = 0          // 0 = off

    /// Auto-unlock is mandatory (and at least this long) once the mouse
    /// is part of the lockdown — the menu bar can no longer be clicked.
    static let minMouseLockSeconds = 30

    /// Selectable auto-unlock durations, in seconds. 0 = off.
    static let unlockChoices = [0, 30, 60, 120, 300]

    /// The auto-unlock the lock really uses for a stored value: once the
    /// mouse is part of the lockdown the menu bar can no longer be
    /// clicked, so it is never off and never shorter than the minimum.
    static func clampedSeconds(_ seconds: Int, mouseLocked: Bool) -> Int {
        mouseLocked ? max(seconds, minMouseLockSeconds) : seconds
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
                autoUnlockSeconds: 0
            )
        }
        var c = self
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
            autoUnlockSeconds: d.integer(forKey: Key.autoUnlockSeconds)
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
    @Binding var isPresented: Bool

    // Mirrors SMAppService, which the user can also change from System
    // Settings — re-read on appear instead of persisting it ourselves.
    @AppStorage(HotKeyPreset.defaultsKey) private var hotKey: HotKeyPreset = HotKeyPreset.defaultValue
    @AppStorage(AppDelegate.hotKeyConflictKey) private var hotKeyConflict = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginItemNeedsApproval = LaunchAtLogin.requiresApproval

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
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
            Text(
                Duration.seconds(seconds)
                    .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
            )
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
        .frame(width: 300)
}
