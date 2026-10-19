import XCTest
import Foundation
@testable import CleanR
import CleanRKit
import CleanRTestSupport

final class AppDiscoverySmokeTests: XCTestCase {

    func testDiscoversAtLeastOneApp() async {
        // Every Mac has Safari etc. in /Applications
        let apps = await AppDiscovery().discoverApps()
        XCTAssertGreaterThan(apps.count, 0,
                             "AppDiscovery should find at least one app in /Applications")
    }

    func testAppsAreSortedAlphabetically() async {
        let apps = await AppDiscovery().discoverApps()
        guard apps.count >= 2 else { return }
        for i in 1..<apps.count {
            XCTAssertLessThanOrEqual(
                apps[i-1].name.lowercased(),
                apps[i].name.lowercased(),
                "Apps should be sorted alphabetically"
            )
        }
    }
}
