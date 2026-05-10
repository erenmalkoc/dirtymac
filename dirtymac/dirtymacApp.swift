import SwiftUI
import AppKit

@main
struct dirtymacApp: App {
    @StateObject private var blocker = KeyboardBlocker()

    init() {
        // Apply the saved appearance preference at launch so the very
        // first popover render uses the correct light/dark materials.
        DispatchQueue.main.async { AppearancePreference.applyCurrent() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(blocker)
        } label: {
            // Symbol itself swaps (keyboard → lock) so the locked state
            // is unmistakable at a glance, not just a tint change.
            Image(systemName: blocker.isActive ? "lock.fill" : "keyboard.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(blocker.isActive ? Color.red : Color.primary)
                .symbolEffect(.pulse, options: .repeating, isActive: blocker.isActive)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(blocker.isActive ? "dirtymac — keyboard locked" : "dirtymac")
        }
        .menuBarExtraStyle(.window)
    }
}
