import XCTest
import Foundation
import GRDB
@testable import CleanR
@testable import CleanRKit
import CleanRTestSupport

/// Integration tests for the GRDB-backed scan cache.
final class DatabaseTests: XCTestCase {

    /// Build an isolated database for each test.
    private func makeDB() throws -> AppDatabase {
        try AppDatabase.open(at: tempDatabaseURL())
    }

    private func tempDatabaseURL(_ name: String = "test.sqlite") -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "cleanr-db-test-\(UUID().uuidString)")
            .appending(path: name)
    }

    /// `open(at:)` replaced a `static let shared` that ran `try!` twice: a
    /// corrupt cache file used to abort the app at launch. It must throw
    /// instead, and it must survive being called again on a good file.
    func testOpenSucceedsAndReopensExistingFile() throws {
        let url = tempDatabaseURL()
        let first = try AppDatabase.open(at: url)
        let scanID = try first.createScan(rootPath: "/tmp/test", moduleID: "system_junk")
        XCTAssertGreaterThan(scanID, 0)

        let second = try AppDatabase.open(at: url)
        let rows = try second.getCachedFiles(scanID: scanID)
        XCTAssertTrue(rows.isEmpty)
    }

    func testOpenThrowsOnACorruptDatabaseFile() throws {
        let url = tempDatabaseURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("this is not a sqlite file, it is a poem about not being sqlite".utf8)
            .write(to: url)
        do {
            _ = try AppDatabase.open(at: url)
            XCTFail("Opening a corrupt database must throw, not crash the process")
        } catch {
            // Any GRDB/SQLite error is acceptable; the contract is "no trap".
        }
    }

    func testCreateScanAndCompleteRoundtrip() throws {
        let db = try makeDB()
        let id = try db.createScan(rootPath: "/tmp/test", moduleID: "system_junk")
        XCTAssertGreaterThan(id, 0)

        try db.completeScan(id: id, totalSize: 1234, fileCount: 5, fsEventID: 100)

        let last = try db.lastScan(moduleID: "system_junk")
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.id, id)
        XCTAssertEqual(last?.fsEventID, 100)
    }

    func testNoLastScanForUnknownModule() throws {
        let db = try makeDB()
        XCTAssertNil(try db.lastScan(moduleID: "never_registered"))
    }

    /// An interrupted scan has no `completedAt` and therefore no trustworthy
    /// `fsEventID` to resume from; handing one back would make the next run skip
    /// files that changed while CleanR wasn't looking.
    func testLastScanIgnoresUncompletedScansOfTheSameModule() throws {
        let db = try makeDB()
        let finished = try db.createScan(rootPath: "/tmp/test", moduleID: "system_junk")
        try db.completeScan(id: finished, totalSize: 1234, fileCount: 5, fsEventID: 100)

        // Started later, never completed - must not be picked up.
        _ = try db.createScan(rootPath: "/tmp/test", moduleID: "system_junk")

        let last = try db.lastScan(moduleID: "system_junk")
        XCTAssertEqual(last?.id, finished)
        XCTAssertEqual(last?.fsEventID, 100)
    }

    func testCacheAndRetrieveFiles() throws {
        let db = try makeDB()
        let scanID = try db.createScan(rootPath: "/tmp/test", moduleID: "system_junk")

        let records = [
            CachedFileRecord(
                path: "/tmp/a.cache", name: "a.cache", parentPath: "/tmp",
                size: 100, allocatedSize: 100,
                isDirectory: false, category: "user_caches",
                inode: 1, deviceID: 1
            ),
            CachedFileRecord(
                path: "/tmp/b.log", name: "b.log", parentPath: "/tmp",
                size: 200, allocatedSize: 200,
                isDirectory: false, category: "user_logs",
                inode: 2, deviceID: 1
            ),
        ]
        try db.cacheFiles(records, scanID: scanID)

        let all = try db.getCachedFiles(scanID: scanID)
        XCTAssertEqual(all.count, 2)

        let userCaches = try db.getCachedFilesByCategory(scanID: scanID, category: "user_caches")
        XCTAssertEqual(userCaches.count, 1)
        XCTAssertEqual(userCaches.first?.path, "/tmp/a.cache")
    }

    func testInvalidatePaths() throws {
        let db = try makeDB()
        let scanID = try db.createScan(rootPath: "/tmp/test", moduleID: "system_junk")
        try db.cacheFiles([
            CachedFileRecord(path: "/tmp/a/x", name: "x", parentPath: "/tmp/a",
                             size: 1, allocatedSize: 1, isDirectory: false),
            CachedFileRecord(path: "/tmp/a/y", name: "y", parentPath: "/tmp/a",
                             size: 1, allocatedSize: 1, isDirectory: false),
            CachedFileRecord(path: "/tmp/b/x", name: "x", parentPath: "/tmp/b",
                             size: 1, allocatedSize: 1, isDirectory: false),
        ], scanID: scanID)

        try db.invalidatePaths(["/tmp/a"], scanID: scanID)
        let remaining = try db.getCachedFiles(scanID: scanID)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.path, "/tmp/b/x")
    }

    /// A directory name is arbitrary user data, and `%` / `_` are LIKE
    /// wildcards. Without escaping, invalidating `/tmp/a%b` also deleted every
    /// sibling that merely matched the pattern.
    func testInvalidatePathsTreatsWildcardsLiterally() throws {
        let db = try makeDB()
        let scanID = try db.createScan(rootPath: "/tmp/test", moduleID: "system_junk")
        try db.cacheFiles([
            CachedFileRecord(path: "/tmp/a%b/keep", name: "keep", parentPath: "/tmp/a%b",
                             size: 1, allocatedSize: 1, isDirectory: false),
            CachedFileRecord(path: "/tmp/aXb/gone", name: "gone", parentPath: "/tmp/aXb",
                             size: 1, allocatedSize: 1, isDirectory: false),
            CachedFileRecord(path: "/tmp/a%b/x", name: "x", parentPath: "/tmp/a%b",
                             size: 1, allocatedSize: 1, isDirectory: false),
        ], scanID: scanID)

        try db.invalidatePaths(["/tmp/a%b"], scanID: scanID)
        let remaining = try db.getCachedFiles(scanID: scanID)
        XCTAssertEqual(remaining.map(\.path), ["/tmp/aXb/gone"])
    }

    func testInvalidatePathsEscapesUnderscore() throws {
        let db = try makeDB()
        let scanID = try db.createScan(rootPath: "/tmp/test", moduleID: "system_junk")
        try db.cacheFiles([
            CachedFileRecord(path: "/tmp/my_cache/x", name: "x", parentPath: "/tmp/my_cache",
                             size: 1, allocatedSize: 1, isDirectory: false),
            CachedFileRecord(path: "/tmp/myXcache/y", name: "y", parentPath: "/tmp/myXcache",
                             size: 1, allocatedSize: 1, isDirectory: false),
        ], scanID: scanID)

        try db.invalidatePaths(["/tmp/my_cache"], scanID: scanID)
        let remaining = try db.getCachedFiles(scanID: scanID)
        XCTAssertEqual(remaining.map(\.path), ["/tmp/myXcache/y"])
    }

    func testEscapeLikePattern() {
        XCTAssertEqual(AppDatabase.escapeLikePattern("/tmp/a%b"), #"/tmp/a\%b"#)
        XCTAssertEqual(AppDatabase.escapeLikePattern("/tmp/a_b"), #"/tmp/a\_b"#)
        XCTAssertEqual(AppDatabase.escapeLikePattern(#"/tmp/a\b"#), #"/tmp/a\\b"#)
        XCTAssertEqual(AppDatabase.escapeLikePattern("/tmp/plain"), "/tmp/plain")
    }

    func testCacheAppUpsertsByBundleID() throws {
        let db = try makeDB()
        let app = AppInfo(
            bundleIdentifier: "com.test.app",
            name: "Test", path: URL(filePath: "/Applications/Test.app"),
            version: "1.0", size: 1024
        )
        try db.cacheApp(app)

        // Same bundle ID, different version - should replace, not duplicate.
        let updatedApp = AppInfo(
            bundleIdentifier: "com.test.app",
            name: "Test", path: URL(filePath: "/Applications/Test.app"),
            version: "2.0", size: 2048
        )
        try db.cacheApp(updatedApp)
        // Test passes if no crash + no UNIQUE constraint violation
    }

    func testClearOldScansKeepsRecent() throws {
        let db = try makeDB()
        for i in 0..<10 {
            let id = try db.createScan(rootPath: "/tmp/s\(i)", moduleID: "test")
            try db.completeScan(id: id, totalSize: 0, fileCount: 0, fsEventID: 0)
        }
        try db.clearOldScans(keepLast: 3)
        // We don't expose a count, but lastScan should still return the most recent.
        XCTAssertNotNil(try db.lastScan(moduleID: "test"))
    }

    func testCachedFileRecord_toFileItem() {
        let record = CachedFileRecord(
            path: "/tmp/x.txt", name: "x.txt", parentPath: "/tmp",
            size: 100, allocatedSize: 100,
            modificationDate: Date(),
            isDirectory: false, inode: 42, deviceID: 7
        )
        let item = record.toFileItem()
        XCTAssertEqual(item.url, URL(filePath: "/tmp/x.txt"))
        XCTAssertEqual(item.size, 100)
        XCTAssertEqual(item.inode, 42)
    }
}

