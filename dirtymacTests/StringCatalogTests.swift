import XCTest
@testable import dirtymac

/// Guards the 12-language promise. The catalog is read from the source
/// tree (through #filePath) so the checks see exactly what is committed;
/// the compiled tables are read from the app bundle hosting the tests.
final class StringCatalogTests: XCTestCase {
    private typealias JSON = [String: Any]

    private let languages = LanguagePreference.allCases
        .filter { $0 != .system }
        .map(\.rawValue)

    private func catalogStrings() throws -> [String: JSON] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // dirtymacTests/
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("dirtymac/Localizable.xcstrings")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? JSON
        )
        return try XCTUnwrap(root["strings"] as? [String: JSON])
    }

    /// The translated value for `language`, nil when missing or not
    /// marked as translated.
    private func value(_ entry: JSON, _ language: String) -> String? {
        let localizations = entry["localizations"] as? [String: JSON]
        guard let unit = localizations?[language]?["stringUnit"] as? JSON,
              unit["state"] as? String == "translated",
              let value = unit["value"] as? String, !value.isEmpty
        else { return nil }
        return value
    }

    private func isTranslatable(_ entry: JSON) -> Bool {
        entry["shouldTranslate"] as? Bool != false
    }

    func testEveryKeyIsTranslatedIntoEveryLanguage() throws {
        var missing: [String] = []
        for (key, entry) in try catalogStrings() where isTranslatable(entry) {
            for language in languages where value(entry, language) == nil {
                missing.append("\(language): \(key)")
            }
        }
        XCTAssertEqual(missing.sorted(), [], "untranslated strings")
    }

    func testTranslationsKeepTheFormatSpecifiers() throws {
        var mismatched: [String] = []
        for (key, entry) in try catalogStrings() where isTranslatable(entry) {
            let expected = Self.specifiers(in: key)
            for language in languages {
                guard let translated = value(entry, language) else { continue }
                if Self.specifiers(in: translated) != expected {
                    mismatched.append("\(language): \(key) → \(translated)")
                }
            }
        }
        XCTAssertEqual(mismatched.sorted(), [], "format specifiers differ from the key")
    }

    func testCatalogHasNoStaleKeys() throws {
        let stale = try catalogStrings()
            .filter { $0.value["extractionState"] as? String == "stale" }
            .map(\.key)
        XCTAssertEqual(stale, [], "stale keys can never be shown; delete them")
    }

    func testCatalogLanguagesMatchTheLanguagePicker() throws {
        var found = Set<String>()
        for entry in try catalogStrings().values {
            if let localizations = entry["localizations"] as? JSON {
                found.formUnion(localizations.keys)
            }
        }
        XCTAssertEqual(found, Set(languages))
    }

    func testAppBundleShipsEveryLanguage() {
        for language in languages {
            XCTAssertNotNil(
                Bundle.main.path(forResource: language, ofType: "lproj"),
                "\(language).lproj is missing from the app bundle"
            )
        }
    }

    /// The compiled .lproj tables are what the in-app language switch and
    /// AppKit lookups read; they must carry the catalog's values.
    func testCompiledTablesMatchTheCatalog() throws {
        let strings = try catalogStrings()
        var wrong: [String] = []
        for language in languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for (key, entry) in strings where isTranslatable(entry) {
                guard let expected = value(entry, language) else { continue }
                let actual = bundle.localizedString(forKey: key, value: "<missing>", table: "Localizable")
                if actual != expected { wrong.append("\(language): \(key) → \(actual)") }
            }
        }
        XCTAssertEqual(wrong.sorted(), [], "compiled tables differ from the catalog")
    }

    /// Format specifiers in order of appearance, positional indexes
    /// dropped ("%1$@" counts as "%@"); "%%" is a literal and ignored.
    static func specifiers(in text: String) -> [String] {
        let pattern = "%(?:[0-9]+\\$)?(lld|ld|d|@|f|s|u)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range)
            .compactMap { Range($0.range(at: 1), in: text).map { "%" + String(text[$0]) } }
            .sorted()
    }

    func testSpecifierParsing() {
        XCTAssertEqual(Self.specifiers(in: "Unlocks in %@"), ["%@"])
        XCTAssertEqual(Self.specifiers(in: "%1$@ and %2$lld"), ["%@", "%lld"])
        XCTAssertEqual(Self.specifiers(in: "100%% sure"), [])
        XCTAssertEqual(Self.specifiers(in: "no placeholders"), [])
    }
}
