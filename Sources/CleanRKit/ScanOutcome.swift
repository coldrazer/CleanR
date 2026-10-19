import Foundation

/// Result of a `TargetedScanner` run that, unlike a bare `[FileItem]`,
/// distinguishes "found nothing" from "couldn't read because access was
/// denied." `~/.Trash` without Full Disk Access enumerates as empty —
/// the EPERM is swallowed by `NSDirectoryEnumerator` — so a plain item
/// count can't tell the two apart. Carrying the denied target paths lets
/// the UI show a "Grant Full Disk Access" prompt instead of a misleading
/// "Trash is empty."
public struct ScanOutcome: Sendable {
    public let items: [FileItem]
    /// Target roots that exist but whose contents this process is not
    /// permitted to read (EPERM/EACCES — TCC denial or POSIX permissions).
    public let permissionDeniedPaths: [URL]

    public init(items: [FileItem], permissionDeniedPaths: [URL] = []) {
        self.items = items
        self.permissionDeniedPaths = permissionDeniedPaths
    }

    public var permissionDenied: Bool { !permissionDeniedPaths.isEmpty }
}
