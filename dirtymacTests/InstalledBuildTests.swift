import XCTest
@testable import dirtymac

final class InstalledBuildTests: XCTestCase {
    private func makeBundle(build: String?) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledBuildTests-\(UUID().uuidString).app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle) }
        var info: [String: Any] = ["CFBundleIdentifier": "tech.erenium.dirtymac"]
        if let build { info["CFBundleVersion"] = build }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }

    func testReadsTheBuildOfTheBundleOnDisk() throws {
        XCTAssertEqual(InstalledBuild.onDisk(bundleURL: try makeBundle(build: "202610111136")), "202610111136")
        XCTAssertNil(InstalledBuild.onDisk(bundleURL: try makeBundle(build: nil)))
        XCTAssertNil(InstalledBuild.onDisk(bundleURL: URL(fileURLWithPath: "/nonexistent/dirtymac.app")))
    }

    func testOnlyADifferentBuildOnDiskCountsAsReplaced() {
        XCTAssertTrue(InstalledBuild.wasReplaced(running: "202609231307", onDisk: "202610111136"))
        XCTAssertFalse(InstalledBuild.wasReplaced(running: "202610111136", onDisk: "202610111136"))
        // Mid-uninstall or unreadable: nothing to restart into.
        XCTAssertFalse(InstalledBuild.wasReplaced(running: "202609231307", onDisk: nil))
        XCTAssertFalse(InstalledBuild.wasReplaced(running: nil, onDisk: "202610111136"))
    }

    func testTheRunningTestHostIsNotStale() {
        XCTAssertFalse(InstalledBuild.currentWasReplaced)
    }
}
