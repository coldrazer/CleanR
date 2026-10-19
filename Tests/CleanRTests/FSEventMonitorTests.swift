import XCTest
import Foundation
@testable import CleanR
import CleanRTestSupport

final class FSEventMonitorTests: XCTestCase {

    func testCurrentEventIDIsNonZero() {
        let monitor = FSEventMonitor()
        XCTAssertGreaterThan(monitor.currentEventID, 0,
                             "FSEvents should always report a current event ID")
    }

    func testInvalidatedPathsForRescanFlag() {
        let monitor = FSEventMonitor()
        let mustRescanFlag = UInt32(kFSEventStreamEventFlagMustScanSubDirs)
        let change = FSEventMonitor.FSChange(
            path: "/tmp/x",
            flags: mustRescanFlag,
            eventID: 1
        )
        let invalidated = monitor.invalidatedPaths(changes: [change])
        XCTAssertTrue(invalidated.contains("/tmp/x"))
    }

    /// URL.deletingLastPathComponent emits trailing-slash form, so we match
    /// against both forms to keep the test resilient to that quirk.
    private func parentDirVariants(_ path: String) -> Set<String> {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return [trimmed, trimmed + "/"]
    }

    func testInvalidatedPathsForCreatedItem() {
        let monitor = FSEventMonitor()
        let change = FSEventMonitor.FSChange(
            path: "/tmp/dir/newfile.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
            eventID: 1
        )
        let invalidated = monitor.invalidatedPaths(changes: [change])
        // Accept "/tmp/dir", "/tmp/dir/", or the /private/tmp equivalent.
        let acceptable = parentDirVariants("/tmp/dir").union(parentDirVariants("/private/tmp/dir"))
        XCTAssertFalse(invalidated.isDisjoint(with: acceptable),
                       "Should invalidate parent dir; got: \(invalidated)")
    }

    func testInvalidatedPathsForRemovedItem() {
        let monitor = FSEventMonitor()
        let change = FSEventMonitor.FSChange(
            path: "/tmp/dir/oldfile.txt",
            flags: UInt32(kFSEventStreamEventFlagItemRemoved),
            eventID: 1
        )
        let invalidated = monitor.invalidatedPaths(changes: [change])
        let acceptable = parentDirVariants("/tmp/dir").union(parentDirVariants("/private/tmp/dir"))
        XCTAssertFalse(invalidated.isDisjoint(with: acceptable),
                       "Got: \(invalidated)")
    }

    func testEmptyChangesProduceEmptyInvalidated() {
        let monitor = FSEventMonitor()
        XCTAssertTrue(monitor.invalidatedPaths(changes: []).isEmpty)
    }
}
