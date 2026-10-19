import XCTest
import Foundation
@testable import CleanRKit

final class VolumeInfoTests: XCTestCase {

    func testCreation() {
        let v = VolumeInfo(
            name: "Macintosh HD",
            url: URL(filePath: "/"),
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 250_000_000_000,
            fileSystemType: "APFS"
        )
        XCTAssertEqual(v.name, "Macintosh HD")
        XCTAssertEqual(v.totalCapacity, 1_000_000_000_000)
    }

    func testUsedCapacity() {
        let v = VolumeInfo(name: "T", url: URL(filePath: "/"),
                           totalCapacity: 1000, availableCapacity: 250)
        XCTAssertEqual(v.usedCapacity, 750)
    }

    func testUsedCapacityWhenAvailableExceedsTotal() {
        // Bogus data: available > total. Should not underflow.
        let v = VolumeInfo(name: "T", url: URL(filePath: "/"),
                           totalCapacity: 100, availableCapacity: 200)
        XCTAssertEqual(v.usedCapacity, 0, "Should not crash with arithmetic underflow")
    }

    func testUsagePercentage() {
        let v = VolumeInfo(name: "T", url: URL(filePath: "/"),
                           totalCapacity: 100, availableCapacity: 25)
        XCTAssertEqual(v.usagePercentage, 0.75, accuracy: 0.001)
    }

    func testUsagePercentageZeroTotal() {
        let v = VolumeInfo(name: "T", url: URL(filePath: "/"),
                           totalCapacity: 0, availableCapacity: 0)
        XCTAssertEqual(v.usagePercentage, 0)
    }

    func testEqualityByURL() {
        let a = VolumeInfo(name: "X", url: URL(filePath: "/"),
                           totalCapacity: 100, availableCapacity: 50)
        let b = VolumeInfo(name: "Y", url: URL(filePath: "/"),
                           totalCapacity: 999, availableCapacity: 999)
        XCTAssertEqual(a, b, "Volumes are equal if URLs match (the unique identifier)")
    }

    func testInequalityByURL() {
        let a = VolumeInfo(name: "X", url: URL(filePath: "/Volumes/A"),
                           totalCapacity: 100, availableCapacity: 50)
        let b = VolumeInfo(name: "X", url: URL(filePath: "/Volumes/B"),
                           totalCapacity: 100, availableCapacity: 50)
        XCTAssertNotEqual(a, b)
    }
}
