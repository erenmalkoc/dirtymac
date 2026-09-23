import XCTest
@testable import dirtymac

final class WhatsNewTests: XCTestCase {
    private let catalog = [
        ReleaseNote(version: "1.4.0", items: []),
        ReleaseNote(version: "1.3.0", items: []),
        ReleaseNote(version: "1.2.0", items: []),
    ]

    private func versions(_ notes: [ReleaseNote]) -> [String] { notes.map(\.version) }

    func testCompareIsNumericNotLexical() {
        XCTAssertEqual(WhatsNew.compare("1.10.0", "1.9.2"), .orderedDescending)
        XCTAssertEqual(WhatsNew.compare("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(WhatsNew.compare("1.1.2", "1.2.0"), .orderedAscending)
        XCTAssertEqual(WhatsNew.compare("2.0.0", "1.99.99"), .orderedDescending)
    }

    func testUserWhoPredatesTheWindowSeesOnlyTheRunningVersion() {
        let notes = WhatsNew.notesToShow(current: "1.3.0", lastSeen: nil, catalog: catalog)
        XCTAssertEqual(versions(notes), ["1.3.0"])
    }

    func testUserWhoPredatesTheWindowOnAReleaseWithoutNotesSeesNothing() {
        XCTAssertTrue(WhatsNew.notesToShow(current: "1.1.2", lastSeen: nil, catalog: catalog).isEmpty)
    }

    func testSkippedReleasesAreIncludedNewestFirst() {
        let notes = WhatsNew.notesToShow(current: "1.4.0", lastSeen: "1.1.2", catalog: catalog)
        XCTAssertEqual(versions(notes), ["1.4.0", "1.3.0", "1.2.0"])
    }

    func testAlreadySeenVersionShowsNothing() {
        XCTAssertTrue(WhatsNew.notesToShow(current: "1.3.0", lastSeen: "1.3.0", catalog: catalog).isEmpty)
    }

    func testPatchReleaseAfterSeenMinorShowsNothing() {
        XCTAssertTrue(WhatsNew.notesToShow(current: "1.3.1", lastSeen: "1.3.0", catalog: catalog).isEmpty)
    }

    func testNotesNewerThanTheRunningBuildAreNeverShown() {
        let notes = WhatsNew.notesToShow(current: "1.3.0", lastSeen: "1.1.0", catalog: catalog)
        XCTAssertEqual(versions(notes), ["1.3.0", "1.2.0"])
    }

    func testDowngradeShowsNothing() {
        XCTAssertTrue(WhatsNew.notesToShow(current: "1.2.0", lastSeen: "1.4.0", catalog: catalog).isEmpty)
    }

    func testAllNotesStopAtTheRunningVersion() {
        XCTAssertEqual(versions(WhatsNew.allNotes(current: "1.3.0", catalog: catalog)), ["1.3.0", "1.2.0"])
    }

    func testShippedCatalogIsNewestFirstWithoutDuplicates() {
        let shipped = versions(WhatsNew.catalog)
        XCTAssertEqual(shipped, shipped.sorted { WhatsNew.compare($0, $1) == .orderedDescending })
        XCTAssertEqual(Set(shipped).count, shipped.count)
        XCTAssertFalse(WhatsNew.catalog.contains { $0.items.isEmpty })
    }
}
