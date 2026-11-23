import SwiftUI
import AppKit

/// Root container for the menu bar popover. Switches between the main
/// keyboard-lock control and the settings page, and applies user
/// preferences (appearance + language) to its entire subtree.
struct MenuBarPopoverView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("language") private var language: LanguagePreference = .system
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(isPresented: $showingSettings)
                    .transition(MotionPolicy.slide(from: .trailing, reduceMotion: reduceMotion))
            } else {
                MainView(showingSettings: $showingSettings)
                    .transition(MotionPolicy.slide(from: .leading, reduceMotion: reduceMotion))
            }
        }
        .frame(width: 300)
        // SwiftUI environment override (text, dynamic colors).
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.locale, language.locale ?? .current)
        .animation(MotionPolicy.animation(.easeInOut(duration: 0.22), reduceMotion: reduceMotion), value: showingSettings)
        // AppKit-level override — applied once at launch (see
        // AppDelegate.applicationDidFinishLaunching) and on user change.
        // Re-applying on every popover open triggers a global NSApp
        // redraw for no reason.
        .onChange(of: appearance) { _, new in
            NSApp.appearance = new.nsAppearance
        }
    }
}

#Preview {
    MenuBarPopoverView()
        .environmentObject(KeyboardBlocker())
        .environmentObject(UpdateChecker())
}
