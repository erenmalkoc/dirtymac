import SwiftUI
import AppKit
import Combine
import QuartzCore

@main
struct dirtymacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The UI is a hand-managed NSStatusItem + NSPopover (see AppDelegate)
    // so we can support single-click (popover) and right-click (menu) —
    // neither of which MenuBarExtra exposes. The App still needs one
    // Scene; this empty Settings scene is a no-op.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate

/// Owns the shared KeyboardBlocker, the status item + popover, and the
/// first-launch onboarding window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NSApp.delegate` is SwiftUI's adaptor proxy, not this object, so
    /// App Intents reach the running delegate through this reference.
    private(set) static weak var shared: AppDelegate?

    let blocker = KeyboardBlocker()

    override init() {
        super.init()
        Self.shared = self
    }

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var lockObserver: AnyCancellable?

    private var onboardingWindow: NSWindow?
    private static let onboardedKey = "hasOnboarded"

    private var hotKey: GlobalHotKey?
    private var registeredHotKey: HotKeyPreset?
    private var defaultsObserver: NSObjectProtocol?
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch Apple event is only available this early. A login
        // item launch must stay silent; a launch the user asked for
        // (Spotlight, Finder, Launchpad) should show the app right away.
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearancePreference.applyCurrent()
        // Force the bundle-icon Launch Services lookup to happen now
        // (during app launch, off the popover-open hot path) instead of
        // the first time the user clicks the menu bar.
        _ = AppIconView.bundleIcon
        setupPopover()
        setupStatusItem()
        observeLockState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboarding),
            name: .showOnboarding,
            object: nil
        )

        setupHotKey()

        if !UserDefaults.standard.bool(forKey: Self.onboardedKey) {
            showOnboarding()
        } else if isUserInitiatedLaunch(notification) {
            // Let the status item get its window before anchoring to it.
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    /// Launching an already-running menu bar app again (Spotlight, Finder,
    /// the Dock's recents) lands here. Without this, nothing visible
    /// happens and the app looks broken.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboardingWindow == nil { showPopover() }
        return false
    }

    private func isUserInitiatedLaunch(_ notification: Notification) -> Bool {
        guard !launchedAsLoginItem else { return false }
        // False when macOS launched the app to open a URL or run an
        // intent — those paths decide for themselves what to show.
        return notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
    }

    // MARK: Global shortcut

    static let hotKeyConflictKey = "globalHotKeyConflict"

    private func setupHotKey() {
        hotKey = GlobalHotKey { [weak self] in self?.togglePopover() }
        applyHotKeyPreference()
        // Settings writes the preset through @AppStorage; follow it
        // without a relaunch.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.applyHotKeyPreference() }
    }

    private func applyHotKeyPreference() {
        let preset = HotKeyPreset.current
        guard preset != registeredHotKey else { return }
        registeredHotKey = preset
        let ok = hotKey?.register(preset) ?? false
        UserDefaults.standard.set(!ok, forKey: Self.hotKeyConflictKey)
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
        togglePopover()
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
    // Release the keyboard before terminating, exactly like the popover's
    // Quit button. The tap dies with the process either way, but not
    // relying on that keeps both quit paths identical.
    @objc private func quitFromMenu() {
        blocker.stop()
        NSApp.terminate(nil)
    }

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

    /// For callers that may run while the app is still launching (App
    /// Intents): the status item exists only after didFinishLaunching.
    func showPopoverWhenReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.onboardingWindow == nil else {
                self?.onboardingWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            self.showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        guard !popover.isShown else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
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
        // Without this, the window is constructed before SwiftUI has
        // produced a layout, so window.center() ends up centering a
        // tiny default-sized window; when the content then grows to
        // 460x560 the window expands from its bottom-left anchor and
        // visibly drifts off-center.
        hosting.sizingOptions = .preferredContentSize

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 560))
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
