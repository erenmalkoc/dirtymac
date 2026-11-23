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
    let updates = UpdateChecker()
    /// Created with the delegate: the closure reaches the delegate only
    /// when a click needs the panel, long after init.
    private(set) lazy var quickLock = QuickLockController(blocker: blocker) { [weak self] in
        self?.showPopover()
    }
    private var updateObserver: AnyCancellable?
    private var lockTitleObserver: AnyCancellable?

    override init() {
        super.init()
        Self.shared = self
    }

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var lockObserver: AnyCancellable?
    private var secureInputObserver: AnyCancellable?

    private var onboardingWindow: NSWindow?
    private static let onboardedKey = "hasOnboarded"
    private var whatsNewWindow: NSWindow?
    private var whatsNewOffersUpdateChecks = false

    private var hotKey: GlobalHotKey?
    private var registeredHotKey: HotKeyPreset?
    private var defaultsObserver: NSObjectProtocol?
    private var sessionWatcher: SessionWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit calls this from inside the launch Apple event's handler,
        // the only moment that event can be read (it is still nil in
        // applicationWillFinishLaunching, which left every login launch
        // looking like a manual one and opened the panel at each login).
        let loginItemLaunch = Self.isLoginItemLaunch(NSAppleEventManager.shared().currentAppleEvent)

        // As the unit-test host the app must stay inert: no status item,
        // no global shortcut, no windows and no writes to the user's
        // defaults (onboarding / What's New bookkeeping).
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        LockConfiguration.normalizeStoredAutoUnlock(in: .standard)
        AppearancePreference.applyCurrent()
        // Force the bundle-icon Launch Services lookup to happen now
        // (during app launch, off the popover-open hot path) instead of
        // the first time the user clicks the menu bar.
        _ = AppIconView.bundleIcon
        setupPopover()
        setupStatusItem()
        observeLockState()
        observeUpdates()
        observeLockTitle()
        // With update checks off (the default) this only counts days.
        updates.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboarding),
            name: .showOnboarding,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showAllReleaseNotes),
            name: .showWhatsNew,
            object: nil
        )

        setupHotKey()
        watchSession()

        if !UserDefaults.standard.bool(forKey: Self.onboardedKey) {
            showOnboarding()
        } else if presentWhatsNewIfNeeded() {
            // The window is the launch's visible response.
        } else if Self.isUserInitiatedLaunch(loginItem: loginItemLaunch, userInfo: notification.userInfo) {
            // Let the status item get its window before anchoring to it.
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    /// Launching an already-running menu bar app again (Spotlight, Finder,
    /// the Dock's recents) lands here. Without this, nothing visible
    /// happens and the app looks broken.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app after an update that replaced it on disk lands
        // here, in the stale copy: start the new version instead.
        if relaunchIfReplaced() { return false }
        if let window = onboardingWindow ?? whatsNewWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showPopover()
        }
        return false
    }

    /// True for the 'oapp' event macOS sends when it starts a login item.
    static func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication)
        else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }

    /// A login item launch stays silent; a launch the user asked for
    /// (Spotlight, Finder, Launchpad) shows the panel right away.
    static func isUserInitiatedLaunch(loginItem: Bool, userInfo: [AnyHashable: Any]?) -> Bool {
        guard !loginItem else { return false }
        // False when macOS launched the app to open a URL or run an
        // intent — those paths decide for themselves what to show.
        return userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
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

    // MARK: Session

    /// Sleep, a locked screen, a user switch or System Settings coming
    /// forward end the lock; see SessionWatcher.
    private func watchSession() {
        let watcher = SessionWatcher { [weak self] reason in
            guard let self else { return }
            // A start delay still counting down must not lock after the
            // Mac woke up or the screen was locked.
            self.blocker.cancelPendingLock()
            guard self.blocker.isActive else { return }
            self.blocker.stop(reason: reason)
        }
        watcher.start()
        sessionWatcher = watcher
    }

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
            title: String(localized: "Open dirtymac", bundle: LanguagePreference.current.bundle),
            action: #selector(openFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let locale = LanguagePreference.current.locale ?? Locale.current
        if let quick = quickLock.makeMenuItem(
            title: String(localized: "Lock for", bundle: LanguagePreference.current.bundle),
            locale: locale
        ) {
            menu.addItem(quick)
        }

        if let version = updates.availableVersion {
            let format = String(localized: "dirtymac \(version) is available.", bundle: LanguagePreference.current.bundle)
            let updateItem = NSMenuItem(title: format, action: #selector(openReleaseNotes), keyEquivalent: "")
            updateItem.target = self
            updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit dirtymac", bundle: LanguagePreference.current.bundle),
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

    @objc private func openReleaseNotes() {
        guard let version = updates.availableVersion else { return }
        NSWorkspace.shared.open(UpdateCheck.notesURL(version: version))
    }
    // Release the keyboard before terminating, exactly like the popover's
    // Quit button. The tap dies with the process either way, but not
    // relying on that keeps both quit paths identical.
    @objc private func quitFromMenu() {
        blocker.stop(reason: .quit)
        NSApp.terminate(nil)
    }

    // MARK: Popover

    private func setupPopover() {
        let hosting = NSHostingController(
            rootView: MenuBarPopoverView()
                .environmentObject(blocker)
                .environmentObject(updates)
        )
        hosting.sizingOptions = .preferredContentSize
        popover.behavior = .transient
        popover.delegate = self
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

    // MARK: Updates

    private var isRelaunching = false

    /// Restarts into the version on disk when an update replaced this
    /// running copy (see InstalledBuild). Returns whether it did.
    @discardableResult
    private func relaunchIfReplaced() -> Bool {
        guard !isRelaunching else { return true }
        guard InstalledBuild.currentWasReplaced else { return false }
        isRelaunching = true
        blocker.stop(reason: .quit)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                // If the new copy didn't start, keep this one rather than
                // leaving no dirtymac at all.
                guard error == nil else {
                    NSLog("dirtymac: relaunch after update failed: \(error?.localizedDescription ?? "")")
                    self.isRelaunching = false
                    return
                }
                NSApp.terminate(nil)
            }
        }
        return true
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        // A stale copy would only show a permission prompt it can't satisfy.
        if relaunchIfReplaced() { return }
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

        // When keys start getting past the lock, bring dirtymac forward:
        // the panel says why, and apps that hold secure input only while
        // they are frontmost (password fields, Terminal) let go of it.
        secureInputObserver = blocker.$secureInput
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self, on, self.blocker.isActive || self.blocker.lastUnlockReason == .secureInput else { return }
                self.showPopover()
            }
    }

    /// NSStatusItem can't host SwiftUI symbol effects, so the lock state
    /// is conveyed with a glyph swap, a red tint, and a gentle opacity
    /// "breathe" — the closest AppKit approximation of the SwiftUI icon.
    /// The keycap glyph from the asset catalog. Idle it is a template that
    /// adapts to the menu bar; locked it is drawn in its own red, which a
    /// template (or contentTintColor on a non-template) could not give.
    static func statusImage(active: Bool, badged: Bool = false) -> NSImage? {
        guard let base = NSImage(named: active ? "MenuBarIconLocked" : "MenuBarIcon")?.copy() as? NSImage else {
            return nil
        }
        guard badged else {
            base.isTemplate = !active
            return base
        }
        // A newer version is out: the same glyph with a small dot in the
        // top-right corner, ringed by a gap so it reads against the keycap.
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let diameter = max(4, (rect.height * 0.3).rounded())
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.25, dy: -1.25)).fill()
            NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
            // A template image keeps only alpha, so the colour matters only
            // for the locked (non-template) glyph.
            (active ? NSColor.white : NSColor.black).setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = !active
        return image
    }

    /// The countdown beside the icon while locked. Built from the values
    /// the publishers hand over, not from reading the blocker: a @Published
    /// property still holds its old value when its subscribers run.
    private func observeLockTitle() {
        lockTitleObserver = Publishers.CombineLatest(
            Publishers.CombineLatest4(
                blocker.$isActive, blocker.$elapsed, blocker.$escHold, blocker.$autoUnlockTotal
            ),
            blocker.$lockCountdown
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] state, countdown in
            guard let button = self?.statusItem?.button else { return }
            let (active, elapsed, escHold, total) = state
            let pending = countdown.map {
                String(localized: "Locking in \($0)…", bundle: LanguagePreference.current.bundle)
            }
            LockStatusTitle.apply(
                LockStatusTitle.text(
                    isActive: active, escHold: escHold, autoUnlockTotal: total,
                    elapsed: elapsed, pendingLockText: pending
                ),
                to: button
            )
        }
    }

    private func observeUpdates() {
        updateObserver = updates.$availableVersion
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateIcon(active: self.blocker.isActive)
            }
    }

    private func updateIcon(active: Bool) {
        guard let button = statusItem?.button else { return }

        let available = updates.availableVersion
        var label = active
            ? String(localized: "dirtymac — keyboard locked", bundle: LanguagePreference.current.bundle)
            : "dirtymac"
        if let available {
            label += " — " + String(localized: "dirtymac \(available) is available.", bundle: LanguagePreference.current.bundle)
        }
        let image = Self.statusImage(active: active, badged: available != nil)
        image?.accessibilityDescription = label
        button.image = image
        button.contentTintColor = nil
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

        let window = makeWindow(root: root, size: NSSize(width: 460, height: 560))
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        onboardingWindow?.close()
    }

    /// Shared chrome for the AppKit-hosted SwiftUI windows (onboarding,
    /// What's New): transparent title bar, draggable background.
    private func makeWindow<Root: View>(root: Root, size: NSSize) -> NSWindow {
        let hosting = NSHostingController(rootView: root)
        // Without this, the window is constructed before SwiftUI has
        // produced a layout, so window.center() ends up centering a
        // tiny default-sized window; when the content then grows the
        // window expands from its bottom-left anchor and visibly drifts
        // off-center.
        hosting.sizingOptions = .preferredContentSize

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        window.delegate = self
        return window
    }

    // MARK: What's New

    /// Shows the release notes the user hasn't seen yet, once per update.
    /// Returns false (and records the version as seen) when there is
    /// nothing new, so a later release is measured from this one.
    private func presentWhatsNewIfNeeded() -> Bool {
        let notes = WhatsNew.notesToShow(
            current: WhatsNew.currentVersion,
            lastSeen: WhatsNew.lastSeenVersion
        )
        guard !notes.isEmpty else {
            WhatsNew.markCurrentSeen()
            return false
        }
        let offer = !LaunchAtLogin.wasOffered && !LaunchAtLogin.isEnabled
        // Asked once, and only of someone who has never answered.
        let offerChecks = !UpdateCheck.wasOffered() && !updates.isEnabled
        showWhatsNew(notes: notes, offerLaunchAtLogin: offer, offerUpdateChecks: offerChecks)
        return true
    }

    @objc private func showAllReleaseNotes() {
        let notes = WhatsNew.allNotes(current: WhatsNew.currentVersion)
        guard !notes.isEmpty else { return }
        showWhatsNew(notes: notes, offerLaunchAtLogin: false)
    }

    private func showWhatsNew(notes: [ReleaseNote], offerLaunchAtLogin: Bool, offerUpdateChecks: Bool = false) {
        if let window = whatsNewWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        whatsNewOffersUpdateChecks = offerUpdateChecks
        let root = WhatsNewView(
            notes: notes,
            offerLaunchAtLogin: offerLaunchAtLogin,
            offerUpdateChecks: offerUpdateChecks,
            onFinish: { [weak self] launchAtLogin, updateChecks in
                if offerLaunchAtLogin {
                    LaunchAtLogin.set(launchAtLogin)
                    LaunchAtLogin.markOffered()
                }
                // Only the box the user ticked turns anything on.
                if offerUpdateChecks { self?.updates.setEnabled(updateChecks) }
                self?.whatsNewWindow?.close()
            }
        )
        .environment(\.locale, LanguagePreference.current.locale ?? Locale.current)
        .preferredColorScheme(AppearancePreference.current.colorScheme)

        let window = makeWindow(root: root, size: NSSize(width: 460, height: 560))
        whatsNewWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSPopoverDelegate {
    /// Lets the panel drop a confirmation that was left open.
    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .panelDidClose, object: nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            // Closing by any means (Done button or red traffic light)
            // counts as onboarded so we don't nag on every launch. The
            // permission prompt still lives in the popover as a fallback.
            UserDefaults.standard.set(true, forKey: Self.onboardedKey)
            // A new user has just been shown everything; the release
            // notes of the version they installed would repeat it.
            WhatsNew.markCurrentSeen()
            onboardingWindow = nil
        } else if window === whatsNewWindow {
            // Seen once, by button or traffic light — never again for
            // this version. Closing without choosing leaves login items
            // alone but still ends the offer.
            WhatsNew.markCurrentSeen()
            LaunchAtLogin.markOffered()
            // The update-check question was on screen: leaving it unticked
            // is an answer too, so it is not asked again.
            if whatsNewOffersUpdateChecks { UpdateCheck.markOffered() }
            whatsNewOffersUpdateChecks = false
            whatsNewWindow = nil
        }
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("dirtymac.showOnboarding")
    static let showWhatsNew = Notification.Name("dirtymac.showWhatsNew")
    static let panelDidClose = Notification.Name("dirtymac.panelDidClose")
}
