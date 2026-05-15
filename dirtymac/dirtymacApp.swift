import SwiftUI
import AppKit

@main
struct dirtymacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(appDelegate.blocker)
        } label: {
            MenuBarLabel(blocker: appDelegate.blocker)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar status item. A dedicated view so it observes the
/// blocker and re-renders the icon on lock/unlock.
struct MenuBarLabel: View {
    @ObservedObject var blocker: KeyboardBlocker

    var body: some View {
        Image(systemName: blocker.isActive ? "lock.fill" : "keyboard")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(blocker.isActive ? Color.red : Color.primary)
            .symbolEffect(.pulse, options: .repeating, isActive: blocker.isActive)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(blocker.isActive ? "dirtymac — keyboard locked" : "dirtymac")
    }
}

// MARK: - App Delegate

/// Owns the shared KeyboardBlocker and the first-launch onboarding
/// window. A MenuBarExtra-only app has no Scene whose lifecycle we can
/// hang first-run logic on, so this is managed in AppKit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let blocker = KeyboardBlocker()

    private var onboardingWindow: NSWindow?
    private static let onboardedKey = "hasOnboarded"

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearancePreference.applyCurrent()

        // Re-show on demand (Settings → "Show Welcome Screen").
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboarding),
            name: .showOnboarding,
            object: nil
        )

        if !UserDefaults.standard.bool(forKey: Self.onboardedKey) {
            showOnboarding()
        }
    }

    @objc func showOnboarding() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = OnboardingView(onFinish: { [weak self] in
            self?.finishOnboarding()
        })
        .environmentObject(blocker)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        onboardingWindow?.close()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Closing by any means (Done button or red traffic light)
        // counts as onboarded so we don't nag on every launch. The
        // permission prompt still lives in the popover as a fallback.
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        onboardingWindow = nil
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("dirtymac.showOnboarding")
}
