import Foundation
import CleanRKit

public struct TrashBinsModule: ScanModule {
    public let id = "trash_bins"
    public var name: String { L10n.tr("废纸篓", "Trash Bins", "Корзины") }
    public let category = ModuleCategory.cleanup

    private let scanner = TargetedScanner()

    public init() {}

    public func scan() async -> [ScanResult] {
        await scanReportingPermissions().results
    }

    /// Same scan as `scan()`, but also reports whether the Trash came back
    /// empty because Full Disk Access is missing (macOS blocks reading
    /// `~/.Trash` without it, and the enumerator silently yields nothing).
    /// The Trash view uses this to show a "Grant Full Disk Access" prompt
    /// instead of a false "Trash is empty."
    public func scanReportingPermissions() async -> (results: [ScanResult], permissionDenied: Bool) {
        let outcome = await scanner.scanReportingPermissions(targets: Self.targets())
        guard !outcome.items.isEmpty else {
            return ([], outcome.permissionDenied)
        }
        let results = [ScanResult(category: .trashBins, items: outcome.items)]
            .filteringUncleanable()
        return (results, outcome.permissionDenied)
    }

    private static func targets() -> [ScanTarget] {
        var targets: [ScanTarget] = [
            // Main user trash
            ScanTarget(path: MCConstants.userTrash, recursive: true),
        ]

        let fm = FileManager.default
        if let volumes = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey],
            options: [.skipHiddenVolumes]
        ) {
            for volume in volumes where hasEmptiableTrashFilesystem(volume) {
                let trashURL = volume.appending(path: ".Trashes")
                if fm.fileExists(atPath: trashURL.path(percentEncoded: false)) {
                    targets.append(ScanTarget(path: trashURL, recursive: true))
                }
            }
        }
        return targets
    }

    /// Filesystems whose `.Trashes` holds files deleted off a disk physically
    /// attached to this Mac.
    static let localTrashFilesystems: Set<String> = [
        "apfs", "hfs", "hfsplus", "msdos", "exfat", "udf", "ntfs",
    ]

    static func hasEmptiableTrashFilesystem(fstype: String, isReadOnly: Bool) -> Bool {
        !isReadOnly && localTrashFilesystems.contains(fstype.lowercased())
    }

    /// A volume's `.Trashes` contains the files deleted *on that volume*, and
    /// emptying it is permanent, so the scope has to match what "empty the
    /// trash" means: a disk plugged into this machine.
    ///
    /// `mountedVolumeURLs` also returns SMB, AFP, NFS and WebDAV mounts, and
    /// each of those carries a `.Trashes` belonging to everyone who uses the
    /// share — deleting their recoverable files over the network is data loss,
    /// not cleanup. The `volumeIsInternal` / `volumeIsEjectable` flags can't
    /// separate a NAS mount from a USB SSD (both read false/false), so the
    /// filesystem type from `statfs` is what distinguishes them.
    static func hasEmptiableTrashFilesystem(_ volume: URL) -> Bool {
        var status = statfs()
        guard statfs(volume.path(percentEncoded: false), &status) == 0 else { return false }
        let fstype = withUnsafeBytes(of: &status.f_fstypename) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let readOnly = status.f_flags & UInt32(MNT_RDONLY) != 0
        return hasEmptiableTrashFilesystem(fstype: fstype, isReadOnly: readOnly)
    }
}
