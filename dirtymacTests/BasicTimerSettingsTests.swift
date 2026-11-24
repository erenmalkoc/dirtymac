import XCTest
import SwiftUI
import AppKit
@testable import dirtymac

/// The Auto-unlock choice is in Settings in Basic mode too.
@MainActor
final class BasicTimerSettingsTests: XCTestCase {
    private func settings(mode: LockMode, language: String = "en", stored: Int = 300, cap: CGFloat = 10_000) throws -> NSHostingView<some View> {
        let defaults = try TestDefaults.make(self)
        defaults.set(mode.rawValue, forKey: LockConfiguration.Key.mode)
        defaults.set(stored, forKey: LockConfiguration.Key.autoUnlockSeconds)
        return ViewHost.host(
            SettingsView(isPresented: .constant(true), maxContentHeight: cap)
                .defaultAppStorage(defaults)
                .environmentObject(UpdateChecker(defaults: defaults, currentVersion: "1.4.0"))
                .environment(\.locale, Locale(identifier: language))
        )
    }

    /// Basic Settings grew by the Auto-unlock row: the row is about 28 pt
    /// tall and the mode picker's own section alone is much shorter.
    func testBasicSettingsAreTallerThanTheBareModePicker() throws {
        let basic = try settings(mode: .basic)
        ViewHost.snapshot(basic, named: "settings-basic-timer")
        let advanced = try settings(mode: .advanced)
        XCTAssertGreaterThan(advanced.frame.height, basic.frame.height)
        XCTAssertGreaterThan(basic.frame.height, 300)
    }

    func testBasicAndAdvancedBothFitInEveryLanguage() throws {
        for language in LanguagePreference.allCases.filter({ $0 != .system }).map(\.rawValue) {
            let basic = try settings(mode: .basic, language: language, cap: SettingsView.maxContentHeight(forVisibleHeight: 840))
            XCTAssertLessThan(basic.frame.height, 840, "Basic Settings in \(language) is \(basic.frame.height) pt tall")
        }
    }
}
