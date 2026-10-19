import XCTest
@testable import CleanR

final class DeepLinkRoutingTests: XCTestCase {
    func testDeepLinkIDRoundTrips() {
        XCTAssertEqual(SidebarItem.systemJunk.deepLinkID, "system-junk")
        XCTAssertEqual(SidebarItem(deepLinkID: "system-junk"), .systemJunk)
        XCTAssertEqual(SidebarItem(deepLinkID: "trash-bins"), .trashBins)
        XCTAssertEqual(SidebarItem.wifiNetworks.deepLinkID, "wifi-networks")
        XCTAssertEqual(SidebarItem(deepLinkID: "wifi-networks"), .wifiNetworks)
        XCTAssertEqual(SidebarItem.appPermissions.deepLinkID, "app-permissions")
        XCTAssertEqual(SidebarItem(deepLinkID: "app-permissions"), .appPermissions)
        XCTAssertEqual(SidebarItem.extensions.deepLinkID, "extensions")
        XCTAssertEqual(SidebarItem(deepLinkID: "extensions"), .extensions)
        XCTAssertEqual(SidebarItem.browserExtensions.deepLinkID, "browser-extensions")
        XCTAssertEqual(SidebarItem(deepLinkID: "browser-extensions"), .browserExtensions)
        XCTAssertEqual(SidebarItem.diskHogs.deepLinkID, "disk-hogs")
        XCTAssertEqual(SidebarItem(deepLinkID: "disk-hogs"), .diskHogs)
        XCTAssertEqual(SidebarItem.projectJunk.deepLinkID, "project-junk")
        XCTAssertEqual(SidebarItem(deepLinkID: "project-junk"), .projectJunk)
        XCTAssertEqual(SidebarItem.cleanHistory.deepLinkID, "clean-history")
        XCTAssertEqual(SidebarItem(deepLinkID: "clean-history"), .cleanHistory)
        XCTAssertEqual(SidebarItem.unusedApps.deepLinkID, "unused-apps")
        XCTAssertEqual(SidebarItem(deepLinkID: "unused-apps"), .unusedApps)
        XCTAssertNil(SidebarItem(deepLinkID: "nonsense"))
    }
}
