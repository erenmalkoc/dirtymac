import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// What the update notice, the Settings section, the menu bar dot and the
/// What's New offer put in front of the user, and that they fit.
@MainActor
final class UpdateInterfaceTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let languages = LanguagePreference.allCases.filter { $0 != .system }.map(\.rawValue)

    // MARK: Which buttons

    func testAFoundVersionOffersItsNotesAndTheWayToInstall() {
        XCTAssertEqual(
            UpdateNoticeAction.actions(for: .available("1.5.0"), homebrew: true),
            [.releaseNotes("1.5.0"), .copyBrewCommand]
        )
        XCTAssertEqual(
            UpdateNoticeAction.actions(for: .available("1.5.0"), homebrew: false),
            [.releaseNotes("1.5.0"), .download("1.5.0")]
        )
    }

    func testTheReminderOffersTheReleasesTheSettingAndLater() {
        for homebrew in [true, false] {
            XCTAssertEqual(
                UpdateNoticeAction.actions(for: .reminder(days: 61), homebrew: homebrew),
                [.viewReleases, .turnOnChecks, .later]
            )
        }
    }

    func testOnlyTheOpeningButtonsHaveAnAddressAndItIsOnGitHub() {
        let all: [UpdateNoticeAction] = [
            .releaseNotes("1.5.0"), .copyBrewCommand, .download("1.5.0"), .viewReleases, .turnOnChecks, .later,
        ]
        let withURL = all.filter { $0.url != nil }
        XCTAssertEqual(withURL, [.releaseNotes("1.5.0"), .download("1.5.0"), .viewReleases])
        for action in withURL {
            let url = action.url
            XCTAssertEqual(url?.scheme, "https")
            XCTAssertEqual(url?.host, "github.com")
            XCTAssertTrue(url?.path.hasPrefix("/erenmalkoc/dirtymac/releases") ?? false, "\(String(describing: url))")
        }
    }

    func testNothingIsSwitchedOnForTheUser() throws {
        XCTAssertFalse(UpdateCheck.enabledByDefault)
        let checker = UpdateChecker(defaults: try TestDefaults.make(self), currentVersion: "1.4.0")
        XCTAssertFalse(checker.isEnabled)
        XCTAssertFalse(UpdateCheck.wasOffered(in: try TestDefaults.make(self)))
    }

    func testAnsweringEitherWayEndsTheOneTimeOffer() throws {
        for answer in [true, false] {
            let defaults = try TestDefaults.make(self)
            let checker = UpdateChecker(
                defaults: defaults, currentVersion: "1.4.0",
                fetch: { "1.4.0" }
            )
            checker.setEnabled(answer)
            XCTAssertTrue(UpdateCheck.wasOffered(in: defaults), "answer \(answer)")
            XCTAssertEqual(checker.isEnabled, answer)
        }
    }

    func testSayingNoToTheOfferAsksNothingOfTheNetwork() async throws {
        var requests = 0
        let checker = UpdateChecker(
            defaults: try TestDefaults.make(self), currentVersion: "1.4.0",
            fetch: { requests += 1; return "1.4.0" }
        )
        checker.setEnabled(false)
        checker.start()
        await checker.check()
        XCTAssertEqual(requests, 0)
    }

    func testSettingTheSameValueAgainStartsNoSecondRequest() async throws {
        var requests = 0
        let checker = UpdateChecker(
            defaults: try TestDefaults.make(self), currentVersion: "1.4.0",
            fetch: { requests += 1; return "1.4.0" }
        )
        checker.setEnabled(true)
        await checker.pendingCheck?.value
        checker.setEnabled(true)   // Settings re-syncing its switch on appear
        await checker.pendingCheck?.value
        XCTAssertEqual(requests, 1)
    }

    func testTheShippedWhatsNewAnnouncesUpdateChecks() throws {
        let note = try XCTUnwrap(WhatsNew.catalog.first { $0.version == "1.4.0" })
        XCTAssertEqual(note.items.count, 1)
    }

    // MARK: The menu bar dot

    private func render(_ image: NSImage, side: Int = 36) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    func testTheBadgeKeepsTheGlyphsKindAndSize() throws {
        let plainIdle = try XCTUnwrap(AppDelegate.statusImage(active: false))
        let badgedIdle = try XCTUnwrap(AppDelegate.statusImage(active: false, badged: true))
        XCTAssertEqual(badgedIdle.size, plainIdle.size)
        XCTAssertTrue(badgedIdle.isTemplate, "the idle glyph must keep adapting to the menu bar")

        let badgedLocked = try XCTUnwrap(AppDelegate.statusImage(active: true, badged: true))
        XCTAssertFalse(badgedLocked.isTemplate, "the locked glyph stays red, not a template")
    }

    func testTheBadgeAddsADotInTheTopRightCornerAndChangesNothingElse() throws {
        for active in [false, true] {
            let plain = try render(try XCTUnwrap(AppDelegate.statusImage(active: active)))
            let badged = try render(try XCTUnwrap(AppDelegate.statusImage(active: active, badged: true)))
            // The dot is 30 % of the height, plus its gap: stay out of that corner.
            let cornerSize = 36 - Int(36 * 0.3) - 4
            var differsInCorner = 0
            var differsElsewhere = 0
            for x in 0..<36 {
                for y in 0..<36 {   // y counts from the top
                    let changed = abs(alpha(plain, x, y) - alpha(badged, x, y)) > 0.05
                    guard changed else { continue }
                    if x >= cornerSize && y < 36 - cornerSize { differsInCorner += 1 } else { differsElsewhere += 1 }
                }
            }
            XCTAssertGreaterThan(differsInCorner, 20, "locked=\(active): the dot is drawn")
            XCTAssertEqual(differsElsewhere, 0, "locked=\(active): nothing outside the corner changes")

            // The very corner is opaque, so the dot can be seen.
            XCTAssertGreaterThan(alpha(badged, 33, 3), 0.9, "locked=\(active)")
        }
    }

    /// A strip of the four glyphs, enlarged, on light and dark menu bars,
    /// to look at (written only when a snapshot folder is given).
    func testMenuBarGlyphPicture() throws {
        guard let dir = ProcessInfo.processInfo.environment["DIRTYMAC_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let cell = 144
        let variants: [(Bool, Bool)] = [(false, false), (false, true), (true, false), (true, true)]
        let strip = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: cell * variants.count, pixelsHigh: cell * 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: strip)
        for (row, dark) in [(1, false), (0, true)] {
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(x: 0, y: row * cell, width: cell * variants.count, height: cell).fill()
            for (index, variant) in variants.enumerated() {
                guard let image = AppDelegate.statusImage(active: variant.0, badged: variant.1) else { continue }
                // Template glyphs are drawn black on a light bar, white on a dark one.
                let drawn = NSImage(size: image.size, flipped: false) { rect in
                    image.draw(in: rect)
                    if image.isTemplate {
                        (dark ? NSColor.white : NSColor.black).setFill()
                        rect.fill(using: .sourceIn)
                    }
                    return true
                }
                drawn.draw(in: NSRect(x: index * cell + 8, y: row * cell + 8, width: cell - 16, height: cell - 16))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(strip.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("menubar-glyphs.png"))
    }

    // MARK: Fit

    private func host<V: View>(_ view: V, width: CGFloat = 300, dark: Bool = false) -> NSHostingView<some View> {
        ViewHost.host(view, width: width, dark: dark)
    }

    private func snapshot(_ view: NSView, named name: String) {
        ViewHost.snapshot(view, named: name)
    }

    private func checker(found: String? = nil, reminderAfter days: Int? = nil) throws -> UpdateChecker {
        let defaults = try TestDefaults.make(self)
        var clock = start
        if let found {
            defaults.set(true, forKey: UpdateCheck.Key.enabled)
            defaults.set(found, forKey: UpdateCheck.Key.latestVersion)
        }
        UpdateCheck.recordInstalledVersion("1.4.0", now: start, in: defaults)
        if let days { clock = start + Double(days) * day }
        let checker = UpdateChecker(defaults: defaults, currentVersion: "1.4.0", now: { clock })
        checker.refreshReminder()
        return checker
    }

    func testTheNoticeFitsThePanelInEveryLanguage() throws {
        let reminder = try checker(reminderAfter: 61)
        let found = try checker(found: "1.5.0")
        XCTAssertNotNil(reminder.notice)
        XCTAssertNotNil(found.notice)

        for language in languages {
            for (name, model) in [("reminder", reminder), ("found", found)] {
                let view = UpdateNoticeView(openSettings: {})
                    .environmentObject(model)
                    .environment(\.locale, Locale(identifier: language))
                let hosting = host(view)
                let height = hosting.frame.height
                XCTAssertGreaterThan(height, 40, "\(language) \(name): the notice is drawn")
                XCTAssertLessThan(height, 230, "\(language) \(name): \(height) pt tall")
                snapshot(hosting, named: "notice-\(name)-\(language)")
            }
        }
    }

    func testDarkAppearanceLayoutsAreDrawn() throws {
        let reminder = try checker(reminderAfter: 61)
        let found = try checker(found: "1.5.0")
        for (name, model) in [("reminder", reminder), ("found", found)] {
            let panel = host(
                MainView(showingSettings: .constant(false))
                    .environmentObject(KeyboardBlocker())
                    .environmentObject(model),
                dark: true
            )
            XCTAssertGreaterThan(panel.frame.height, 200)
            snapshot(panel, named: "panel-\(name)-dark")
        }
        let settings = host(
            SettingsView(isPresented: .constant(true), updateChecksOn: true).environmentObject(found),
            dark: true
        )
        snapshot(settings, named: "settings-dark")
        let offer = host(
            WhatsNewView(notes: WhatsNew.allNotes(current: "1.4.0"), offerLaunchAtLogin: true,
                         offerUpdateChecks: true, onFinish: { _, _ in }),
            width: 460, dark: true
        )
        snapshot(offer, named: "whatsnew-dark")
    }

    func testNoNoticeTakesNoSpace() throws {
        let quiet = try checker()
        XCTAssertNil(quiet.notice)
        let hosting = host(UpdateNoticeView(openSettings: {}).environmentObject(quiet))
        XCTAssertEqual(hosting.frame.height, 0, accuracy: 0.5)
    }

    func testSettingsStaysShortEnoughForASmallScreenInEveryLanguage() throws {
        // Advanced mode with its extra controls and the update buttons
        // showing is the tallest Settings gets. A MacBook Air's screen
        // leaves about 840 pt under the menu bar.
        let defaults = try TestDefaults.make(self)
        defaults.set(LockMode.advanced.rawValue, forKey: LockConfiguration.Key.mode)
        // A model with checks on, or Settings would switch its toggle off
        // again when it appears.
        let model = try checker(found: "1.5.0")
        XCTAssertTrue(model.isEnabled)
        var tallest: (String, CGFloat) = ("", 0)
        for language in languages {
            let view = SettingsView(isPresented: .constant(true), updateChecksOn: true)
                .defaultAppStorage(defaults)
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: language))
            let hosting = host(view)
            if hosting.frame.height > tallest.1 { tallest = (language, hosting.frame.height) }
            snapshot(hosting, named: "settings-\(language)")
        }
        print("tallest Settings: \(tallest.0) \(tallest.1) pt")
        XCTAssertLessThan(tallest.1, 840, "Settings in \(tallest.0) is \(tallest.1) pt tall")
    }

    func testThePanelWithANoticeStaysShortEnoughInEveryLanguage() throws {
        let model = try checker(reminderAfter: 61)
        var tallest: (String, CGFloat) = ("", 0)
        for language in languages {
            let view = MainView(showingSettings: .constant(false))
                .environmentObject(KeyboardBlocker())
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: language))
            let hosting = host(view)
            if hosting.frame.height > tallest.1 { tallest = (language, hosting.frame.height) }
            snapshot(hosting, named: "panel-reminder-\(language)")
        }
        print("tallest panel: \(tallest.0) \(tallest.1) pt")
        XCTAssertLessThan(tallest.1, 600, "the panel in \(tallest.0) is \(tallest.1) pt tall")
    }

    /// The window most people will see: coming from the last release, with
    /// only the 1.4.0 note above the offer. Looked at through the pictures
    /// (the window is a fixed size, so there is no height to assert).
    func testTheWhatsNewOfferAfterAnOrdinaryUpdateIsDrawnInEveryLanguage() throws {
        let notes = WhatsNew.notesToShow(current: "1.4.0", lastSeen: "1.3.2")
        XCTAssertEqual(notes.map(\.version), ["1.4.0"])
        for language in languages {
            let view = WhatsNewView(
                notes: notes, offerLaunchAtLogin: true, offerUpdateChecks: true, onFinish: { _, _ in }
            )
            .environment(\.locale, Locale(identifier: language))
            .frame(width: 460, height: 560)
            let hosting = host(view, width: 460)
            snapshot(hosting, named: "whatsnew-ordinary-\(language)")
            XCTAssertEqual(hosting.frame.height, 560, accuracy: 0.5, language)
        }
    }

    func testTheWhatsNewOfferFitsItsFixedWindowInEveryLanguage() throws {
        for language in languages {
            let view = WhatsNewView(
                notes: WhatsNew.allNotes(current: "1.4.0"),
                offerLaunchAtLogin: true,
                offerUpdateChecks: true,
                onFinish: { _, _ in }
            )
            .environment(\.locale, Locale(identifier: language))
            let hosting = host(view, width: 460)
            snapshot(hosting, named: "whatsnew-\(language)")
            // The window is a fixed 460 x 560: the content must not ask for more.
            XCTAssertLessThanOrEqual(hosting.frame.height, 560.5, "\(language): \(hosting.frame.height)")
        }
    }
}
