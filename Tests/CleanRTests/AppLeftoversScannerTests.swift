import XCTest
@testable import CleanR
import CleanRKit

final class AppLeftoversScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "Leftovers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEntry(_ name: String, bytes: Int) throws {
        let dir = root.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: dir.appending(path: "data.bin"))
    }

    func testReturnsOnlyOrphanEntries() throws {
        try makeEntry("com.deleted.app", bytes: 4096)        // owner not installed
        try makeEntry("com.installed.app", bytes: 4096)      // owner installed
        try makeEntry("com.apple.Safari", bytes: 4096)       // system, never flagged
        try makeEntry("com.installed.app.helper", bytes: 4096) // helper of installed

        let items = AppLeftoversScanner.scan(
            roots: [root],
            installedBundleIDs: ["com.installed.app"]
        )

        XCTAssertEqual(items.map(\.name), ["com.deleted.app"],
                       "only the deleted app's leftover should be flagged")
        XCTAssertGreaterThan(items.first?.size ?? 0, 0)
    }

    func testEmptyInstalledSetFlagsNothing() throws {
        // An empty installed set means enumeration failed; never treat the
        // whole Mac as orphaned.
        try makeEntry("com.deleted.app", bytes: 4096)
        let items = AppLeftoversScanner.scan(roots: [root], installedBundleIDs: [])
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - #151 nested install roots

    /// Minimal .app bundle so macOS treats the directory as a package.
    private func makeApp(at appsRoot: URL, _ relativePath: String, bundleID: String) throws {
        let appURL = appsRoot.appending(path: relativePath)
        let contents = appURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let name = appURL.deletingPathExtension().lastPathComponent
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>\(bundleID)</string>
          <key>CFBundleName</key><string>\(name)</string>
        </dict></plist>
        """
        try plist.write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
    }

    /// Regression for #151: leftovers must see the same nested apps the
    /// Uninstaller already finds (#120 / #123), or live Adobe/PostgreSQL
    /// caches get listed as orphans.
    func testInstalledBundleIDsIncludesNestedApps() throws {
        let appsRoot = FileManager.default.temporaryDirectory
            .appending(path: "LeftoversApps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appsRoot) }

        try makeApp(at: appsRoot, "Root.app", bundleID: "com.test.Root")
        try makeApp(at: appsRoot, "Adobe Photoshop 2026/Adobe Photoshop 2026.app",
                    bundleID: "com.adobe.Photoshop")
        try makeApp(at: appsRoot, "Adobe/CC/Lightroom.app",
                    bundleID: "com.adobe.Lightroom")
        // Helper buried inside a bundle must not become its own "installed" id.
        try makeApp(at: appsRoot, "Root.app/Contents/Library/LoginItems/Helper.app",
                    bundleID: "com.test.Helper")

        let ids = AppLeftoversScanner.installedBundleIDs(in: [appsRoot])

        XCTAssertEqual(ids, Set([
            "com.test.root",
            "com.adobe.photoshop",
            "com.adobe.lightroom",
        ]))
        XCTAssertFalse(ids.contains("com.test.helper"),
                       "must not treat in-bundle helpers as installed apps")
    }

    func testNestedInstalledAppIsNotFlaggedAsLeftover() throws {
        let appsRoot = FileManager.default.temporaryDirectory
            .appending(path: "LeftoversApps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appsRoot) }

        try makeApp(at: appsRoot, "Adobe Photoshop 2026/Adobe Photoshop 2026.app",
                    bundleID: "com.adobe.Photoshop")
        try makeEntry("com.adobe.Photoshop", bytes: 4096)
        try makeEntry("com.deleted.app", bytes: 2048)

        let installed = AppLeftoversScanner.installedBundleIDs(in: [appsRoot])
        let items = AppLeftoversScanner.scan(roots: [root], installedBundleIDs: installed)

        XCTAssertEqual(items.map(\.name), ["com.deleted.app"],
                       "Photoshop cache must not be an orphan while the nested app is installed")
    }
}
