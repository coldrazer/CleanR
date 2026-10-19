import Foundation
import AppKit

public final class PermissionManager: Sendable {
    public static let shared = PermissionManager()

    private init() {}

    public func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Live Full Disk Access probe: the system TCC database is readable
    /// only with the grant, and it always exists, so a successful read is
    /// a reliable yes and a permission error is a reliable no. No file is
    /// modified and nothing leaves the machine.
    public func hasFullDiskAccess() -> Bool {
        let tccPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileManager.default.isReadableFile(atPath: tccPath)
            && (try? Data(contentsOf: URL(fileURLWithPath: tccPath), options: [.mappedIfSafe])) != nil
    }
}
