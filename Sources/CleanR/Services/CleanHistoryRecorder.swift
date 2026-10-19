import Foundation
import CleanRKit

/// Persists whole-clean sessions so the user can Restore in one click.
public enum CleanHistoryRecorder {
    /// Override in tests. Under XCTest it defaults to a temp file so the
    /// suite's real trash cleans never land in the developer's own history.
    nonisolated(unsafe) public static var fileURL: URL = NSClassFromString("XCTestCase") != nil
        ? FileManager.default.temporaryDirectory
            .appending(path: "cleanr-test-clean-history-\(ProcessInfo.processInfo.processIdentifier).json")
        : MCConstants.cleanHistoryFile
    /// Override in tests; the user's Trash in production.
    nonisolated(unsafe) public static var trashRoot: URL = MCConstants.userTrash

    /// Serializes load-modify-save so two cleans finishing together can't
    /// drop each other's session.
    private static let lock = NSLock()

    public static func load() -> [CleanHistorySession] {
        lock.withLock { unlockedLoad() }
    }

    private static func unlockedLoad(now: Date = Date()) -> [CleanHistorySession] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? CleanHistoryStore.decode(data)
        else { return [] }
        return CleanHistoryStore.pruned(sessions, now: now)
    }

    public static func record(
        trashedItems: [CleaningEngine.TrashedItem],
        now: Date = Date()
    ) {
        guard !trashedItems.isEmpty else { return }
        let kept = trashedItems.prefix(CleanHistoryStore.maxItemsPerSession)
        let omitted = trashedItems.count - kept.count
        let session = CleanHistorySession(
            id: UUID(),
            date: now,
            items: kept.map {
                let trashPath = $0.trashURL.path(percentEncoded: false)
                return CleanHistoryItem(
                    id: UUID(),
                    originalPath: $0.originalURL.path(percentEncoded: false),
                    trashPath: trashPath,
                    bytes: $0.bytes,
                    trashFileID: fileID(atPath: trashPath)
                )
            },
            omittedCount: omitted > 0 ? omitted : nil
        )
        lock.withLock {
            unlockedSave(CleanHistoryStore.adding(session, to: unlockedLoad(now: now), now: now))
        }
    }

    public static func save(_ sessions: [CleanHistorySession]) {
        lock.withLock { unlockedSave(sessions) }
    }

    /// Forgets every session. Files already in the Trash are not touched.
    public static func clear() {
        lock.withLock { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Writes owner-only (0600, the file lists cleaned paths) and atomically:
    /// the data goes to a temp file created with those permissions, which is
    /// then renamed over the old history.
    private static func unlockedSave(_ sessions: [CleanHistorySession]) {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? CleanHistoryStore.encode(sessions) else { return }
        preserveUnreadableHistoryFile()
        let tmp = dir.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            .path(percentEncoded: false)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return }
        if !writeAll(fd, data) || fsync(fd) != 0 {
            close(fd)
            unlink(tmp)
            return
        }
        close(fd)
        // Without the sync the rename can land before the bytes do: a power
        // loss then leaves a zero-length history file, i.e. an empty Restore
        // list for a clean that actually happened.
        if rename(tmp, url.path(percentEncoded: false)) != 0 {
            unlink(tmp)
        }
    }

    /// `write(2)` may accept only part of the buffer, and the history file is
    /// capped at 5,000 entries — roughly a megabyte — so a single call is not a
    /// complete write.
    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var remaining = data[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            if written == 0 { return false }
            remaining = remaining.dropFirst(written)
        }
        return true
    }

    /// Rename an existing history file that no longer decodes out of the way
    /// before overwriting it. `unlockedLoad` reads a corrupt file as "no
    /// history", so without this the next clean would save a one-session file
    /// over a list that may still describe dozens of restorable items — and the
    /// bytes would be the only evidence of where those items went.
    private static func preserveUnreadableHistoryFile() {
        let url = fileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url),
              (try? CleanHistoryStore.decode(data)) == nil
        else { return }
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: url, to: backup)
    }

    /// Puts a session's items back where they were. Each item is validated
    /// first, never overwrites anything (`moveItem` fails on an existing
    /// destination), and only items that actually moved are counted and
    /// dropped from the history. Blocking: call off the main thread.
    @discardableResult
    public static func restore(_ session: CleanHistorySession) -> CleanHistoryRestoreSummary {
        let fm = FileManager.default
        let root = trashRoot.path(percentEncoded: false)
        let uid = getuid()
        var summary = CleanHistoryRestoreSummary()

        for item in session.items {
            let recordedID = item.trashFileID
            let isSafe = CleanHistoryRestore.isInsideTrash(item.trashPath, trashRoot: root, uid: uid)
                && CleanHistoryRestore.isRestorableDestination(item.originalPath, trashRoot: root, uid: uid)
                && recordedID != nil && fileID(atPath: item.trashPath) == recordedID
                && (try? SafetyGuard().validatePath(URL(filePath: item.originalPath), excludedFolders: [])) != nil
            let action = CleanHistoryRestore.plan(
                item: item,
                trashExists: fileID(atPath: item.trashPath) != nil,
                originalExists: fileID(atPath: item.originalPath) != nil,
                isSafe: isSafe
            )
            switch action {
            case .skippedEmptied:
                summary.emptied += 1
            case .skippedReappeared:
                summary.reappeared += 1
            case .skippedUnsafe:
                summary.failed += 1
            case .restore(let from, let to):
                let destination = URL(filePath: to)
                do {
                    try fm.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: URL(filePath: from), to: destination)
                    summary.restored += 1
                    summary.restoredItemIDs.insert(item.id)
                } catch {
                    summary.failed += 1
                }
            }
        }

        if !summary.restoredItemIDs.isEmpty {
            lock.withLock {
                unlockedSave(CleanHistoryStore.removing(itemIDs: summary.restoredItemIDs, from: unlockedLoad()))
            }
        }
        return summary
    }

    /// Inode of the item at `path` without following a final symlink, or nil
    /// when nothing is there.
    static func fileID(atPath path: String) -> UInt64? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return UInt64(info.st_ino)
    }
}
