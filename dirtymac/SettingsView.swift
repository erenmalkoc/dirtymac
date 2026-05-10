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

    /// Apply this preference app-wide. Reads UserDefaults under the
    /// "appearance" key and pushes the matching NSAppearance to NSApp,
    /// which propagates to the menu bar popover and any future windows.
    static func applyCurrent() {
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? ""
        let pref = AppearancePreference(rawValue: raw) ?? .system
        NSApp?.appearance = pref.nsAppearance
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

    @ViewBuilder
    var label: some View {
        if self == .system {
            Text("System")
        } else {
            Text(verbatim: nativeName)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("language") private var language: LanguagePreference = .system
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
        }
        .padding(18)
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
