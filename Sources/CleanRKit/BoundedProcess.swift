import Foundation
import OSLog

private let logger = Logger(subsystem: MCConstants.bundleIdentifier, category: "BoundedProcess")

/// Runs a command with a time budget, terminating it on timeout or when the
/// calling task is cancelled.
///
/// Both pipes are drained while the process runs: waiting for exit before
/// reading deadlocks once output passes the ~64KB pipe buffer, because the
/// child blocks writing while we block waiting.
public enum BoundedProcess {
    public enum Outcome: Equatable, Sendable {
        case exited(status: Int32, stdout: Data, stderr: Data)
        case launchFailed(String)
        case timedOut
        case cancelled
    }

    /// Hard ceiling on how much of each stream we keep in memory.
    ///
    /// `readDataToEndOfFile` allocates whatever the child writes, and the
    /// children here are third-party CLIs on paths we accept but do not own
    /// (docker, simctl, lsof). One chatty or hostile tool printing gigabytes
    /// would take the app down with it. Past the cap the stream is still drained
    /// — see `readBounded` — so the child never blocks on a full pipe.
    static var maxOutputPerStream: Int { 16 * 1024 * 1024 }

    /// How long to wait for a SIGTERM to land before escalating.
    static var sigkillGrace: DispatchTimeInterval { .milliseconds(1500) }

    public static func run(_ executable: String, _ arguments: [String], timeout: Duration) async -> Outcome {
        let handle = Handle()
        do {
            return try await withTimeout(timeout) {
                try await Task.detached { try handle.run(executable, arguments) }.value
            }
        } catch is TimeoutError {
            handle.terminate()
            return .timedOut
        } catch is CancellationError {
            handle.terminate()
            return .cancelled
        } catch {
            return .launchFailed(error.localizedDescription)
        }
    }

    /// Synchronous variant for runners that are not in an async context.
    ///
    /// Both streams are drained *while* the child runs. Calling
    /// `waitUntilExit()` and reading the pipes afterwards deadlocks as soon as
    /// output exceeds the ~64KB pipe buffer: the child blocks writing, we block
    /// waiting for it to exit, and neither side can ever proceed. Several older
    /// runners in this app had exactly that shape, and the commands they call
    /// routinely exceed 64KB (`diskutil verifyVolume` on a large APFS volume,
    /// `lsof +D` on a busy bundle), so this was an availability bug rather than a
    /// theoretical one.
    ///
    /// - Throws: whatever `Process.run()` throws if the executable cannot launch.
    public static func runSynchronously(
        _ executable: String,
        _ arguments: [String]
    ) throws -> (status: Int32, stdout: Data, stderr: Data) {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        let cap = maxOutputPerStream
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            stderrBox.data = readBounded(err.fileHandleForReading, maxBytes: cap)
        }
        let stdout = readBounded(out.fileHandleForReading, maxBytes: cap)
        process.waitUntilExit()
        group.wait()
        return (process.terminationStatus, stdout, stderrBox.data)
    }

    private final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var stopped = false

        func run(_ executable: String, _ arguments: [String]) throws -> Outcome {
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            lock.lock()
            if stopped {
                lock.unlock()
                return .cancelled
            }
            do {
                try process.run()
            } catch {
                lock.unlock()
                throw error
            }
            self.process = process
            lock.unlock()

            let cap = BoundedProcess.maxOutputPerStream
            let stderr = DataBox()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                stderr.data = BoundedProcess.readBounded(err.fileHandleForReading, maxBytes: cap)
            }
            let stdout = BoundedProcess.readBounded(out.fileHandleForReading, maxBytes: cap)
            process.waitUntilExit()
            group.wait()
            return .exited(status: process.terminationStatus, stdout: stdout, stderr: stderr.data)
        }

        /// Stops the child, escalating to SIGKILL if it ignores SIGTERM.
        ///
        /// `Process.terminate()` is only SIGTERM. A child that traps or blocks
        /// it survived the "bounded" run entirely: the caller had already
        /// reported `.timedOut` and moved on while the process kept mutating the
        /// system, and the detached reader stayed parked in
        /// `readDataToEndOfFile` forever because its pipes never closed. Every
        /// timed-out run leaked a thread until the pool exhausted.
        func terminate() {
            lock.lock()
            stopped = true
            let process = self.process
            lock.unlock()
            guard let process, process.isRunning else { return }

            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + BoundedProcess.sigkillGrace) {
                // Re-check rather than signalling unconditionally: the pid may
                // already have been reaped and recycled by the time we get here.
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    /// Reads `handle` to end of file, keeping at most `maxBytes` of it.
    ///
    /// Everything past the cap is still read and thrown away rather than left in
    /// the pipe: stopping early would leave the child blocked writing into a
    /// full buffer while we wait for it to exit, which is the deadlock this type
    /// exists to prevent. Draining is therefore not optional, only storing is.
    static func readBounded(_ handle: FileHandle, maxBytes: Int) -> Data {
        let chunkSize = 64 * 1024
        var collected = Data()
        var truncated = false

        while true {
            let next: Data?
            do {
                next = try handle.read(upToCount: chunkSize)
            } catch {
                break
            }
            guard let next, !next.isEmpty else { break }
            if collected.count < maxBytes {
                let room = maxBytes - collected.count
                if next.count <= room {
                    collected.append(next)
                } else {
                    collected.append(next.prefix(room))
                    truncated = true
                }
            } else {
                truncated = true
            }
        }

        if truncated {
            logger.notice(
                "Bounded process output truncated at \(maxBytes, privacy: .public) bytes"
            )
        }
        return collected
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}

public extension BoundedProcess.Outcome {
    var succeeded: Bool {
        if case .exited(0, _, _) = self { return true }
        return false
    }

    var stdoutText: String {
        if case .exited(_, let stdout, _) = self { return String(decoding: stdout, as: UTF8.self) }
        return ""
    }

    var stdoutData: Data {
        if case .exited(_, let stdout, _) = self { return stdout }
        return Data()
    }

    /// First non-empty stderr line (or stdout when stderr is empty), for a
    /// short failure detail. Empty for timeouts and cancellations.
    var failureDetail: String {
        switch self {
        case .exited(_, let stdout, let stderr):
            let text = String(decoding: stderr.isEmpty ? stdout : stderr, as: UTF8.self)
            return text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
        case .launchFailed(let message):
            return message
        case .timedOut, .cancelled:
            return ""
        }
    }
}
