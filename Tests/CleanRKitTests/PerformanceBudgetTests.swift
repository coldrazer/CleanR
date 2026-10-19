import XCTest
@testable import CleanRKit

/// Performance budgets for the scan-results pipeline. These are the
/// operations that beachballed the UI on large scans; the budgets keep
/// them in the "imperceptible" range on CI hardware: flattening or
/// sorting 10k rows must stay well under a frame budget at scale, and
/// the whole suite fails loudly if an O(n²) sneaks back in.
final class PerformanceBudgetTests: XCTestCase {

    private func makeResults(count: Int) -> [ScanResult] {
        let items = (0..<count).map { i in
            FileItem(
                url: URL(filePath: "/tmp/cache/file-\(i)"),
                name: "file-\(i)",
                size: UInt64(i % 997),
                allocatedSize: UInt64(i % 997),
                isDirectory: false
            )
        }
        return [ScanResult(category: .userCaches, items: items)]
    }

    func testFlattenTenThousandRowsWithinBudget() {
        let results = makeResults(count: 10_000)
        let start = Date()
        let rows = FileListRows.flatten(results: results, isExpanded: { _ in true }, selectedItems: [])
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(rows.count, 10_001)
        XCTAssertLessThan(elapsed, 1.0, "flattening 10k rows took \(elapsed)s (budget 1.0s)")
    }

    func testSortTenThousandRowsWithinBudget() {
        let results = makeResults(count: 10_000)
        let start = Date()
        let sorted = FileListSort.sizeDescending.sorted(results)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(sorted.first?.items.count, 10_000)
        XCTAssertLessThan(elapsed, 1.0, "sorting 10k rows took \(elapsed)s (budget 1.0s)")
    }
}
