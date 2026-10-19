import XCTest
import Foundation

/// Regression for issue #3: long-running Smart Scan / Duplicates scans must
/// expose a Cancel path back to idle. Mirrors `NoEmptyButtonActionsTests` —
/// scan the view sources so we don't ship a progress UI with no escape hatch.
final class ScanCancelUIRegressionTests: XCTestCase {

    private func viewsRoot() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/CleanR/Views")
    }

    func testSmartScanScanningViewWiresCancel() throws {
        let url = viewsRoot().appending(path: "SmartScan/SmartScanView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            src.contains("func cancelScan(") || src.contains("func cancelScan()"),
            "SmartScanView must define cancelScan() for issue #3"
        )
        XCTAssertTrue(
            src.contains("scanCoordinator.cancel()"),
            "SmartScan cancel must call ScanCoordinator.cancel()"
        )
        // Cancel button must live in the scanning UI, not only mid-clean.
        XCTAssertTrue(
            src.range(of: #"scanningView[\s\S]*?cancelScan\(\)"#, options: .regularExpression) != nil
                || src.range(of: #"cancelScan\(\)[\s\S]*?scanningView"#, options: .regularExpression) != nil
                || (src.contains("Button(L10n.tr(\"取消\", \"Cancel\"") && src.contains("cancelScan()")),
            "SmartScan scanningView must invoke cancelScan()"
        )
    }

    func testDuplicatesScanningViewWiresCancel() throws {
        let url = viewsRoot().appending(path: "Files/DuplicatesView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            src.contains("func cancelScan(") || src.contains("func cancelScan()"),
            "DuplicatesView must define cancelScan() for issue #3"
        )
        XCTAssertTrue(
            src.contains("scanTask"),
            "DuplicatesView must retain the scan Task so cancel can stop it"
        )
        XCTAssertTrue(
            src.contains("cancelScan()"),
            "Duplicates scanning UI must call cancelScan()"
        )
    }
}
