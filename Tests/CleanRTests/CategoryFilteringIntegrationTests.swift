import XCTest
import Foundation
@testable import CleanR
@testable import CleanRKit
import CleanRTestSupport

/// Integration tests for category filtering using synthetic file fixtures.
/// Verifies the system-side wrappers (in CleanR target) correctly use
/// the pure logic in CleanRKit.
final class CategoryFilteringIntegrationTests: XCTestCase {

    // MARK: - BrokenPreferences integration

    func testBrokenPreferences_findsCorruptPlist() throws {
        try TestFixtures.withTempDir { tmp in
            let valid = tmp.appending(path: "com.example.app.plist")
            let corrupt = tmp.appending(path: "com.example.broken.plist")
            try TestFixtures.writePlist(["x": "y"], to: valid)
            try TestFixtures.writeCorruptPlist(at: corrupt)

            let validItem = FileItem(url: valid, name: "com.example.app.plist",
                                     size: 100, allocatedSize: 100, isDirectory: false)
            let corruptItem = FileItem(url: corrupt, name: "com.example.broken.plist",
                                       size: 100, allocatedSize: 100, isDirectory: false)

            let cat = BrokenPreferencesCategory()
            let broken = cat.filterBroken(
                [validItem, corruptItem],
                loadData: { try? Data(contentsOf: $0) },
                appExistsForBundleID: { _ in true }
            )
            XCTAssertEqual(broken.count, 1)
            XCTAssertEqual(broken.first?.url, corrupt)
        }
    }

    func testBrokenPreferences_skipsAppleDomains() throws {
        try TestFixtures.withTempDir { tmp in
            let appleCorrupt = tmp.appending(path: "com.apple.somesystem.plist")
            try TestFixtures.writeCorruptPlist(at: appleCorrupt)

            let item = FileItem(url: appleCorrupt, name: "com.apple.somesystem.plist",
                                size: 100, allocatedSize: 100, isDirectory: false)
            let broken = BrokenPreferencesCategory().filterBroken(
                [item],
                loadData: { try? Data(contentsOf: $0) },
                appExistsForBundleID: { _ in false }
            )
            XCTAssertEqual(broken.count, 0, "Apple system domain plists should never be flagged")
        }
    }

    // MARK: - BrokenLoginItems integration

    func testBrokenLoginItems_findsMissingProgram() throws {
        try TestFixtures.withTempDir { tmp in
            let plistURL = tmp.appending(path: "com.deleted.app.plist")
            try TestFixtures.writePlist([
                "Label": "com.deleted.app",
                "Program": "/Applications/Deleted.app/Contents/MacOS/Deleted",
            ], to: plistURL)
            let item = FileItem(url: plistURL, name: "com.deleted.app.plist",
                                size: 100, allocatedSize: 100, isDirectory: false)

            let broken = BrokenLoginItemsCategory().filterBroken(
                [item],
                loadData: { try? Data(contentsOf: $0) },
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                appExistsForBundleID: { _ in false }
            )
            XCTAssertEqual(broken.count, 1)
        }
    }
}
