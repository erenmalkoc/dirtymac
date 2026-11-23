import AppKit

/// A nearly invisible window over every screen while the keyboard is locked.
///
/// macOS 27 hands trackpad scrolling to apps without it passing any event
/// tap, so the taps cannot stop it. A window is not asked: the scroll goes
/// to the window under the cursor, and while this one is there that is
/// dirtymac's own, which does nothing with it. Clicks land on it too, so
/// they never reach an app. It leaves the menu bar alone, and the panel
/// and the menu bar icon sit above it, so the lock can always be ended.
/// It goes with the lock, and with the app if the app ever dies.
protocol PointerShielding: AnyObject {
    /// Covers every screen. Safe to call again: it starts over.
    func show()
    /// Takes the cover away. Safe to call when it is not there.
    func hide()
}

/// Where the cover goes on a screen.
nonisolated enum ShieldGeometry {
    /// Just below the menu bar (level 24), above the Dock (20) and every
    /// app window.
    static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)

    /// The screen without its menu bar, so the menu bar icon stays
    /// reachable. The menu bar is measured as what the visible frame leaves
    /// at the top, never less than `menuBarThickness` (a menu bar that
    /// hides in full screen still comes back when the cursor goes up).
    static func frame(screenFrame: NSRect, visibleFrame: NSRect, menuBarThickness: CGFloat) -> NSRect {
        let top = max(menuBarThickness, screenFrame.maxY - visibleFrame.maxY)
        return NSRect(
            x: screenFrame.minX, y: screenFrame.minY,
            width: screenFrame.width, height: max(0, screenFrame.height - top)
        )
    }
}

/// Takes mouse, scroll and trackpad events and does nothing with them.
final class ShieldView: NSView {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func smartMagnify(with event: NSEvent) {}
}

/// Never takes focus from the app the person was in.
final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ScreenShield: PointerShielding {
    private(set) var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?

    /// Not fully clear: a window with nothing drawn would let the events
    /// through to what is behind it.
    static let tint = NSColor.black.withAlphaComponent(0.01)

    func show() {
        hide()
        cover()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cover() }
        }
    }

    func hide() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        close(windows)
        windows = []
    }

    /// One window per screen, rebuilt when the screens change (a monitor
    /// plugged in during a lock must not be a way around it).
    private func cover() {
        close(windows)
        windows = NSScreen.screens.map(makeWindow)
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func close(_ windows: [NSWindow]) {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let frame = ShieldGeometry.frame(
            screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            menuBarThickness: NSStatusBar.system.thickness
        )
        let window = ShieldWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.level = ShieldGeometry.level
        window.isOpaque = false
        window.backgroundColor = Self.tint
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = ShieldView(frame: NSRect(origin: .zero, size: frame.size))
        return window
    }

    deinit {
        MainActor.assumeIsolated { hide() }
    }
}
