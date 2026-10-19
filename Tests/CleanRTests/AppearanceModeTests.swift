import XCTest
@testable import CleanR

final class AppearanceModeTests: XCTestCase {
    func testNSAppearanceMapping() {
        XCTAssertNil(AppearanceMode.system.nsAppearance)   // nil clears the override
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }

    func testRawValuesRoundTrip() {
        for mode in AppearanceMode.allCases {
            XCTAssertEqual(AppearanceMode(rawValue: mode.rawValue), mode)
        }
        XCTAssertNil(AppearanceMode(rawValue: "nonsense"))
    }
}
