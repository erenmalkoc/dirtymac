import SwiftUI
import AppKit
import Combine
import QuartzCore

@main
struct dirtymacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The UI is a hand-managed NSStatusItem + NSPopover (see AppDelegate)
    // so we can support single-click (popover), double-click (quit), and
    // right-click (menu) — none of which MenuBarExtra exposes. The App
    // still needs one Scene; this empty Settings scene is a no-op.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate

/// Owns the shared KeyboardBlocker, the status item + popover, and the
/// first-launch onboarding window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let blocker = KeyboardBlocker()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var lockObserver: AnyCancellable?
    private var pendingSingleClick: DispatchWorkItem?

    private var onboardingWindow: NSWindow?
    private static let onboardedKey = "hasOnboarded"

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearancePreference.applyCurrent()
        setupPopover()
        setupStatusItem()
        observeLockState()

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

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon(active: blocker.isActive)
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { togglePopover(); return }

        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
            return
        }

        // Double-click → quit.
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            NSApp.terminate(nil)
            return
        }

        // Single-click → open popover, but defer by the system double-
        // click interval so the first click of a double-click can be
        // cancelled instead of flashing the popover open.
        pendingSingleClick?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSingleClick = nil
            self?.togglePopover()
        }
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + NSEvent.doubleClickInterval,
            execute: work
        )
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: String(localized: "Open dirtymac"),
            action: #selector(openFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit dirtymac"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 5),
            in: button
        )
    }

    @objc private func openFromMenu() { showPopover() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    // MARK: Popover

    private func setupPopover() {
        let hosting = NSHostingController(
            rootView: MenuBarPopoverView().environmentObject(blocker)
        )
        hosting.sizingOptions = .preferredContentSize
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Icon state

    private func observeLockState() {
        lockObserver = blocker.$isActive
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] active in self?.updateIcon(active: active) }
    }

    /// NSStatusItem can't host SwiftUI symbol effects, so the lock state
    /// is conveyed with a glyph swap, a red tint, and a gentle opacity
    /// "breathe" — the closest AppKit approximation of the SwiftUI icon.
    private func updateIcon(active: Bool) {
        guard let button = statusItem?.button else { return }

        let label = active
            ? String(localized: "dirtymac — keyboard locked")
            : "dirtymac"
        let image = NSImage(
            systemSymbolName: active ? "keyboard.fill" : "keyboard",
            accessibilityDescription: label
        )
        // Template adapts to the menu bar; the locked state needs a real
        // red so it must opt out of template tinting.
        image?.isTemplate = !active
        button.image = image
        button.contentTintColor = active ? .systemRed : nil
        button.toolTip = label

        if active {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1.0
            breathe.toValue = 0.5
            breathe.duration = 1.4
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(breathe, forKey: "breathe")
        } else {
            button.layer?.removeAnimation(forKey: "breathe")
            button.alphaValue = 1.0
        }
    }

    // MARK: Onboarding

    @objc func showOnboarding() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // The onboarding window is AppKit-hosted, outside the popover's
        // SwiftUI scene, so it must be given the same locale + color
        // scheme the popover applies — otherwise it ignores the in-app
        // Language / Appearance settings and falls back to system.
        let root = OnboardingView(onFinish: { [weak self] in
            self?.finishOnboarding()
        })
        .environmentObject(blocker)
        .environment(\.locale, LanguagePreference.current.locale ?? Locale.current)
        .preferredColorScheme(AppearancePreference.current.colorScheme)

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
