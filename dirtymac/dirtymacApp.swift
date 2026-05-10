import SwiftUI

@main
struct dirtymacApp: App {
    @StateObject private var blocker = KeyboardBlocker()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(blocker)
        } label: {
            Label {
                Text("dirtymac")
            } icon: {
                Image(systemName: blocker.isActive
                      ? "keyboard.badge.eye.fill"
                      : "keyboard")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
