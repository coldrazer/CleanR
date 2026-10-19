import XCTest
import Foundation
@testable import CleanRKit

final class ScanTargetTests: XCTestCase {

    // MARK: - matchesByNameRules

    func testMatchesByDefault() {
        let target = ScanTarget(path: URL(filePath: "/tmp"))
        XCTAssertTrue(target.matchesByNameRules(URL(filePath: "/tmp/foo.txt")))
    }

    func testExcludePatternBlocks() {
        let target = ScanTarget(
            path: URL(filePath: "/tmp"),
            excludePatterns: ["spotify"]
        )
        XCTAssertFalse(target.matchesByNameRules(URL(filePath: "/tmp/com.spotify.client")))
        XCTAssertTrue(target.matchesByNameRules(URL(filePath: "/tmp/com.apple.cache")))
    }

    func testExcludePatternCaseInsensitive() {
        let target = ScanTarget(
            path: URL(filePath: "/tmp"),
            excludePatterns: ["SpOtIfY"]
        )
        XCTAssertFalse(target.matchesByNameRules(URL(filePath: "/tmp/spotify-cache")))
    }

    func testFileExtensionWhitelist() {
        let target = ScanTarget(
            path: URL(filePath: "/tmp"),
            fileExtensions: ["log", "crash"]
        )
        XCTAssertTrue(target.matchesByNameRules(URL(filePath: "/tmp/error.log")))
        XCTAssertTrue(target.matchesByNameRules(URL(filePath: "/tmp/app.crash")))
        XCTAssertFalse(target.matchesByNameRules(URL(filePath: "/tmp/data.json")))
    }

    func testFileExtensionCaseInsensitive() {
        let target = ScanTarget(
            path: URL(filePath: "/tmp"),
            fileExtensions: ["LOG"]
        )
        XCTAssertTrue(target.matchesByNameRules(URL(filePath: "/tmp/error.log")))
        XCTAssertTrue(target.matchesByNameRules(URL(filePath: "/tmp/error.LOG")))
    }

    func testEmptyExtensionSetMatchesEverything() {
        let target = ScanTarget(
            path: URL(filePath: "/tmp"),
            fileExtensions: []
        )
        XCTAssertTrue(target.matchesByNameRules(URL(filePath: "/tmp/whatever.xyz")))
    }

    // MARK: - passesSizeFilter

    func testNoMinSizeAlwaysPasses() {
        let target = ScanTarget(path: URL(filePath: "/tmp"))
        XCTAssertTrue(target.passesSizeFilter(0))
        XCTAssertTrue(target.passesSizeFilter(.max))
    }

    func testMinSizeRejectsSmallFiles() {
        let target = ScanTarget(path: URL(filePath: "/tmp"), minSize: 1024)
        XCTAssertFalse(target.passesSizeFilter(1023))
        XCTAssertTrue(target.passesSizeFilter(1024))
        XCTAssertTrue(target.passesSizeFilter(10_000))
    }

    // MARK: - passesAgeFilters

    func testNoAgeFiltersAlwaysPasses() {
        let target = ScanTarget(path: URL(filePath: "/tmp"))
        XCTAssertTrue(target.passesAgeFilters(modificationDate: nil))
        XCTAssertTrue(target.passesAgeFilters(modificationDate: Date()))
    }

    func testMissingModDateFailsWhenFilterRequired() {
        let target = ScanTarget(path: URL(filePath: "/tmp"), minAge: 3600)
        XCTAssertFalse(target.passesAgeFilters(modificationDate: nil))
    }

    func testMinAgeFiltersRecentFiles() {
        let now = Date()
        let target = ScanTarget(path: URL(filePath: "/tmp"), minAge: 3600) // ≥ 1 hour old
        // Created 30 min ago → too recent → fails
        XCTAssertFalse(target.passesAgeFilters(modificationDate: now.addingTimeInterval(-1800), now: now))
        // Created 2 hr ago → passes
        XCTAssertTrue(target.passesAgeFilters(modificationDate: now.addingTimeInterval(-7200), now: now))
    }

    func testMaxAgeFiltersOldFiles() {
        let now = Date()
        let target = ScanTarget(path: URL(filePath: "/tmp"), maxAge: 7 * 24 * 3600) // ≤ 1 week
        // Created 1 month ago → too old → fails
        XCTAssertFalse(target.passesAgeFilters(modificationDate: now.addingTimeInterval(-30 * 24 * 3600), now: now))
        // Created 1 day ago → passes
        XCTAssertTrue(target.passesAgeFilters(modificationDate: now.addingTimeInterval(-24 * 3600), now: now))
    }

    func testBothMinAndMaxAgeApplied() {
        let now = Date()
        let target = ScanTarget(path: URL(filePath: "/tmp"), minAge: 24 * 3600, maxAge: 7 * 24 * 3600)
        // 30 min old: too young
        XCTAssertFalse(target.passesAgeFilters(modificationDate: now.addingTimeInterval(-1800), now: now))
        // 3 days old: in window
        XCTAssertTrue(target.passesAgeFilters(modificationDate: now.addingTimeInterval(-3 * 24 * 3600), now: now))
        // 1 month old: too old
        XCTAssertFalse(target.passesAgeFilters(modificationDate: now.addingTimeInterval(-30 * 24 * 3600), now: now))
    }

    // MARK: - Equatable

    func testEqualityByValue() {
        let a = ScanTarget(path: URL(filePath: "/tmp"), recursive: true, fileExtensions: ["log"])
        let b = ScanTarget(path: URL(filePath: "/tmp"), recursive: true, fileExtensions: ["log"])
        XCTAssertEqual(a, b)
    }
}
