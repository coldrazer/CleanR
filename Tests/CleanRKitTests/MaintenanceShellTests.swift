import XCTest
@testable import CleanRKit

final class MaintenanceShellTests: XCTestCase {
    func testPlainWordIsQuoted() {
        XCTAssertEqual(MaintenanceShell.quote("daily"), "'daily'")
    }

    func testSpacesArePreservedInsideQuotes() {
        XCTAssertEqual(MaintenanceShell.quote("/Volumes/My Disk"), "'/Volumes/My Disk'")
    }

    func testSingleQuoteIsEscaped() {
        // POSIX idiom: close quote, escaped quote, reopen quote.
        XCTAssertEqual(MaintenanceShell.quote("a'b"), "'a'\\''b'")
    }

    func testMetacharactersAreNeutralised() {
        XCTAssertEqual(MaintenanceShell.quote("x; rm -rf /"), "'x; rm -rf /'")
        XCTAssertEqual(MaintenanceShell.quote("$(whoami)"), "'$(whoami)'")
        XCTAssertEqual(MaintenanceShell.quote("`id`"), "'`id`'")
    }

    func testCommandLineJoinsQuotedArgs() {
        let line = MaintenanceShell.commandLine("/usr/sbin/periodic", ["daily", "weekly"])
        XCTAssertEqual(line, "'/usr/sbin/periodic' 'daily' 'weekly'")
    }

    // MARK: - AppleScript source (issue #143)

    /// Admin tasks run `do shell script` in-process so macOS can cache the
    /// password (~5 min, per process). The source string is the contract
    /// between MaintenanceShell (quoting) and the NSAppleScript runner.
    func testAppleScriptSourceWrapsQuotedCommandLine() {
        let line = MaintenanceShell.commandLine("/usr/sbin/purge", [])
        XCTAssertEqual(
            MaintenanceShell.appleScriptSource(commandLine: line),
            "do shell script \"'/usr/sbin/purge'\" with administrator privileges"
        )
    }

    func testAppleScriptSourceEscapesQuotesAndBackslashes() {
        // POSIX quoting keeps the double-quote literal; AppleScript then
        // needs it escaped so the string literal stays valid.
        let line = MaintenanceShell.commandLine(#"/tmp/foo"bar"#, [])
        XCTAssertEqual(
            MaintenanceShell.appleScriptSource(commandLine: line),
            #"do shell script "'/tmp/foo\"bar'" with administrator privileges"#
        )

        let withSlash = MaintenanceShell.commandLine(#"/tmp/foo\bar"#, [])
        XCTAssertEqual(
            MaintenanceShell.appleScriptSource(commandLine: withSlash),
            #"do shell script "'/tmp/foo\\bar'" with administrator privileges"#
        )
    }

    func testAuthorizationCancelDetectedByErrorNumber() {
        XCTAssertTrue(MaintenanceShell.isAuthorizationCancelled("", errorNumber: -128))
        XCTAssertFalse(MaintenanceShell.isAuthorizationCancelled("disk full", errorNumber: 1))
    }

    func testAuthorizationCancelDetectedByMessage() {
        XCTAssertTrue(MaintenanceShell.isAuthorizationCancelled("User canceled."))
        XCTAssertTrue(MaintenanceShell.isAuthorizationCancelled("1:92: execution error: User canceled. (-128)"))
        XCTAssertFalse(MaintenanceShell.isAuthorizationCancelled("Operation not permitted"))
    }
}
