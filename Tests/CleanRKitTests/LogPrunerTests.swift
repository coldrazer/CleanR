import XCTest
@testable import CleanRKit

final class LogPrunerTests: XCTestCase {

    /// Builds a log line in the format CleaningEngine emits.
    private func line(_ daysAgo: Double, _ body: String) -> String {
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        return "\(ISO8601DateFormatter().string(from: date)) \(body)"
    }

    private var cutoff: Date {
        Date().addingTimeInterval(-30 * 86_400)
    }

    // MARK: - Spec

    /// SPEC: lines whose ISO8601 timestamp is older than the cutoff are
    /// dropped; lines newer are kept; ordering is preserved.
    func testPruning_dropsLinesOlderThanCutoff_keepsNewerOnes() {
        let log = """
        \(line(45, "[REMOVED] /a"))
        \(line(31, "[REMOVED] /b"))
        \(line(29, "[REMOVED] /c"))
        \(line(0.1, "[REMOVED] /d"))
        """
        let pruned = LogPruner.pruning(log, olderThan: cutoff)
        XCTAssertFalse(pruned.contains("/a"), "45d old line must be dropped")
        XCTAssertFalse(pruned.contains("/b"), "31d old line must be dropped")
        XCTAssertTrue(pruned.contains("/c"), "29d old line must be kept")
        XCTAssertTrue(pruned.contains("/d"), "fresh line must be kept")
    }

    /// SPEC: lines without a parseable ISO8601 timestamp prefix are
    /// kept — defensive against future log-format changes and against
    /// edge cases like blank lines in the middle of the file. We'd
    /// rather over-keep than silently lose user data.
    func testPruning_keepsLinesWithoutValidTimestamp() {
        let log = """
        \(line(60, "[REMOVED] /old"))
        a random line without a timestamp
        2024 — not a valid ISO timestamp
        \(line(1, "[REMOVED] /fresh"))
        """
        let pruned = LogPruner.pruning(log, olderThan: cutoff)
        XCTAssertFalse(pruned.contains("/old"), "old line dropped")
        XCTAssertTrue(pruned.contains("a random line without a timestamp"),
                      "unparseable lines must be kept")
        XCTAssertTrue(pruned.contains("2024 — not a valid ISO timestamp"),
                      "lines whose prefix isn't valid ISO8601 must be kept")
        XCTAssertTrue(pruned.contains("/fresh"))
    }

    /// SPEC: pruning an empty log returns empty (no-op, no crash).
    func testPruning_emptyInput_returnsEmpty() {
        XCTAssertEqual(LogPruner.pruning("", olderThan: cutoff), "")
    }

    /// SPEC: when every line is fresher than the cutoff, the input is
    /// returned unchanged (preserving trailing newlines, whitespace, etc).
    func testPruning_noOldLines_isIdentity() {
        let log = """
        \(line(1, "[REMOVED] /a"))
        \(line(2, "[REMOVED] /b"))
        \(line(3, "[REMOVED] /c"))
        """
        XCTAssertEqual(LogPruner.pruning(log, olderThan: cutoff), log)
    }

    /// SPEC: ordering of the kept lines matches their order in the input.
    func testPruning_preservesOrder() {
        let log = """
        \(line(5, "[REMOVED] /first"))
        \(line(45, "[REMOVED] /old-middle"))
        \(line(3, "[REMOVED] /second"))
        """
        let pruned = LogPruner.pruning(log, olderThan: cutoff)
        let firstIdx = pruned.range(of: "/first")?.lowerBound
        let secondIdx = pruned.range(of: "/second")?.lowerBound
        XCTAssertNotNil(firstIdx)
        XCTAssertNotNil(secondIdx)
        if let f = firstIdx, let s = secondIdx {
            XCTAssertLessThan(f, s, "order preserved across pruned middle")
        }
    }
}
