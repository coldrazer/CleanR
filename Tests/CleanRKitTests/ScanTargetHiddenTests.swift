import XCTest
import Foundation
@testable import CleanRKit

/// Covers the opt-in "skip hidden subtrees" knob the duplicate finder uses to
/// stay out of dot-directories (app caches, editor extensions, tool configs)
/// rather than surfacing app state as user duplicates.
final class ScanTargetHiddenTests: XCTestCase {

    func testIsHiddenEntryDetectsDotPrefix() {
        XCTAssertTrue(ScanTarget.isHiddenEntry(URL(filePath: "/Users/me/.cache")))
        XCTAssertTrue(ScanTarget.isHiddenEntry(URL(filePath: "/Users/me/.config")))
        XCTAssertTrue(ScanTarget.isHiddenEntry(URL(filePath: "/Users/me/.env")))
    }

    func testIsHiddenEntryFalseForVisibleEntries() {
        XCTAssertFalse(ScanTarget.isHiddenEntry(URL(filePath: "/Users/me/Documents")))
        XCTAssertFalse(ScanTarget.isHiddenEntry(URL(filePath: "/Users/me/Pictures/photo.jpg")))
        XCTAssertFalse(ScanTarget.isHiddenEntry(URL(filePath: "/Users/me/report.pdf")))
    }

    func testSkipHiddenDirectoriesDefaultsOff() {
        let target = ScanTarget(path: URL(filePath: "/Users/me"))
        XCTAssertFalse(target.skipHiddenDirectories,
                       "default must stay false so existing modules are unaffected")
    }

    func testSkipHiddenDirectoriesStored() {
        let target = ScanTarget(path: URL(filePath: "/Users/me"), skipHiddenDirectories: true)
        XCTAssertTrue(target.skipHiddenDirectories)
    }
}
