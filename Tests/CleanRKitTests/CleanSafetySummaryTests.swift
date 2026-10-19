import XCTest
import Foundation
@testable import CleanRKit

final class CleanSafetySummaryTests: XCTestCase {

    private func item(_ path: String, size: UInt64) -> FileItem {
        FileItem(url: URL(filePath: path), name: "f", size: size, allocatedSize: size, isDirectory: false)
    }

    func testTrashItemsArePermanentEverythingElseRecoverable() {
        let cache = item("/Users/me/Library/Caches/a", size: 300)
        let trash = item("/Users/me/.Trash/b", size: 200)
        let results = [
            ScanResult(category: .userCaches, items: [cache]),
            ScanResult(category: .trashBins, items: [trash]),
        ]
        let summary = results.safetySummary(selectedItems: [cache.url, trash.url])
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.recoverableCount, 1)
        XCTAssertEqual(summary.permanentCount, 1)
        XCTAssertEqual(summary.recoverableBytes, 300)
        XCTAssertEqual(summary.permanentBytes, 200)
        XCTAssertEqual(summary.totalBytes, 500)
        XCTAssertTrue(summary.requiresExplicitConfirmation)
    }

    func testNoPermanentItemsNeedsNoExplicitConfirmation() {
        let cache = item("/Users/me/Library/Caches/a", size: 10)
        let results = [ScanResult(category: .userCaches, items: [cache])]
        let summary = results.safetySummary(selectedItems: [cache.url])
        XCTAssertEqual(summary.permanentCount, 0)
        XCTAssertFalse(summary.requiresExplicitConfirmation)
    }

    func testUnselectedAndDuplicateURLsAreCountedOnce() {
        let dup = item("/Users/me/Library/Caches/a", size: 100)
        let other = item("/Users/me/Library/Caches/b", size: 50)
        let results = [
            ScanResult(category: .userCaches, items: [dup, other]),
            ScanResult(category: .systemLogs, items: [dup]),
        ]
        let summary = results.safetySummary(selectedItems: [dup.url])
        XCTAssertEqual(summary.selectedCount, 1)
        XCTAssertEqual(summary.totalBytes, 100)
    }

    func testEmptySelectionIsAllZero() {
        let summary = [ScanResult]().safetySummary(selectedItems: [])
        XCTAssertEqual(summary.selectedCount, 0)
        XCTAssertEqual(summary.totalBytes, 0)
        XCTAssertFalse(summary.requiresExplicitConfirmation)
    }
}
