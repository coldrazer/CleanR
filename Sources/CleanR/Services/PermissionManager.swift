import Foundation
import AppKit

public final class PermissionManager: Sendable {
    public static let shared = PermissionManager()

    private init() {}

    public func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
