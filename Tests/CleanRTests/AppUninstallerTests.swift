import XCTest
import Foundation
@testable import CleanR
@testable import CleanRKit

/// The uninstall decision logic, extracted from the view so it's testable.
/// Guards against the security-review finding: the app bundle used to be
/// trashed with a raw `try? trashItem` that skipped SafetyGuard and never
/// re-checked protected apps.
final class AppUninstallerTests: XCTestCase {

    private func app(_ bundleID: String, path: String = "/Applications/Foo.app") -> AppInfo {
        AppInfo(bundleIdentifier: bundleID, name: "Foo",
                path: URL(filePath: path), version: "1.0", size: 1000)
    }

    func testProtectedAppIsRefused() {
        // Finder is in the protected set; uninstall must refuse it regardless
        // of what the UI does (defense in depth beyond hiding the button).
        XCTAssertNil(AppUninstaller.plan(app: app("com.apple.finder"),
                                         associatedFiles: [], selectedFiles: []),
                     "a protected system app must never be uninstallable")
    }

    func testNormalAppRoutesBundleThroughEngine() {
        let a = app("com.example.foo", path: "/Applications/Foo.app")
        let plan = AppUninstaller.plan(app: a, associatedFiles: [], selectedFiles: [])
        // The bundle itself must be in the item list so it goes through the
        // validated, logged CleaningEngine, not a raw try? trashItem.
        XCTAssertTrue(plan?.items.contains { $0.url == a.path } ?? false,
                      "the app bundle must be routed through the cleaning engine")
        XCTAssertTrue(plan?.selection.contains(a.path) ?? false,
                      "the bundle must be selected for removal")
    }

    func testSelectedLeftoversArePreservedAlongsideBundle() {
        let a = app("com.example.foo", path: "/Applications/Foo.app")
        let leftover = FileItem(
            url: URL(filePath: "/Users/x/Library/Caches/com.example.foo"),
            name: "com.example.foo", size: 10, allocatedSize: 10, isDirectory: true)
        let plan = AppUninstaller.plan(app: a, associatedFiles: [leftover],
                                       selectedFiles: [leftover.url])
        XCTAssertTrue(plan?.items.contains { $0.url == leftover.url } ?? false)
        XCTAssertTrue(plan?.selection.contains(leftover.url) ?? false)
        XCTAssertTrue(plan?.selection.contains(a.path) ?? false,
                      "the bundle is always included even if only leftovers were checked")
    }

    // MARK: - Default selection (data-loss regression)

    private func item(_ url: URL) -> FileItem {
        FileItem(url: url, name: url.lastPathComponent,
                 size: 10, allocatedSize: 10, isDirectory: false)
    }

    /// Uninstalling Chrome used to pre-check every name match, and Chrome's
    /// `includeTerms: ["google", "chrome"]` substring-matches personal files in
    /// `~/Documents` and on `~/Desktop`. One click then trashed them.
    func testUserContentMatchesAreNeverPreSelected() {
        let home = MCConstants.home
        let files = [
            item(home.appending(path: "Documents/Google Docs notes.md")),
            item(home.appending(path: "Desktop/chrome-bookmarks.html")),
            item(home.appending(path: "Downloads/google-chrome.dmg")),
            item(home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Desktop/chrome.txt")),
        ]
        let selected = AppUninstaller.defaultSelectedURLs(for: files)
        XCTAssertTrue(selected.isEmpty,
                      "no match inside a user content root may be auto-checked: \(selected)")
    }

    func testLibraryLeftoversAreStillPreSelected() {
        let home = MCConstants.home
        let support = item(home.appending(path: "Library/Application Support/Google/Chrome"))
        let cache = item(home.appending(path: "Library/Caches/com.google.Chrome"))
        let prefs = item(home.appending(path: "Library/Preferences/com.google.Chrome.plist"))
        let selected = AppUninstaller.defaultSelectedURLs(for: [support, cache, prefs])
        XCTAssertEqual(selected, [support.url, cache.url, prefs.url])
    }

    /// A sibling whose name merely starts with a content-root name is not the
    /// user's content, so it should stay auto-selected like any other leftover.
    func testContentRootSiblingIsAutoSelected() {
        let sibling = item(MCConstants.home.appending(path: "DocumentsArchive/google-chrome.json"))
        XCTAssertEqual(AppUninstaller.defaultSelectedURLs(for: [sibling]), [sibling.url])
    }

    /// The other half of the contract: when the user does check a document, the
    /// plan must honour it. Refusing here would make opt-in impossible.
    func testExplicitUserSelectionOfADocumentSurvivesThePlan() {
        let a = app("com.example.foo", path: "/Applications/Foo.app")
        let doc = item(MCConstants.home.appending(path: "Documents/google-chrome-notes.md"))
        let plan = AppUninstaller.plan(app: a, associatedFiles: [doc], selectedFiles: [doc.url])
        XCTAssertTrue(plan?.selection.contains(doc.url) ?? false,
                      "an explicitly checked file must still be removable")
    }
}
