import XCTest
@testable import CleanR
@testable import CleanRKit
import CleanRTestSupport

/// End-to-end coverage for SystemJunk categories that EndToEndScenarioTests
/// doesn't already exercise. Each test plants fixtures the scanner actually
/// sees (some categories use non-recursive scans, so we plant files
/// directly in the target dir rather than under a subdir), then runs the
/// real SystemJunkModule.scan() and asserts disposition.
///
/// Documented gaps (not feasible via plain XCTest):
///  - LanguageFiles: scans /Applications recursively; planting fake .app
///    bundles in /Applications during tests would pollute the user's apps
///    list. Covered indirectly by SimpleCategories tests.
///  - XcodeJunk: requires Xcode-shaped DerivedData/Archives/etc dirs
///    that may not exist on every machine; covered by SimpleCategories
///    tests.
///  - DocumentVersions: target path (~/.DocumentRevisions-V100) is
///    SIP-protected; can't plant fixtures there.
final class RemainingSystemJunkE2ETests: XCTestCase {

    /// Exact-path artifacts created in shared user dirs (~/Library/Preferences,
    /// LaunchAgents, etc.). Cleaned up by tearDown regardless of test outcome.
    private var stragglerFiles: [URL] = []
    /// Subdir-shaped artifacts under non-shared paths.
    private var stragglerDirs: [URL] = []

    override func tearDownWithError() throws {
        for url in stragglerFiles { try? FileManager.default.removeItem(at: url) }
        for url in stragglerDirs  { try? FileManager.default.removeItem(at: url) }
        stragglerFiles.removeAll()
        stragglerDirs.removeAll()
    }

    @discardableResult
    private func plant(at url: URL, bytes: Data, daysOld: Double? = nil) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: url)
        if let daysOld {
            let mod = Date().addingTimeInterval(-daysOld * 86_400)
            try FileManager.default.setAttributes(
                [.modificationDate: mod],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }
        return url
    }

    private func itemsForCategory(_ cat: ScanCategory, scan: [ScanResult]) -> [FileItem] {
        scan.first(where: { $0.category == cat })?.items ?? []
    }

    /// URL membership check that normalizes for the /var → /private/var
    /// symlink (Foundation's directory enumerator resolves it; our
    /// planted URLs don't).
    private func contains(_ urls: Set<URL>, _ url: URL) -> Bool {
        let target = url.standardizedFileURL.path(percentEncoded: false)
        return urls.contains { $0.standardizedFileURL.path(percentEncoded: false) == target }
    }

    // MARK: - BrokenPreferences

    func testBrokenPreferences_flagsCorruptPlistDirectlyInPreferencesDir() async throws {
        // Plant a uniquely-named plist file DIRECTLY in ~/Library/Preferences/
        // — the category scans non-recursively, so files in subdirs are
        // invisible. Cleanup by exact path on tearDown.
        let id = UUID().uuidString
        let corrupt = MCConstants.userPreferences
            .appending(path: "com.cleanr.e2e-bad-\(id).plist")
        let valid = MCConstants.userPreferences
            .appending(path: "com.cleanr.e2e-good-\(id).plist")
        stragglerFiles.append(corrupt)
        stragglerFiles.append(valid)

        try plant(at: corrupt, bytes: Data([0xFF, 0xFE, 0xFD, 0x00, 0x01]))
        let validData = try PropertyListSerialization.data(
            fromPropertyList: ["LastVersion": "1.0"] as [String: Any],
            format: .xml, options: 0
        )
        try plant(at: valid, bytes: validData)

        let scan = await SystemJunkModule().scan()
        let urls = Set(itemsForCategory(.brokenPreferences, scan: scan).map(\.url))

        XCTAssertTrue(contains(urls, corrupt), "corrupt plist must be flagged")
        XCTAssertFalse(contains(urls, valid),
                       "valid plist must NOT be flagged — even from a third-party app")
    }

    // MARK: - BrokenLoginItems
    //
    // Intentionally NOT tested end-to-end here. Planting a plist in
    // ~/Library/LaunchAgents/ triggers macOS's Background Items watcher
    // before the test's tearDown can remove the file — the user gets a
    // "<program> can run in the background" system notification every
    // time the suite runs. Tests that pollute the developer's
    // Notification Center aren't worth the coverage.
    //
    // The filter logic — "agent plist with a non-existent ProgramArguments
    // path is flagged broken" — is covered by:
    //   Tests/CleanRTests/CategoryFilteringIntegrationTests.swift
    //     testBrokenLoginItems_findsMissingProgram
    // which calls BrokenLoginItemsCategory.filterBroken directly against
    // synthetic FileItems, never touching ~/Library/LaunchAgents/.

    // MARK: - iOSBackups (TCC-skipped on machines that block writes there)

    func testIOSBackups_flagsOldBackupsOnly() async throws {
        // Sometimes ~/Library/Application Support/MobileSync/Backup is
        // blocked at the FS level for unsigned tools. Detect by trying
        // a write first; skip the test if we can't.
        let probeDir = MCConstants.mobileBackups
            .appending(path: "CleanRE2E-probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(
                at: probeDir, withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: probeDir)
        } catch {
            throw XCTSkip("MobileSync/Backup not writable in this environment (TCC).")
        }

        let dirName = "abcdef0123456789-\(UUID().uuidString)"
        let backupDir = MCConstants.mobileBackups.appending(path: dirName)
        stragglerDirs.append(backupDir)

        let manifest = backupDir.appending(path: "Manifest.db")
        try plant(at: manifest, bytes: Data(count: 4096), daysOld: 60)
        // Backup dir mtime drives the category check (scan is non-recursive
        // depth-1, surfaces directories whose own mtime is old).
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60 * 86_400)],
            ofItemAtPath: backupDir.path(percentEncoded: false)
        )

        let scan = await SystemJunkModule().scan()
        let urls = Set(itemsForCategory(.iosDeviceBackups, scan: scan).map(\.url))
        XCTAssertTrue(contains(urls, backupDir),
                      "60-day-old backup dir must be flagged (minAge = 30d)")
    }

    // MARK: - OldUpdates

    func testOldUpdates_flagsOldInstallersOnly() async throws {
        let dir = MCConstants.userAppSupport
            .appending(path: "CleanRE2E-old-updates-\(UUID().uuidString)")
        stragglerDirs.append(dir)

        let oldPkg = try plant(
            at: dir.appending(path: "Updates/MyApp-old.pkg"),
            bytes: Data(count: 1024), daysOld: 14
        )
        let newPkg = try plant(
            at: dir.appending(path: "Updates/MyApp-new.pkg"),
            bytes: Data(count: 1024), daysOld: 1
        )
        let nonPkg = try plant(
            at: dir.appending(path: "Updates/notes.txt"),
            bytes: Data(count: 1024), daysOld: 14
        )

        let scan = await SystemJunkModule().scan()
        let urls = Set(itemsForCategory(.oldUpdates, scan: scan).map(\.url))

        XCTAssertTrue(contains(urls, oldPkg), "14-day-old .pkg must be flagged")
        XCTAssertFalse(contains(urls, newPkg), "1-day-old .pkg must NOT be flagged")
        XCTAssertFalse(contains(urls, nonPkg), ".txt file must NOT match .pkg/.mpkg")
    }

    // MARK: - IncompleteDownloads (temp-dir branch)

    func testIncompleteDownloads_flagsAgedTempFiles() async throws {
        // Plant directly in the temp dir root — depth-2 max applies from
        // the temp dir; a file at depth-1 is in range.
        let id = UUID().uuidString
        let aged = FileManager.default.temporaryDirectory
            .appending(path: "cleanr-e2e-aged-\(id).tmp")
        let fresh = FileManager.default.temporaryDirectory
            .appending(path: "cleanr-e2e-fresh-\(id).tmp")
        stragglerFiles.append(aged)
        stragglerFiles.append(fresh)

        try plant(at: aged, bytes: Data(count: 256), daysOld: 2)
        try plant(at: fresh, bytes: Data(count: 256), daysOld: 0)

        let scan = await SystemJunkModule().scan()
        let urls = Set(itemsForCategory(.incompleteDownloads, scan: scan).map(\.url))
        XCTAssertTrue(contains(urls, aged),
                      "2-day-old file in temp dir must be flagged (minAge = 1d)")
        XCTAssertFalse(contains(urls, fresh),
                       "0-day-old file must NOT be flagged")
    }
}
