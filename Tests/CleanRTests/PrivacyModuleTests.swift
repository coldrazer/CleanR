import XCTest
@testable import CleanR
import CleanRKit

final class PrivacyModuleTests: XCTestCase {
    private let safariDirectory = URL(filePath: "/Users/test/Library/Safari")

    func testSafariRootFilterExcludesNonHistoryData() {
        let items = [
            item("Bookmarks.plist"),
            item("BookmarksMetadata.plist"),
            item("CloudTabs.db"),
            item("TopSites.plist"),
            item("PerSitePreferences.db"),
            item("LastSession.plist"),
        ]

        let filtered = PrivacyModule.filterSafariRootItems(
            items,
            safariDirectory: safariDirectory
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    func testSafariRootFilterKeepsHistoryData() {
        let items = [
            item("History.db"),
            item("History.plist"),
        ]

        let filtered = PrivacyModule.filterSafariRootItems(
            items,
            safariDirectory: safariDirectory
        )

        XCTAssertEqual(Set(filtered.map(\.name)), ["History.db", "History.plist"])
    }

    func testSafariRootFilterLeavesOtherBrowserDataUntouched() {
        let chromeCookie = item(
            "Cookies",
            directory: URL(filePath: "/Users/test/Library/Application Support/Google/Chrome/Default")
        )

        let filtered = PrivacyModule.filterSafariRootItems(
            [chromeCookie],
            safariDirectory: safariDirectory
        )

        XCTAssertEqual(filtered, [chromeCookie])
    }

    private func item(_ name: String, directory: URL? = nil) -> FileItem {
        let url = (directory ?? safariDirectory).appending(path: name)
        return FileItem(
            url: url,
            name: name,
            size: 1,
            allocatedSize: 1,
            isDirectory: false
        )
    }
}
