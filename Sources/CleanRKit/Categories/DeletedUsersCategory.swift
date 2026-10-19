import Foundation

/// Identifies user home folders under `/Users` that no longer correspond
/// to an active user account (i.e., residual from a deleted user).
///
/// The active-user list comes from `dscl` in the CleanR target; the
/// matching logic is pure and lives here.
public struct DeletedUsersCategory: JunkCategory {
    public init() {}

    public let scanCategory = ScanCategory.deletedUsers

    public var targets: [ScanTarget] { [] }

    /// System folders under `/Users` that are not "user folders" and must
    /// never be flagged.
    public static let systemFolders: Set<String> = ["Shared", ".localized", "Guest"]

    /// Returns true if the folder named `name` is a residual home folder —
    /// i.e., it's not a system folder, not a hidden dotfile, and doesn't
    /// appear in `activeUsers`.
    public static func isResidualHomeFolder(name: String, activeUsers: Set<String>) -> Bool {
        if systemFolders.contains(name) { return false }
        if name.hasPrefix(".") { return false }
        return !activeUsers.contains(name)
    }

    /// Parses `dscl . -list /Users` output into a set of active usernames.
    /// Drops empty lines and entries prefixed with `_` (system service accounts).
    public static func parseDsclOutput(_ output: String) -> Set<String> {
        Set(
            output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("_") }
        )
    }
}
