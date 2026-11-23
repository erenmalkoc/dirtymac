import XCTest
import SwiftUI
import AppKit

/// Throwaway UserDefaults for tests. The tests run inside the app, so
/// `.standard` is the installed app's real preferences; anything that
/// reads or writes settings takes one of these instead. The suite is
/// named after the test, so an aborted run leaves at most one stray
/// plist, which the next run clears.
enum TestDefaults {
    static func make(_ test: XCTestCase) throws -> UserDefaults {
        let suite = "tech.erenium.dirtymacTests." + test.name.filter { $0.isLetter || $0.isNumber }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        test.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}

/// Hosts a SwiftUI view the way the panel does, to measure it and to
/// look at it.
@MainActor
enum ViewHost {
    /// A fixed width, the window background behind it and a chosen
    /// appearance. Without those a picture would be transparent text on
    /// nothing. The height is whatever the content asks for.
    static func host<V: View>(_ view: V, width: CGFloat = 300, dark: Bool = false) -> NSHostingView<some View> {
        let framed = view
            .frame(width: width)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(dark ? .dark : .light)
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    /// Writes a picture when TEST_RUNNER_DIRTYMAC_SNAPSHOT_DIR is set.
    static func snapshot(_ view: NSView, named name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DIRTYMAC_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
