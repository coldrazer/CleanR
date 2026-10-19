import XCTest
@testable import CleanRKit

final class DiagnosticsReportTests: XCTestCase {

    func testRedactReplacesHomePathEverywhere() {
        let text = "cleaned /Users/alice/Library/Caches/x and /Users/alice/.Trash/y"
        let out = DiagnosticsReport.redact(text, home: "/Users/alice")
        XCTAssertEqual(out, "cleaned ~/Library/Caches/x and ~/.Trash/y")
        XCTAssertFalse(out.contains("alice"))
    }

    func testRedactWithEmptyHomeChangesNothing() {
        XCTAssertEqual(DiagnosticsReport.redact("/Users/alice/x", home: ""), "/Users/alice/x")
        XCTAssertEqual(DiagnosticsReport.redact("/Users/alice/x", home: "/"), "/Users/alice/x")
    }

    func testTailKeepsOnlyLastLines() {
        let log = (1...10).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(DiagnosticsReport.tail(log, maxLines: 3), "line 8\nline 9\nline 10")
        XCTAssertEqual(DiagnosticsReport.tail(log, maxLines: 50), log)
    }

    func testMakeIncludesFactsAndRedactsLog() {
        let report = DiagnosticsReport.make(
            appVersion: "0.1.0", osVersion: "macOS 15.0", architecture: "arm64",
            appearance: "Dark", language: "en", fullDiskAccess: false,
            logText: "removed /Users/bob/Library/Caches/z", home: "/Users/bob"
        )
        XCTAssertTrue(report.contains("CleanR 0.1.0"))
        XCTAssertTrue(report.contains("Full Disk Access: not granted"))
        XCTAssertTrue(report.contains("~/Library/Caches/z"))
        XCTAssertFalse(report.contains("bob"))
    }
}
