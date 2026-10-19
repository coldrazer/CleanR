import XCTest
@testable import CleanRKit

final class LoginItemsOutputTests: XCTestCase {

    func testParsesEveryRecordFromTabDelimitedPayload() {
        let output = """
        C\t2
        #1\tDropbox\t/Applications/Dropbox.app\tfalse
        #2\tRectangle\t/Applications/Rectangle.app\ttrue
        """
        XCTAssertEqual(LoginItemsOutput.parse(output), [
            ParsedLoginItem(name: "Dropbox", path: "/Applications/Dropbox.app", hidden: false),
            ParsedLoginItem(name: "Rectangle", path: "/Applications/Rectangle.app", hidden: true),
        ])
    }

    func testParsesASingleRecord() {
        XCTAssertEqual(
            LoginItemsOutput.parse("C\t1\n#1\tDropbox\t/Applications/Dropbox.app\tfalse"),
            [ParsedLoginItem(name: "Dropbox", path: "/Applications/Dropbox.app", hidden: false)]
        )
    }

    func testRecordWithoutPathIsKept() {
        XCTAssertEqual(
            LoginItemsOutput.parse("C\t1\n#1\tHelper\t\tfalse"),
            [ParsedLoginItem(name: "Helper", path: nil, hidden: false)]
        )
    }

    func testZeroItemsIsAnEmptyListNotAMalformedPayload() {
        XCTAssertEqual(LoginItemsOutput.parse("C\t0"), [])
    }

    func testEmptyOutputIsRejected() {
        XCTAssertNil(LoginItemsOutput.parse(""))
        XCTAssertNil(LoginItemsOutput.parse("\n"))
    }

    // MARK: - Forgery resistance

    /// An installed app may name itself anything, including text that used to
    /// read as extra key/value pairs. A smuggled record must never surface as a
    /// plausible row that the user can then toggle into deleting a real app.
    func testLegacyKeyCommaPayloadIsRejectedNotMisread() {
        XCTAssertNil(LoginItemsOutput.parse("name:Dropbox, path:/Applications/Dropbox.app, hidden:false"))
    }

    func testNameEmbeddingLegacyRecordSyntaxIsRejected() {
        // The old parser produced a row named "Backup Helper" from this, which
        // deleting would have disabled an unrelated legitimate login item.
        let smuggled = "C\t1\n#1\tBackup Helper, path:/Applications/Other.app, hidden:false\t/Applications/Evil.app\tfalse"
        XCTAssertNotNil(LoginItemsOutput.parse(smuggled),
                        "a name with no tab or newline is just a name")
        XCTAssertEqual(LoginItemsOutput.parse(smuggled)?.first?.name,
                       "Backup Helper, path:/Applications/Other.app, hidden:false")
        XCTAssertEqual(LoginItemsOutput.parse(smuggled)?.first?.path, "/Applications/Evil.app")
    }

    func testSmuggledNewlineDesynchronizesAndFailsClosed() {
        let smuggled = """
        C\t2
        #1\tEvil\t/Applications/Evil.app\tfalse
        #2\tBackup Helper\t/Applications/Other.app\tfalse
        """
        // Well-formed smuggling is impossible: every line still has four fields
        // and sequential indices, so verify the parser at least never merges or
        // reorders them.
        let parsed = LoginItemsOutput.parse(smuggled)
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?[1].name, "Backup Helper")
    }

    func testExtraLineBeyondDeclaredCountIsRejected() {
        let output = """
        C\t1
        #1\tDropbox\t/Applications/Dropbox.app\tfalse
        #2\tGhost\t/Applications/Ghost.app\tfalse
        """
        XCTAssertNil(LoginItemsOutput.parse(output))
    }

    func testMissingLineForDeclaredCountIsRejected() {
        XCTAssertNil(LoginItemsOutput.parse("C\t2\n#1\tDropbox\t/Applications/Dropbox.app\tfalse"))
    }

    func testNonSequentialIndexIsRejected() {
        XCTAssertNil(LoginItemsOutput.parse("C\t1\n#2\tDropbox\t/Applications/Dropbox.app\tfalse"))
    }

    func testTabInPathFieldBreakingArityIsRejected() {
        XCTAssertNil(LoginItemsOutput.parse("C\t1\n#1\tDropbox\t/A\t/B\tfalse"))
    }

    func testUnparseableHiddenFlagIsRejected() {
        XCTAssertNil(LoginItemsOutput.parse("C\t1\n#1\tDropbox\t/Applications/Dropbox.app\tyes"))
    }

    func testMissingHeaderIsRejected() {
        XCTAssertNil(LoginItemsOutput.parse("#1\tDropbox\t/Applications/Dropbox.app\tfalse"))
    }

    func testNegativeDeclaredCountIsRejected() {
        XCTAssertNil(LoginItemsOutput.parse("C\t-1"))
    }
}
