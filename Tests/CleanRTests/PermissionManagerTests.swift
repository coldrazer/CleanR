import XCTest
import Foundation
@testable import CleanR

final class PermissionManagerTests: XCTestCase {

    func testSingletonReturnsSameInstance() {
        XCTAssertTrue(PermissionManager.shared === PermissionManager.shared)
    }

    // Intentionally NOT testing openFullDiskAccessSettings() — it would
    // physically pop open System Settings every test run. The implementation
    // is one line that calls NSWorkspace; not worth the noise.
}
