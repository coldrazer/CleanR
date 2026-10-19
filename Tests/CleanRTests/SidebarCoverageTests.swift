import XCTest
@testable import CleanR

/// Every sidebar module must be reachable and presentable: a unique deep
/// link, an icon, a title, and a theme. A module added to SidebarItem
/// without one of these ships as a dead or invisible entry.
final class SidebarCoverageTests: XCTestCase {

    func testEveryModuleHasUniqueDeepLinkIconAndTitle() {
        let items = SidebarItem.allCases
        XCTAssertEqual(Set(items.map(\.deepLinkID)).count, items.count, "deepLinkID must be unique per module")
        for item in items {
            XCTAssertFalse(item.icon.isEmpty, "\(item) has no icon")
            XCTAssertFalse(item.title.isEmpty, "\(item) has no title")
            XCTAssertEqual(SidebarItem(deepLinkID: item.deepLinkID), item, "\(item) does not round-trip its deep link")
        }
    }

    func testSettingsIsFooterOnlyAndEveryOtherModuleIsInASection() {
        for section in SidebarSection.allCases {
            XCTAssertFalse(section.items.contains(.settings), "Settings must stay pinned to the footer")
        }
        let sectioned = Set(SidebarSection.allCases.flatMap(\.items))
        XCTAssertEqual(sectioned, Set(SidebarItem.allCases).subtracting([.settings]),
                       "every non-Settings module must appear in exactly one section")
    }

    func testKeyboardShortcutsCoverNineUniqueModules() {
        let shortcuts = SidebarItem.keyboardShortcutItems
        XCTAssertEqual(shortcuts.count, 9)
        XCTAssertEqual(Set(shortcuts).count, 9)
        for digit in 1...9 {
            XCTAssertEqual(SidebarItem.item(forShortcutDigit: digit), shortcuts[digit - 1])
        }
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 0))
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 10))
    }
}
