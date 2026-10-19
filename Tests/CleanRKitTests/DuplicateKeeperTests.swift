import XCTest
import Foundation
@testable import CleanRKit

/// Covers the "keep exactly one safe original per set" behavior: which copy is
/// chosen as the keeper, that it's never offered for deletion, and how sets are
/// turned into display groups. This is the data-safety core of the Duplicates
/// feature — the original must survive no matter what the user selects.
final class DuplicateKeeperTests: XCTestCase {

    private func file(_ path: String, size: UInt64 = 100, created: Date? = nil) -> FileItem {
        FileItem(
            url: URL(filePath: path),
            name: (path as NSString).lastPathComponent,
            size: size, allocatedSize: size,
            isDirectory: false, creationDate: created
        )
    }

    // MARK: - isLikelyBackupCopy

    func testIsLikelyBackupCopy() {
        XCTAssertFalse(DuplicateDetection.isLikelyBackupCopy(URL(filePath: "/Users/me/Documents/report.pdf")))
        XCTAssertTrue(DuplicateDetection.isLikelyBackupCopy(URL(filePath: "/Users/me/Backups/report.pdf")))
        XCTAssertTrue(DuplicateDetection.isLikelyBackupCopy(URL(filePath: "/Users/me/Documents/report copy.pdf")))
        XCTAssertTrue(DuplicateDetection.isLikelyBackupCopy(URL(filePath: "/Users/me/Documents/report (1).pdf")))
        XCTAssertTrue(DuplicateDetection.isLikelyBackupCopy(URL(filePath: "/Users/me/Documents/report 2.pdf")))
        XCTAssertTrue(DuplicateDetection.isLikelyBackupCopy(URL(filePath: "/Users/me/.Trash/report.pdf")))
    }

    // MARK: - chooseOriginal

    func testChooseOriginalPrefersNonBackup() {
        let group = [
            file("/Users/me/Documents/Backup/report.pdf"),
            file("/Users/me/Documents/report.pdf"),
        ]
        XCTAssertEqual(DuplicateDetection.chooseOriginal(group).url.path,
                       "/Users/me/Documents/report.pdf")
    }

    func testChooseOriginalPrefersShallowerPath() {
        let group = [
            file("/Users/me/Pictures/2021/old/a.jpg"),
            file("/Users/me/a.jpg"),
        ]
        XCTAssertEqual(DuplicateDetection.chooseOriginal(group).url.path, "/Users/me/a.jpg")
    }

    func testChooseOriginalPrefersOlderOverLexicographic() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        // Same depth, both non-backup. "y" is lexicographically LATER than "x"
        // but older — age must win so the keeper is the original, not a later copy.
        let group = [
            file("/Users/me/x.jpg", created: newer),
            file("/Users/me/y.jpg", created: older),
        ]
        XCTAssertEqual(DuplicateDetection.chooseOriginal(group).url.path, "/Users/me/y.jpg")
    }

    func testChooseOriginalDeterministicTiebreak() {
        // Everything equal (no dates, same depth, no backup markers) → the
        // lexicographically smallest path wins, so results are stable.
        let group = [
            file("/Users/me/b.jpg"),
            file("/Users/me/a.jpg"),
            file("/Users/me/c.jpg"),
        ]
        XCTAssertEqual(DuplicateDetection.chooseOriginal(group).url.path, "/Users/me/a.jpg")
    }

    // MARK: - displayGroups

    func testDisplayGroupsKeepsOneAndExposesRest() {
        let group = [
            file("/Users/me/a.jpg"),
            file("/Users/me/copies/a.jpg"),
            file("/Users/me/copies2/a.jpg"),
        ]
        let display = DuplicateDetection.displayGroups([group])
        XCTAssertEqual(display.count, 1)
        XCTAssertEqual(display[0].original.url.path, "/Users/me/a.jpg")
        XCTAssertEqual(display[0].duplicates.count, 2)
        XCTAssertEqual(display[0].copyCount, 3)
        XCTAssertEqual(display[0].wastedSpace, 200) // size 100 × 2 extras
    }

    func testDisplayGroupOriginalNeverInDuplicates() {
        let group = [file("/Users/me/a.jpg"), file("/Users/me/b/a.jpg")]
        let display = DuplicateDetection.displayGroups([group])
        let dupURLs = Set(display[0].duplicates.map(\.url))
        XCTAssertFalse(dupURLs.contains(display[0].original.url),
                       "the kept original must never appear among the removable copies")
    }

    func testDisplayGroupsSortedByWastedSpaceDescending() {
        let small = [file("/s/a", size: 10), file("/s/b/a", size: 10)]            // wasted 10
        let big = [file("/b/a", size: 100), file("/b/b/a", size: 100), file("/b/c/a", size: 100)] // wasted 200
        let display = DuplicateDetection.displayGroups([small, big])
        XCTAssertEqual(display.map(\.wastedSpace), [200, 10])
    }

    func testDisplayGroupsDropsSingletonsAndEmpty() {
        XCTAssertTrue(DuplicateDetection.displayGroups([]).isEmpty)
        XCTAssertTrue(DuplicateDetection.displayGroups([[file("/lonely.jpg")]]).isEmpty)
    }

    // MARK: - extractDeletableDuplicates safety invariant

    func testExtractDeletableNeverIncludesChosenOriginal() {
        let group = [
            file("/Users/me/Documents/report.pdf"),         // chosen original (non-backup, shallow)
            file("/Users/me/Documents/Backup/report.pdf"),
            file("/Users/me/Desktop/old/report.pdf"),
        ]
        let deletable = DuplicateDetection.extractDeletableDuplicates([group])
        let original = DuplicateDetection.chooseOriginal(group)
        XCTAssertEqual(deletable.count, 2)
        XCTAssertFalse(deletable.map(\.url).contains(original.url),
                       "the original must never be in the deletable set")
    }
}
