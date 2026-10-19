import XCTest
import Foundation
@testable import CleanRKit

final class DeletedUsersTests: XCTestCase {

    // MARK: - isResidualHomeFolder

    func testActiveUserNotFlagged() {
        XCTAssertFalse(
            DeletedUsersCategory.isResidualHomeFolder(name: "iliya", activeUsers: ["iliya", "guest"])
        )
    }

    func testInactiveUserFlagged() {
        XCTAssertTrue(
            DeletedUsersCategory.isResidualHomeFolder(name: "deleted_user", activeUsers: ["iliya"])
        )
    }

    func testSharedFolderNeverFlagged() {
        XCTAssertFalse(
            DeletedUsersCategory.isResidualHomeFolder(name: "Shared", activeUsers: ["iliya"])
        )
    }

    func testLocalizedFolderNeverFlagged() {
        XCTAssertFalse(
            DeletedUsersCategory.isResidualHomeFolder(name: ".localized", activeUsers: ["iliya"])
        )
    }

    func testGuestFolderNeverFlagged() {
        XCTAssertFalse(
            DeletedUsersCategory.isResidualHomeFolder(name: "Guest", activeUsers: [])
        )
    }

    func testHiddenFolderNeverFlagged() {
        XCTAssertFalse(
            DeletedUsersCategory.isResidualHomeFolder(name: ".hidden", activeUsers: [])
        )
        XCTAssertFalse(
            DeletedUsersCategory.isResidualHomeFolder(name: ".DS_Store", activeUsers: [])
        )
    }

    func testEmptyActiveUsersFlagsRealLookingNames() {
        XCTAssertTrue(
            DeletedUsersCategory.isResidualHomeFolder(name: "iliya", activeUsers: [])
        )
    }

    // MARK: - parseDsclOutput

    func testParseDsclTypical() {
        let output = """
        _amavisd
        _analyticsd
        _appleevents
        _appstore
        daemon
        iliya
        nobody
        root
        """
        let users = DeletedUsersCategory.parseDsclOutput(output)
        XCTAssertTrue(users.contains("iliya"))
        XCTAssertTrue(users.contains("daemon"))
        XCTAssertTrue(users.contains("nobody"))
        XCTAssertTrue(users.contains("root"))
        // Underscore-prefixed entries dropped
        XCTAssertFalse(users.contains("_amavisd"))
        XCTAssertFalse(users.contains("_analyticsd"))
    }

    func testParseDsclWithBlankLines() {
        let output = "\niliya\n\nadmin\n\n"
        let users = DeletedUsersCategory.parseDsclOutput(output)
        XCTAssertEqual(users, ["iliya", "admin"])
    }

    func testParseDsclEmpty() {
        XCTAssertEqual(DeletedUsersCategory.parseDsclOutput(""), [])
    }

    func testParseDsclWhitespaceOnly() {
        XCTAssertEqual(DeletedUsersCategory.parseDsclOutput("   \n  \n"), [])
    }

    func testParseDsclTrimsWhitespace() {
        let output = "  iliya  \n   admin\n"
        let users = DeletedUsersCategory.parseDsclOutput(output)
        XCTAssertTrue(users.contains("iliya"))
        XCTAssertTrue(users.contains("admin"))
    }
}
