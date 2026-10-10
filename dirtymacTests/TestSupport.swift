import XCTest

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
