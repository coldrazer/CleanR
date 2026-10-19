import XCTest
import Foundation
@testable import CleanR
@testable import CleanRKit
import CleanRTestSupport

/// Tests for the system-side AppDiscovery + AppPathFinder wrappers.
/// Pure matching logic lives in CleanRKit/Uninstaller/AppArtifactFinder.
final class UninstallerTests: XCTestCase {

    func testAppDiscoveryFindsSyntheticApp() async throws {
        // Create a fake .app under user's ~/Applications, run discovery,
        // verify it shows up.
        let myApps = MCConstants.home.appending(path: "Applications")
        try FileManager.default.createDirectory(at: myApps, withIntermediateDirectories: true)

        let uniqueName = "CleanRTestApp-\(UUID().uuidString.prefix(8))"
        let appPath = myApps.appending(path: "\(uniqueName).app")
        defer { try? FileManager.default.removeItem(at: appPath) }

        try TestFixtures.writeFakeApp(
            at: appPath,
            bundleIdentifier: "com.test.cleanr.\(uniqueName)",
            name: uniqueName,
            version: "1.0"
        )

        let apps = await AppDiscovery().discoverApps()
        let ours = apps.first { $0.name == uniqueName }
        XCTAssertNotNil(ours, "Discovery should find our synthetic .app at \(appPath.path(percentEncoded: false))")
        XCTAssertEqual(ours?.bundleIdentifier, "com.test.cleanr.\(uniqueName)")
    }

    func testAppPathFinderUsesAppArtifactFinder() {
        // AppPathFinder is a thin wrapper around AppArtifactFinder; just verify
        // the type-alias / instantiation path works.
        let finder = AppPathFinder(sensitivity: .deep)
        XCTAssertEqual(finder.sensitivity, AppArtifactFinder.Sensitivity.deep)
    }
}
