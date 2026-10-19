import XCTest
import Foundation
@testable import CleanR

/// Regression test for the "clean reports success but doesn't actually
/// delete anything" bug from May 2026.
///
/// Cause: every view's `clean()` method was calling
/// `appState.cleaningEngine.clean(items: items, mode: .dryRun)` — leftover
/// development scaffolding that returned counts as if files were deleted
/// but never touched the filesystem.
///
/// This test scans every view file in the CleanR target and fails the
/// build if any of them passes `mode: .dryRun` to `cleaningEngine.clean()`.
/// `.dryRun` is fine for tests and previews — never for production view
/// actions that the user expects to actually clean their disk.
final class CleanIsNotDryRunRegressionTests: XCTestCase {

    func testNoViewUsesDryRunModeForUserClean() throws {
        let viewsDir = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/CleanR/Views")
        let viewModelsDir = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/CleanR/ViewModels")

        var offenders: [String] = []
        for dir in [viewsDir, viewModelsDir] {
            guard let enumerator = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

                // Find any call to a cleaningEngine.clean(...) that uses .dryRun.
                // This catches `cleaningEngine.clean(items: x, mode: .dryRun)`,
                // `engine.clean(items: x, mode: .dryRun)`, multiline, etc.
                let pattern = #"clean\(items:[^)]*mode:\s*\.dryRun"#
                if contents.range(of: pattern, options: .regularExpression) != nil {
                    offenders.append(url.lastPathComponent)
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "These views/view-models pass `.dryRun` to CleaningEngine — they'll report success but never actually delete files: \(offenders)"
        )
    }
}
