import XCTest
@testable import CleanRKit

final class BoundedProcessTests: XCTestCase {
    func testCapturesStdoutStderrAndExitStatus() async {
        let outcome = await BoundedProcess.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: .seconds(10))
        guard case .exited(let status, let stdout, let stderr) = outcome else {
            return XCTFail("unexpected \(outcome)")
        }
        XCTAssertEqual(status, 3)
        XCTAssertEqual(String(decoding: stdout, as: UTF8.self), "out\n")
        XCTAssertEqual(String(decoding: stderr, as: UTF8.self), "err\n")
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failureDetail, "err")
    }

    /// Output larger than the pipe buffer on both streams used to deadlock
    /// when the runner waited for exit before reading.
    func testLargeOutputOnBothStreamsDoesNotDeadlock() async {
        let outcome = await BoundedProcess.run(
            "/bin/sh", ["-c", "head -c 300000 /dev/zero >&2; head -c 300000 /dev/zero"],
            timeout: .seconds(20)
        )
        guard case .exited(0, let stdout, let stderr) = outcome else {
            return XCTFail("unexpected \(outcome)")
        }
        XCTAssertEqual(stdout.count, 300_000)
        XCTAssertEqual(stderr.count, 300_000)
    }

    func testTimeoutTerminatesTheProcess() async {
        let start = ContinuousClock.now
        let outcome = await BoundedProcess.run("/bin/sleep", ["30"], timeout: .milliseconds(300))
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    func testCancellationTerminatesTheProcess() async {
        let start = ContinuousClock.now
        let task = Task { await BoundedProcess.run("/bin/sleep", ["30"], timeout: .seconds(60)) }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    func testMissingExecutableIsALaunchFailure() async {
        let outcome = await BoundedProcess.run("/nonexistent/tool", [], timeout: .seconds(5))
        guard case .launchFailed = outcome else { return XCTFail("unexpected \(outcome)") }
    }

    /// `terminate()` is only SIGTERM. A child that traps it used to survive the
    /// whole "bounded" run — still mutating the system while the caller had
    /// already reported `.timedOut` — and its reader thread stayed parked in
    /// `readDataToEndOfFile` because the pipes never closed.
    func testChildIgnoringSigtermIsForceKilled() async {
        let marker = "cleanr_sigterm_probe"
        // Loops in the shell itself so there is no long-lived child to orphan;
        // the comment keeps the marker in argv where pgrep can see it.
        let script = "trap '' TERM # \(marker)\nwhile sleep 1; do :; done"

        let outcome = await BoundedProcess.run("/bin/sh", ["-c", script], timeout: .milliseconds(400))
        XCTAssertEqual(outcome, .timedOut)

        var survived = true
        for _ in 0..<16 {
            try? await Task.sleep(for: .milliseconds(500))
            // pgrep exits 1 when nothing matches.
            let check = await BoundedProcess.run("/usr/bin/pgrep", ["-f", marker], timeout: .seconds(5))
            if case .exited(let status, _, _) = check, status != 0 {
                survived = false
                break
            }
        }
        XCTAssertFalse(survived, "a child that traps SIGTERM outlived the bounded run")
    }

    /// The cap must bound *memory*, not reading: bailing out of the loop early
    /// would leave the child blocked on a full pipe buffer, which is the
    /// deadlock this type exists to prevent.
    func testReadBoundedKeepsTheCapAndDrainsTheRemainder() throws {
        let cap = 64 * 1024
        let payload = Data(repeating: 0x41, count: 300_000)
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "cleanr-bounded-cap.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try payload.write(to: url)

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let collected = BoundedProcess.readBounded(handle, maxBytes: cap)
        XCTAssertEqual(collected.count, cap)
        XCTAssertEqual(collected, payload.prefix(cap))
    }

    func testReadBoundedUnderTheCapReturnsEverything() throws {
        let payload = Data("hello".utf8)
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "cleanr-bounded-small.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try payload.write(to: url)

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        XCTAssertEqual(BoundedProcess.readBounded(handle, maxBytes: 1024), payload)
    }

    func testRunDoesNotStoreMoreThanTheCap() async {
        // Two streams well past the cap: the run must finish with bounded memory
        // and still drain both pipes to EOF.
        let bytes = BoundedProcess.maxOutputPerStream + 2 * 1024 * 1024
        let outcome = await BoundedProcess.run(
            "/bin/sh", ["-c", "head -c \(bytes) /dev/zero; head -c \(bytes) /dev/zero >&2"],
            timeout: .seconds(30)
        )
        guard case .exited(0, let stdout, let stderr) = outcome else {
            return XCTFail("unexpected \(outcome)")
        }
        XCTAssertEqual(stdout.count, BoundedProcess.maxOutputPerStream)
        XCTAssertEqual(stderr.count, BoundedProcess.maxOutputPerStream)
    }
}
