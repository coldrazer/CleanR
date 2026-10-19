import XCTest
import Foundation
@testable import CleanRKit

final class PlistJunkFilterTests: XCTestCase {

    private let validPlistData = try! PropertyListSerialization.data(
        fromPropertyList: ["key": "value"], format: .binary, options: 0
    )
    private let validLoader: (URL) -> Data? = { _ in
        try! PropertyListSerialization.data(
            fromPropertyList: ["key": "value"], format: .binary, options: 0
        )
    }
    private let corruptLoader: (URL) -> Data? = { _ in Data([0x00, 0xFF, 0xAB]) }
    private let noAppRegistered: (String) -> Bool = { _ in false }
    private let allAppsRegistered: (String) -> Bool = { _ in true }

    // MARK: - The critical safety contract

    func testAppleSystemPlistsNeverFlagged() {
        let names = [
            "com.apple.loginwindow", "com.apple.dock", "com.apple.finder",
            "com.apple.systempreferences", "com.apple.iCloud", "com.apple.security",
            "com.apple.Safari", "com.apple.mail",
        ]
        for name in names {
            let url = MCConstants.userPreferences.appending(path: "\(name).plist")
            XCTAssertFalse(
                PlistJunkFilter.isLikelyBroken(at: url, loadData: validLoader, appExistsForBundleID: noAppRegistered),
                "Apple system plist '\(name)' must NEVER be flagged for deletion"
            )
        }
    }

    func testAppGroupPlistsNeverFlagged() {
        let url = MCConstants.userPreferences.appending(path: "group.com.apple.notes.plist")
        XCTAssertFalse(
            PlistJunkFilter.isLikelyBroken(at: url, loadData: validLoader, appExistsForBundleID: noAppRegistered)
        )
    }

    func testValidThirdPartyPlistNotFlaggedEvenIfAppNotRegistered() {
        let url = MCConstants.userPreferences.appending(path: "com.example.unregistered.plist")
        XCTAssertFalse(
            PlistJunkFilter.isLikelyBroken(at: url, loadData: validLoader, appExistsForBundleID: noAppRegistered),
            "A valid plist must never be flagged solely because Launch Services doesn't know the bundle"
        )
    }

    // MARK: - True corruption is flagged

    func testCorruptThirdPartyPlistIsFlagged() {
        let url = MCConstants.userPreferences.appending(path: "com.example.corrupt.plist")
        XCTAssertTrue(
            PlistJunkFilter.isLikelyBroken(at: url, loadData: corruptLoader, appExistsForBundleID: allAppsRegistered)
        )
    }

    func testCorruptAppleSystemPlistIsNotFlagged() {
        // Even if the data is corrupt, never touch Apple-owned domains.
        let url = MCConstants.userPreferences.appending(path: "com.apple.loginwindow.plist")
        XCTAssertFalse(
            PlistJunkFilter.isLikelyBroken(at: url, loadData: corruptLoader, appExistsForBundleID: noAppRegistered),
            "Corrupt Apple system plists are macOS's problem to regenerate, not ours to delete"
        )
    }

    // MARK: - File extension guard

    func testNonPlistFileIsNotFlagged() {
        let url = MCConstants.userPreferences.appending(path: "com.example.app.txt")
        XCTAssertFalse(
            PlistJunkFilter.isLikelyBroken(at: url, loadData: corruptLoader, appExistsForBundleID: noAppRegistered)
        )
    }

    // MARK: - Unreadable files

    func testUnreadableFileNotFlagged() {
        let url = MCConstants.userPreferences.appending(path: "com.example.permission-denied.plist")
        let nilLoader: (URL) -> Data? = { _ in nil }
        XCTAssertFalse(
            PlistJunkFilter.isLikelyBroken(at: url, loadData: nilLoader, appExistsForBundleID: noAppRegistered),
            "Don't blindly flag files we can't even read — could be transient permission issue"
        )
    }

    // MARK: - isAppleSystemDomain

    func testIsAppleSystemDomain() {
        XCTAssertTrue(PlistJunkFilter.isAppleSystemDomain("com.apple.loginwindow"))
        XCTAssertTrue(PlistJunkFilter.isAppleSystemDomain("com.apple.dock"))
        XCTAssertTrue(PlistJunkFilter.isAppleSystemDomain("COM.APPLE.FINDER")) // case insensitive
        XCTAssertTrue(PlistJunkFilter.isAppleSystemDomain("group.com.apple.notes"))
        XCTAssertTrue(PlistJunkFilter.isAppleSystemDomain("group.com.apple.mail"))

        XCTAssertFalse(PlistJunkFilter.isAppleSystemDomain("com.example.app"))
        XCTAssertFalse(PlistJunkFilter.isAppleSystemDomain("net.macromates.TextMate"))
        XCTAssertFalse(PlistJunkFilter.isAppleSystemDomain("com.google.Chrome"))
        XCTAssertFalse(PlistJunkFilter.isAppleSystemDomain(""))
    }
}
