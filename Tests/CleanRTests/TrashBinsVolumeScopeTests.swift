import XCTest
@testable import CleanR

/// `.Trashes` on a mounted volume is emptied permanently by the Trash Bins
/// module, so which volumes qualify is a data-loss boundary, not a nicety.
final class TrashBinsVolumeScopeTests: XCTestCase {

    func testLocalBlockFilesystemsQualify() {
        for fs in ["apfs", "hfs", "hfsplus", "msdos", "exfat", "udf", "ntfs"] {
            XCTAssertTrue(
                TrashBinsModule.hasEmptiableTrashFilesystem(fstype: fs, isReadOnly: false),
                "\(fs) is a disk attached to this Mac"
            )
        }
    }

    func testCaseInsensitiveMatch() {
        XCTAssertTrue(TrashBinsModule.hasEmptiableTrashFilesystem(fstype: "APFS", isReadOnly: false))
    }

    /// Network shares mount under /Volumes and carry a `.Trashes` too — but
    /// those are other people's deleted files, on another machine.
    func testNetworkAndSpecialFilesystemsAreExcluded() {
        for fs in ["smbfs", "afpfs", "nfs", "webdav", "NFS", "sftpfs", "fuse", "cd9660", "tmpfs"] {
            XCTAssertFalse(
                TrashBinsModule.hasEmptiableTrashFilesystem(fstype: fs, isReadOnly: false),
                "\(fs) must never be emptied by us"
            )
        }
    }

    func testReadOnlyVolumeIsExcluded() {
        XCTAssertFalse(TrashBinsModule.hasEmptiableTrashFilesystem(fstype: "apfs", isReadOnly: true))
    }

    /// `statfs` against paths that really exist on any Apple Silicon Mac: the
    /// data volume is a writable local APFS mount, `/` is the sealed,
    /// read-only system snapshot.
    func testStatfsOnRealVolumes() {
        XCTAssertTrue(TrashBinsModule.hasEmptiableTrashFilesystem(URL(filePath: "/Users/Shared")))
        XCTAssertFalse(TrashBinsModule.hasEmptiableTrashFilesystem(URL(filePath: "/")))
    }

    func testStatfsOfAnUnmountedPathFailsClosed() {
        XCTAssertFalse(
            TrashBinsModule.hasEmptiableTrashFilesystem(
                URL(filePath: "/Volumes/definitely-not-mounted-cleanr-test")
            )
        )
    }
}
