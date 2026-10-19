import Foundation
import CleanRKit

/// System-side wrapper around `DeletedUsersCategory`'s pure logic.
/// Reads active usernames via `dscl`, compares to `/Users` contents using
/// the pure `isResidualHomeFolder` decision function.
public enum DeletedUsersScanner {

    public static func scanForDeletedUserFolders() -> [FileItem] {
        let fm = FileManager.default
        let usersDir = URL(filePath: "/Users")

        guard let userFolders = try? fm.contentsOfDirectory(
            at: usersDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        let activeUsers = readActiveUsernames()

        // `dscl` failing, being sandboxed away, or genuinely returning
        // nothing is indistinguishable from "no active users" — and an
        // empty `activeUsers` set would make `isResidualHomeFolder` say
        // yes to EVERY folder under /Users, including the account that's
        // running this scan right now. A real Mac always has at least one
        // active user, so treat empty as "couldn't determine" and refuse
        // to flag anything rather than risk offering someone's own home
        // folder for deletion.
        guard !activeUsers.isEmpty else { return [] }

        // Defense in depth on top of the dscl-based check: never flag the
        // account actually running this process, no matter what dscl said.
        let currentUser = NSUserName()

        var results: [FileItem] = []
        for folder in userFolders {
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let name = folder.lastPathComponent
            guard name != currentUser,
                  DeletedUsersCategory.isResidualHomeFolder(name: name, activeUsers: activeUsers)
            else { continue }

            let size = directorySize(folder)
            results.append(FileItem(
                url: folder,
                name: name,
                size: size,
                allocatedSize: size,
                isDirectory: true
            ))
        }
        return results
    }

    private static func readActiveUsernames() -> Set<String> {
        // BoundedProcess drains both streams while `dscl` runs. Waiting for exit
        // first, and leaving the stderr pipe unread entirely, deadlocks once the
        // child writes past the pipe buffer.
        do {
            let result = try BoundedProcess.runSynchronously(
                "/usr/bin/dscl", [".", "-list", "/Users"]
            )
            guard result.status == 0 else { return Set() }
            let output = String(decoding: result.stdout, as: UTF8.self)
            return DeletedUsersCategory.parseDsclOutput(output)
        } catch {
            return Set()
        }
    }

    private static func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let v = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += UInt64(v?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
