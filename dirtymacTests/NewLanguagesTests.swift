import XCTest
import AppKit
@testable import dirtymac

/// Polish, Dutch, Ukrainian, Indonesian and Vietnamese. The catalog tests
/// already require every key in every language: these are the things that
/// only matter for a language that was added later.
@MainActor
final class NewLanguagesTests: XCTestCase {
    private let added: [LanguagePreference] = [.pl, .nl, .uk, .indonesian, .vi]

    func testTheFiveAreInThePickerWithTheirOwnNames() {
        let names = Dictionary(uniqueKeysWithValues: added.map { ($0.rawValue, $0.nativeName) })
        XCTAssertEqual(names, [
            "pl": "Polski", "nl": "Nederlands", "uk": "Українська", "id": "Bahasa Indonesia", "vi": "Tiếng Việt",
        ])
        XCTAssertEqual(LanguagePreference.allCases.count, 18, "System plus 17 languages")
    }

    func testEveryLanguageCodeIsUniqueAndResolvesToALocale() {
        let codes = LanguagePreference.allCases.map(\.rawValue)
        XCTAssertEqual(Set(codes).count, codes.count)
        for language in added {
            XCTAssertNotNil(language.locale)
            XCTAssertEqual(language.locale?.identifier, language.rawValue)
        }
    }

    func testEachNewLanguageShipsItsCompiledStrings() throws {
        for language in added {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"), language.rawValue)
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(language.bundle.bundlePath, bundle.bundlePath, "the in-app switch finds it")
            let title = bundle.localizedString(forKey: "Settings", value: "<missing>", table: "Localizable")
            XCTAssertNotEqual(title, "<missing>")
            XCTAssertNotEqual(title, "Settings", "\(language.rawValue) is translated, not English")
        }
    }

    func testTheNewLanguagesAreNotJustEnglishInDisguise() throws {
        let catalog = try catalogStrings()
        for language in added {
            var same: [String] = []
            for (key, entry) in catalog where entry["shouldTranslate"] as? Bool != false {
                let value = ((entry["localizations"] as? [String: Any])?[language.rawValue] as? [String: Any])?["stringUnit"] as? [String: Any]
                if value?["value"] as? String == key { same.append(key) }
            }
            // A few strings read the same in some languages (a bare "Download", "Help").
            XCTAssertLessThan(same.count, 8, "\(language.rawValue) leaves English as it is: \(same)")
        }
    }

    func testTheHeaderSubtitleFitsWithoutBeingCut() throws {
        // The popover header gives the subtitle one line of about 150 points.
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        for language in added {
            let bundle = language.bundle
            let text = bundle.localizedString(forKey: "Keyboard utility", value: "", table: "Localizable")
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(width, 150, "\(language.rawValue): \"\(text)\" is \(width) pt wide")
        }
    }

    func testDurationsAndDatesFormatInTheNewLanguages() {
        for language in added {
            let locale = Locale(identifier: language.rawValue)
            let labels = [30, 60, 300, 900, 3600].map { LockConfiguration.unlockChoiceTitle($0, locale: locale) }
            XCTAssertEqual(Set(labels).count, labels.count, language.rawValue)
            XCTAssertFalse(labels.contains { $0.isEmpty }, language.rawValue)
            XCTAssertTrue(labels.allSatisfy { $0.contains(where: \.isNumber) }, "\(language.rawValue): \(labels)")
        }
    }

    func testTheNumbersInTheCountdownsStayReadable() {
        for language in added {
            let bundle = language.bundle
            for announcement in [StatusAnnouncement.waitingToLock(seconds: 5), .escHold(remaining: 3), .autoUnlockIn(seconds: 60)] {
                let text = announcement.text(bundle: bundle)
                XCTAssertFalse(text.contains("%"), "\(language.rawValue): \(text)")
                XCTAssertTrue(text.contains(where: \.isNumber), "\(language.rawValue): \(text)")
            }
        }
    }

    private func catalogStrings() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dirtymac/Localizable.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: [String: Any]])
    }
}
