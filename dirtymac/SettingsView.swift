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
    /// vibrancy backdrop and `.glassEffect()` materials switch modes.
    /// Without this, only text color responds to `colorScheme`.
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
        if c.blockMouseAndTrackpad, c.autoUnlockSeconds < Self.minMouseLockSeconds {
            c.autoUnlockSeconds = Self.minMouseLockSeconds
        }
        return c
    }

    static var current: LockConfiguration {
        let d = UserDefaults.standard
        func boolOr(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        let cfg = LockConfiguration(
            mode: LockMode(rawValue: d.string(forKey: "lockMode") ?? "") ?? .basic,
            blockModifierKeys: boolOr("blockModifierKeys", true),
            blockMediaKeys: boolOr("blockMediaKeys", true),
            blockMouseAndTrackpad: boolOr("blockMouseAndTrackpad", false),
            autoUnlockSeconds: d.integer(forKey: "autoUnlockSeconds")
        )
        return cfg.effective
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("language") private var language: LanguagePreference = .system
    @AppStorage("lockMode") private var lockMode: LockMode = .basic
    @AppStorage("blockModifierKeys") private var blockModifierKeys = true
    @AppStorage("blockMediaKeys") private var blockMediaKeys = true
    @AppStorage("blockMouseAndTrackpad") private var blockMouseAndTrackpad = false
    @AppStorage("autoUnlockSeconds") private var autoUnlockSeconds = 0
    @Binding var isPresented: Bool

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

            section("Help") {
                Button("Show Welcome Screen") {
                    isPresented = false
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
                .buttonStyle(.glass)
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
                    if on, autoUnlockSeconds < LockConfiguration.minMouseLockSeconds {
                        autoUnlockSeconds = LockConfiguration.minMouseLockSeconds
                    }
                }

            HStack {
                Text("Auto-unlock")
                    .font(.callout)
                Spacer()
                Picker("Auto-unlock", selection: $autoUnlockSeconds) {
                    ForEach(LockConfiguration.unlockChoices, id: \.self) { s in
                        autoUnlockLabel(s)
                            .tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(false)
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
