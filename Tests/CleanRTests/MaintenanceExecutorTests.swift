import AppKit
import XCTest
@testable import CleanR
@testable import CleanRKit

/// Issue #143: each admin task used to spawn a fresh `/usr/bin/osascript`
/// process, so macOS could not cache the password. The executor must send
/// every privileged command through one injected in-process runner.
final class MaintenanceExecutorTests: EnglishAppLanguageTestCase {

    func testAdminTaskGoesThroughPrivilegedRunner() async {
        let runner = RecordingPrivilegedRunner(
            result: .ok("purged")
        )
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        let result = await executor.execute(.freeUpRAM)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "purged")
        XCTAssertEqual(runner.commandLines, [
            MaintenanceShell.commandLine("/usr/sbin/purge", [])
        ])
    }

    func testSequentialAdminTasksReuseTheSameRunner() async {
        let runner = RecordingPrivilegedRunner(result: .ok(""))
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        _ = await executor.execute(.freeUpRAM)
        _ = await executor.execute(.freeUpPurgeableSpace)
        _ = await executor.execute(.runMaintenanceScripts)

        XCTAssertEqual(runner.commandLines, [
            MaintenanceShell.commandLine("/usr/sbin/purge", []),
            MaintenanceShell.commandLine("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "1"]),
            MaintenanceShell.commandLine("/usr/sbin/periodic", ["daily", "weekly", "monthly"]),
        ])
    }

    func testUnprivilegedTaskDoesNotTouchPrivilegedRunner() async {
        let runner = RecordingPrivilegedRunner(result: .ok("unused"))
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        _ = await executor.execute(.flushDNSCache)

        XCTAssertTrue(
            runner.commandLines.isEmpty,
            "non-admin tasks must not trigger the password prompt"
        )
    }

    func testMissingBinaryDoesNotPromptForAdmin() async {
        let runner = RecordingPrivilegedRunner(result: .ok("should not run"))
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in false }
        )

        let result = await executor.execute(.runMaintenanceScripts)

        XCTAssertFalse(result.success)
        XCTAssertTrue(runner.commandLines.isEmpty, "password prompt must not appear for a missing tool")
        XCTAssertEqual(
            result.error,
            "/usr/sbin/periodic isn't available on this version of macOS, so this task can't run."
        )
    }

    func testUserCancelIsMappedToFriendlyMessage() async {
        let runner = RecordingPrivilegedRunner(
            result: .failed("User canceled.", errorNumber: -128)
        )
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        let result = await executor.execute(.freeUpRAM)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Cancelled — administrator access was not granted.")
    }

    func testAdminFailureStripsAppleScriptWrapper() async {
        let runner = RecordingPrivilegedRunner(
            result: .failed("1:92: execution error: Operation not permitted (1)")
        )
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        let result = await executor.execute(.freeUpRAM)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Operation not permitted")
    }

    /// `NSAppleScript` is documented as main-thread-only. The production
    /// runner uses a dedicated serial queue so long `periodic` jobs don't
    /// freeze the UI. This proves `do shell script` (no admin) still works
    /// on that kind of queue — same API the runner uses.
    func testDoShellScriptWorksOffMainThread() async {
        let result: (String?, NSDictionary?) = await withCheckedContinuation { continuation in
            DispatchQueue(label: "sai.test.applescript").async {
                var error: NSDictionary?
                let script = NSAppleScript(source: "do shell script \"echo ok\"")
                let descriptor = script?.executeAndReturnError(&error)
                continuation.resume(returning: (descriptor?.stringValue, error))
            }
        }
        XCTAssertNil(result.1, "off-main do shell script failed: \(result.1 ?? [:])")
        XCTAssertEqual(result.0, "ok")
    }

    func testGeneratedAdminScriptsCompile() {
        let commands = MaintenanceTask.allCases.compactMap { task -> String? in
            guard task.requiresAdmin, let command = task.systemCommand else { return nil }
            return MaintenanceShell.commandLine(command.executable, command.arguments)
        }
        XCTAssertEqual(commands.count, 5, "every admin task with a systemCommand should compile")
        for command in commands {
            let source = MaintenanceShell.appleScriptSource(commandLine: command)
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            XCTAssertNotNil(script, source)
            XCTAssertTrue(
                script?.compileAndReturnError(&error) == true,
                "compile failed for \(command): \(error ?? [:])"
            )
        }
    }
}

/// Records every privileged command line. `@unchecked Sendable` because the
/// executor is an actor and tests await it sequentially — no concurrent
/// mutation.
final class RecordingPrivilegedRunner: PrivilegedShellRunning, @unchecked Sendable {
    private(set) var calls: [(executable: String, arguments: [String])] = []
    var result: PrivilegedShellResult

    init(result: PrivilegedShellResult) {
        self.result = result
    }

    /// Same rendered lines the real runner would execute, so assertions stay
    /// readable while the API itself only accepts structured argv.
    var commandLines: [String] {
        calls.map { MaintenanceShell.commandLine($0.executable, $0.arguments) }
    }

    func run(executable: String, arguments: [String]) async -> PrivilegedShellResult {
        calls.append((executable, arguments))
        return result
    }
}
