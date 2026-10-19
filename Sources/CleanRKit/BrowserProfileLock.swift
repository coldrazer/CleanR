import Darwin
import Foundation

/// Detects a browser holding its profile open, independent of the app's name
/// or install location. Used together with the running-apps check: if either
/// says "in use", CleanR never deletes.
public enum BrowserProfileLock {
    /// Chromium creates a `SingletonLock` symlink in the user data folder
    /// while running and removes it on exit. The target never exists on disk,
    /// so this checks the link itself (lstat), not what it points to. A stale
    /// link after a crash also reads as "in use", which errs on the safe side.
    public static func chromiumUserDataIsLocked(_ userDataDirectory: URL) -> Bool {
        let lock = userDataDirectory.appending(path: "SingletonLock").path(percentEncoded: false)
        var info = stat()
        return lstat(lock, &info) == 0
    }

    /// Firefox keeps `.parentlock` in every profile and holds a POSIX record
    /// lock on it while running. The file stays after exit, so its presence
    /// means nothing; ask the kernel whether another process holds the lock
    /// (F_GETLK only queries, it never takes the lock).
    public static func firefoxProfileIsLocked(_ profileDirectory: URL) -> Bool {
        let lockPath = profileDirectory.appending(path: ".parentlock").path(percentEncoded: false)
        let fd = open(lockPath, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var query = flock()
        query.l_type = Int16(F_WRLCK)
        query.l_whence = Int16(SEEK_SET)
        query.l_start = 0
        query.l_len = 0
        guard fcntl(fd, F_GETLK, &query) == 0 else {
            // Could not ask: assume in use rather than risk deleting.
            return true
        }
        return query.l_type != Int16(F_UNLCK)
    }
}
