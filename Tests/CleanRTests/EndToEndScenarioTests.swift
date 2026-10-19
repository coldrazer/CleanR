import XCTest
import Foundation
@testable import CleanR
@testable import CleanRKit
import CleanRTestSupport

/// True end-to-end scenarios: real production scan modules run against
/// real fixtures, then the production Clean path removes the items.
///
/// Each test:
///   1. Plants known files under the actual production scan path
///      (a unique subdirectory of `~/Library/Caches`, `~/Library/Logs`, etc.)
///      — both files we EXPECT the scan to surface and decoy files we expect
///      it to ignore.
///   2. Runs the module's real `scan()` against the real filesystem.
///   3. Filters results to only items inside our test dir (the user's
///      real Caches/Logs may contain millions of items).
///   4. Asserts the scan found exactly the expected set.
///   5. Runs `CleanActions.executeUserClean` — the same code path every
///      production Clean button goes through.
///   6. Asserts the right files are gone and the decoy files are still
///      on disk.
final class EndToEndScenarioTests: XCTestCase {

    private var testRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in testRoots {
            try? FileManager.default.removeItem(at: url)
        }
        testRoots.removeAll()
    }

    // MARK: - Helpers

    private func makeTestDir(under parent: URL, label: String) throws -> URL {
        let dir = parent.appending(path: "CleanRE2E-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        testRoots.append(dir)
        return dir
    }

    @discardableResult
    private func writeFile(at url: URL, size: Int = 32, daysOld: Double? = nil) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
        if let daysOld {
            let mod = Date().addingTimeInterval(-daysOld * 24 * 3600)
            try FileManager.default.setAttributes(
                [.modificationDate: mod],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Filters scan results to items inside one of our test directories,
    /// so the user's actual filesystem contents don't pollute assertions.
    private func itemsInsideTestRoots(_ results: [ScanResult]) -> [FileItem] {
        let rootPaths = testRoots.map { $0.path(percentEncoded: false) }
        return results.flatMap(\.items).filter { item in
            let p = item.url.path(percentEncoded: false)
            return rootPaths.contains { p.hasPrefix($0 + "/") || p == $0 }
        }
    }

    // MARK: - Scenario 1: User cache scan finds and removes the right files

    func testUserCacheScan_findsAndCleansCacheFiles() async throws {
        let dir = try makeTestDir(under: MCConstants.userCaches, label: "user-cache")

        // Avoid directory names ending in ".app" — TargetedScanner uses
        // `.skipsPackageDescendants`, which treats `.app` directories as
        // bundles and skips their contents. That's intentional production
        // behavior; fixtures just have to honor it.
        let cache1 = try writeFile(at: dir.appending(path: "ExampleApp/cache.db"), size: 100)
        let cache2 = try writeFile(at: dir.appending(path: "ExampleApp/data.bin"), size: 200)
        let cache3 = try writeFile(at: dir.appending(path: "WebKit/temp.dat"), size: 50)

        let allResults = await SystemJunkModule().scan()
        let foundInOurDir = itemsInsideTestRoots(allResults)
        let foundURLs = Set(foundInOurDir.map(\.url))

        XCTAssertTrue(foundURLs.contains(cache1), "Scan should find ExampleApp/cache.db")
        XCTAssertTrue(foundURLs.contains(cache2), "Scan should find ExampleApp/data.bin")
        XCTAssertTrue(foundURLs.contains(cache3), "Scan should find WebKit/temp.dat")

        // Clean only the leaf files (the scan also returns parent dirs as items;
        // cleaning a dir + then its child races, since the child no longer exists).
        let fileItems = foundInOurDir.filter { !$0.isDirectory }
        let toClean = Set(fileItems.map(\.url))

        let scopedResults = [ScanResult(category: .userCaches, items: fileItems)]
        let result = await CleanActions.executeUserClean(
            results: scopedResults,
            selectedItems: toClean,
            engine: CleaningEngine()
        )

        XCTAssertFalse(exists(cache1), "cache.db must be gone after Clean")
        XCTAssertFalse(exists(cache2), "data.bin must be gone after Clean")
        XCTAssertFalse(exists(cache3), "temp.dat must be gone after Clean")
        XCTAssertEqual(result.removedCount, toClean.count,
                       "Reported removedCount must match items actually cleaned")
    }

    // MARK: - Scenario 2: Exclude pattern protects the entire subtree
    //
    // BEHAVIORAL SPEC: when a category declares `excludePatterns: ["com.spotify.client"]`,
    // it means "never offer anything under a Spotify dir for cleanup" — deleting
    // Spotify's cache wipes the user's offline music. This test asserts the
    // spec, not whatever the implementation currently does.

    func testUserCacheScan_excludePatternProtectsEntireSubtree() async throws {
        let dir = try makeTestDir(under: MCConstants.userCaches, label: "exclude-test")

        let spotifyDir = dir.appending(path: "com.spotify.client")
        let spotifyChild = try writeFile(at: spotifyDir.appending(path: "marker.dat"), size: 10)
        let normalDir = dir.appending(path: "com.example.normal")
        let normalChild = try writeFile(at: normalDir.appending(path: "marker.dat"), size: 10)

        let results = await SystemJunkModule().scan()
        let foundURLs = Set(itemsInsideTestRoots(results).map(\.url))

        // Sanity: a non-excluded subtree IS found (otherwise the scan didn't run).
        XCTAssertTrue(foundURLs.contains(normalChild),
                      "Non-excluded subtree must surface in results")

        // SPEC: nothing under an excluded directory should be in results.
        XCTAssertFalse(foundURLs.contains(spotifyChild),
                       "Files under com.spotify.client must NOT be in results — " +
                       "deleting them destroys the user's Spotify offline music cache")
        XCTAssertFalse(foundURLs.contains(spotifyDir),
                       "The excluded directory itself must not be in results")
    }

    // MARK: - Scenario 3: User log scan picks the right extensions

    func testUserLogScan_onlyFindsLogExtensions() async throws {
        let dir = try makeTestDir(under: MCConstants.userLogs, label: "log-test")

        // UserLogCategory's extension filter: log / txt / crash / diag / ips
        let goodLog = try writeFile(at: dir.appending(path: "good.log"), size: 100)
        let goodCrash = try writeFile(at: dir.appending(path: "good.crash"), size: 200)
        let decoyJson = try writeFile(at: dir.appending(path: "decoy.json"), size: 50)
        let decoyBinary = try writeFile(at: dir.appending(path: "decoy.bin"), size: 50)

        let results = await SystemJunkModule().scan()
        let foundURLs = Set(itemsInsideTestRoots(results).map(\.url))

        XCTAssertTrue(foundURLs.contains(goodLog), ".log file should be picked up")
        XCTAssertTrue(foundURLs.contains(goodCrash), ".crash file should be picked up")
        XCTAssertFalse(foundURLs.contains(decoyJson), ".json should be filtered by extension")
        XCTAssertFalse(foundURLs.contains(decoyBinary), ".bin should be filtered by extension")
    }

    // MARK: - Scenario 4: Selection-based cleaning leaves unselected files alone

    func testCleanRespectsSelection_unselectedFilesPreserved() async throws {
        let dir = try makeTestDir(under: MCConstants.userCaches, label: "selection-test")

        let keep1 = try writeFile(at: dir.appending(path: "keep1.cache"), size: 100)
        let keep2 = try writeFile(at: dir.appending(path: "keep2.cache"), size: 100)
        let delete1 = try writeFile(at: dir.appending(path: "delete1.cache"), size: 100)
        let delete2 = try writeFile(at: dir.appending(path: "delete2.cache"), size: 100)

        let scanned = await SystemJunkModule().scan()
        let allFound = itemsInsideTestRoots(scanned)

        // User selects only the two "delete*" files
        let toDelete: Set<URL> = [delete1, delete2]
        let result = await CleanActions.executeUserClean(
            results: [ScanResult(category: .userCaches, items: allFound)],
            selectedItems: toDelete,
            engine: CleaningEngine()
        )

        XCTAssertTrue(exists(keep1), "Unselected file keep1.cache must NOT be deleted")
        XCTAssertTrue(exists(keep2), "Unselected file keep2.cache must NOT be deleted")
        XCTAssertFalse(exists(delete1), "Selected file delete1.cache must be deleted")
        XCTAssertFalse(exists(delete2), "Selected file delete2.cache must be deleted")
        XCTAssertEqual(result.removedCount, 2)
    }

    // MARK: - Scenario 5: Broken downloads scan + clean
    //
    // Skipped automatically if the test runner lacks TCC permission to read
    // `~/Downloads` (Apple's Privacy controls block CLI tools by default).
    // Run from an environment with Downloads access to exercise this.

    func testBrokenDownloadsScan_findsPartialDownloads() async throws {
        try XCTSkipUnless(
            FileManager.default.isReadableFile(atPath: MCConstants.downloads.path(percentEncoded: false))
                && (try? FileManager.default.contentsOfDirectory(atPath: MCConstants.downloads.path(percentEncoded: false))) != nil,
            "Test runner lacks read access to ~/Downloads (macOS TCC). Skipping — grant Files & Folders → Downloads to the terminal to run."
        )

        // BrokenDownloadsCategory is non-recursive on ~/Downloads. Files must
        // sit directly in ~/Downloads.
        let prefix = "CleanRE2E-Broken-\(UUID().uuidString)"
        let partial1 = MCConstants.downloads.appending(path: "\(prefix).part")
        let crdownload = MCConstants.downloads.appending(path: "\(prefix).crdownload")
        let decoyDmg = MCConstants.downloads.appending(path: "\(prefix).txt") // wrong ext

        defer {
            try? FileManager.default.removeItem(at: partial1)
            try? FileManager.default.removeItem(at: crdownload)
            try? FileManager.default.removeItem(at: decoyDmg)
        }

        try writeFile(at: partial1, size: 100)
        try writeFile(at: crdownload, size: 200)
        try writeFile(at: decoyDmg, size: 50)

        let scanned = await SystemJunkModule().scan()
        let foundURLs = Set(scanned.flatMap(\.items).map(\.url))

        XCTAssertTrue(foundURLs.contains(partial1), ".part file in Downloads should be found")
        XCTAssertTrue(foundURLs.contains(crdownload), ".crdownload file in Downloads should be found")
        XCTAssertFalse(foundURLs.contains(decoyDmg),
                       "Non-matching extension must NOT be in BrokenDownloads results")

        let toDelete: Set<URL> = [partial1, crdownload]
        let items = scanned.flatMap(\.items).filter { toDelete.contains($0.url) }
        _ = await CleanActions.executeUserClean(
            results: [ScanResult(category: .brokenDownloads, items: items)],
            selectedItems: toDelete,
            engine: CleaningEngine()
        )

        XCTAssertFalse(exists(partial1))
        XCTAssertFalse(exists(crdownload))
        XCTAssertTrue(exists(decoyDmg), "Decoy file with non-matching extension must NOT be cleaned")
    }

    // MARK: - Scenario 6: dryRun mode genuinely preserves files

    func testEngine_dryRunModeGenuinelyPreservesFiles() async throws {
        // Inverse of the .dryRun bug we fixed: the engine MUST still support
        // dryRun mode (used for previews); production code paths just shouldn't
        // call it. Verify the mode itself behaves as documented.
        let dir = try makeTestDir(under: MCConstants.userCaches, label: "dryrun-mode")
        let file = try writeFile(at: dir.appending(path: "preview.cache"), size: 100)

        let item = FileItem(url: file, name: "preview.cache",
                            size: 100, allocatedSize: 100, isDirectory: false)
        let result = await CleaningEngine().clean(items: [item], mode: .dryRun)

        XCTAssertTrue(exists(file), "dryRun must NOT delete the file")
        XCTAssertEqual(result.removedCount, 1, "dryRun must still report what would have been removed")
        XCTAssertEqual(result.freedBytes, 100)
    }

    // MARK: - Scenario 7: SmartScan flow — multiple categories surface together

    func testSmartScanFlow_aggregatesAcrossCategories() async throws {
        let cacheDir = try makeTestDir(under: MCConstants.userCaches, label: "smart-cache")
        let logDir = try makeTestDir(under: MCConstants.userLogs, label: "smart-log")

        let cacheFile = try writeFile(at: cacheDir.appending(path: "x.cache"), size: 100)
        let logFile = try writeFile(at: logDir.appending(path: "y.log"), size: 200)

        let results = await SystemJunkModule().scan()

        let cacheItems = results.first(where: { $0.category == .userCaches })?.items ?? []
        let logItems = results.first(where: { $0.category == .userLogs })?.items ?? []

        XCTAssertTrue(cacheItems.contains { $0.url == cacheFile },
                      "userCaches category should contain our planted cache file")
        XCTAssertTrue(logItems.contains { $0.url == logFile },
                      "userLogs category should contain our planted log file")

        let scopedResults = [
            ScanResult(category: .userCaches, items: cacheItems.filter { $0.url == cacheFile }),
            ScanResult(category: .userLogs, items: logItems.filter { $0.url == logFile }),
        ]
        let result = await CleanActions.executeUserClean(
            results: scopedResults,
            selectedItems: [cacheFile, logFile],
            engine: CleaningEngine()
        )

        XCTAssertFalse(exists(cacheFile), "Cache file should be cleaned")
        XCTAssertFalse(exists(logFile), "Log file should be cleaned")
        XCTAssertEqual(result.removedCount, 2)
        XCTAssertEqual(result.freedBytes, 300)
    }

    // MARK: - Scenario 8: Cleaned file actually ends up in Trash (not destroyed)
    //
    // BEHAVIORAL SPEC: the product promises "Move to Trash, not delete forever"
    // so users can recover from a mistake. Verify the file genuinely lands in
    // ~/.Trash after a Clean — not just that it's gone from the source path.

    func testCleanedFile_actuallyEndsUpInTrash_recoverable() async throws {
        // TCC quirk: macOS lets apps WRITE to ~/.Trash without granting READ
        // access. Detect that case first so we don't false-negative on
        // a successful trash operation. Write a marker file directly into
        // Trash, then try to list it. If listing returns nothing, the test
        // runner can't observe Trash contents and the test isn't meaningful.
        let trash = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
        let marker = trash.appending(path: "CleanRE2E-tcc-probe-\(UUID().uuidString)")
        try? Data(count: 1).write(to: marker)
        defer { try? FileManager.default.removeItem(at: marker) }

        let canSeeTrash = (try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil
        ).contains { $0.lastPathComponent == marker.lastPathComponent }) ?? false
        try XCTSkipUnless(canSeeTrash,
            "Test runner lacks read access to ~/.Trash (macOS TCC). " +
            "Grant Files & Folders → Trash (or Full Disk Access) to the terminal to run.")

        let dir = try makeTestDir(under: MCConstants.userCaches, label: "trash-spec")
        let uniqueName = "trash-spec-\(UUID().uuidString).cache"
        let source = try writeFile(at: dir.appending(path: uniqueName), size: 100)

        let item = FileItem(url: source, name: uniqueName,
                            size: 100, allocatedSize: 100, isDirectory: false)
        let result = await CleaningEngine().clean(items: [item], mode: .trash)

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertFalse(exists(source), "Source must be gone from its original location")

        // macOS may rename trashed duplicates with a timestamp suffix
        // (e.g. "<name> 2026-05-30 11.27.13.cache"), so match on the unique stem.
        let trashContents = (try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil
        )) ?? []
        let stem = (uniqueName as NSString).deletingPathExtension
        let matched = trashContents.filter { $0.lastPathComponent.contains(stem) }
        XCTAssertFalse(matched.isEmpty,
                       "SPEC: Cleaned file must appear in ~/.Trash so the user can recover it.")

        // Cleanup: don't pollute the user's bin with test artifacts.
        for url in matched {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Scenario 9: Idempotency — rescanning after clean doesn't re-find cleaned items
    //
    // BEHAVIORAL SPEC: clean an item, scan again, the item must NOT reappear.
    // (Trivially true if clean works, but catches regressions where the engine
    // misreports success — e.g., the original dry-run bug where files weren't
    // actually deleted but the engine returned removedCount > 0.)

    func testRescanAfterClean_doesNotReFindCleanedItems() async throws {
        let dir = try makeTestDir(under: MCConstants.userCaches, label: "idempotency")
        let f1 = try writeFile(at: dir.appending(path: "first.cache"), size: 100)
        let f2 = try writeFile(at: dir.appending(path: "second.cache"), size: 200)

        // First scan should find both.
        let firstScan = await SystemJunkModule().scan()
        let firstURLs = Set(itemsInsideTestRoots(firstScan).map(\.url))
        XCTAssertTrue(firstURLs.contains(f1), "First scan must find first.cache")
        XCTAssertTrue(firstURLs.contains(f2), "First scan must find second.cache")

        // Clean only f1.
        let fileItems = itemsInsideTestRoots(firstScan).filter { !$0.isDirectory && $0.url == f1 }
        _ = await CleanActions.executeUserClean(
            results: [ScanResult(category: .userCaches, items: fileItems)],
            selectedItems: [f1],
            engine: CleaningEngine()
        )

        // Second scan: f1 must be GONE, f2 must STILL be there.
        let secondScan = await SystemJunkModule().scan()
        let secondURLs = Set(itemsInsideTestRoots(secondScan).map(\.url))
        XCTAssertFalse(secondURLs.contains(f1),
                       "SPEC: cleaned item must not reappear in a fresh scan — " +
                       "if it does, either the clean lied about success or the scan ignores filesystem reality")
        XCTAssertTrue(secondURLs.contains(f2),
                      "Uncleaned items must still be found by a fresh scan")
    }

    // MARK: - Scenario 10: Protected paths stay protected even in a real scan→clean chain

    func testProtectedPath_neverDeletedEvenIfManuallyInjected() async throws {
        // Imagine a (buggy) future module produced a ScanResult containing a
        // SIP-protected path. CleanActions / CleaningEngine / SafetyGuard must
        // collectively refuse to delete it regardless of how it got into the input.
        let unsafe = FileItem(
            url: URL(filePath: "/System/Library/CoreServices/Finder.app"),
            name: "Finder.app",
            size: 100, allocatedSize: 100, isDirectory: true
        )

        let result = await CleanActions.executeUserClean(
            results: [ScanResult(category: .userCaches, items: [unsafe])],
            selectedItems: [unsafe.url],
            engine: CleaningEngine()
        )

        XCTAssertEqual(result.removedCount, 0, "Protected SIP path must never be cleaned")
        XCTAssertFalse(result.errors.isEmpty, "Engine must report the validation failure")
        XCTAssertTrue(exists(unsafe.url), "Finder.app must still exist on disk")
    }
}
