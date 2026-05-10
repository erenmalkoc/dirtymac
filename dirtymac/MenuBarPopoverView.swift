import SwiftUI
import AppKit

/// Root container for the menu bar popover. Switches between the main
/// keyboard-lock control and the settings page, and applies user
/// preferences (appearance + language) to its entire subtree.
struct MenuBarPopoverView: View {
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("language") private var language: LanguagePreference = .system
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(isPresented: $showingSettings)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MainView(showingSettings: $showingSettings)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 300)
        // SwiftUI environment override (text, dynamic colors).
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.locale, language.locale ?? .current)
        .animation(.easeInOut(duration: 0.22), value: showingSettings)
        // AppKit-level override — this is what actually flips the
        // popover's vibrancy backdrop and Liquid Glass materials.
        .onAppear { NSApp.appearance = appearance.nsAppearance }
        .onChange(of: appearance) { _, new in
            NSApp.appearance = new.nsAppearance
        }
    }
}

#Preview {
    MenuBarPopoverView()
        .environmentObject(KeyboardBlocker())
}
