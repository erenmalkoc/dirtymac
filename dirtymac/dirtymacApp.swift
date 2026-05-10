import SwiftUI

@main
struct dirtymacApp: App {
    @StateObject private var blocker = KeyboardBlocker()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(blocker)
        } label: {
            Image(systemName: "keyboard.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(blocker.isActive ? Color.red : Color.primary)
                .symbolEffect(.pulse, options: .repeating, isActive: blocker.isActive)
                .accessibilityLabel(blocker.isActive ? "dirtymac — keyboard locked" : "dirtymac")
        }
        .menuBarExtraStyle(.window)
    }
}
