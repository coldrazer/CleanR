import XCTest
@testable import CleanRKit
import CleanRTestSupport

final class MachOWalkerTests: XCTestCase {

    private var bundleURL: URL!

    override func setUpWithError() throws {
        let raw = FileManager.default.temporaryDirectory
            .appending(path: "Walker-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        bundleURL = URL(filePath: raw.resolvingSymlinksInPath().path(percentEncoded: false))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleURL)
    }

    private func placeFatBinary(at dest: URL) throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let built = try UniversalBinaryFixture.build(at: dest)
        try XCTSkipUnless(built, "cc not available")
    }

    private func writeNonMachOFile(at dest: URL, _ content: String = "junk") throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: dest)
    }

    /// Canonical path string. URL identity comparisons are flaky because
    /// macOS's `/var → /private/var` symlink + Foundation's behavior in
    /// directory enumeration result in different prefixes for the same
    /// on-disk file.
    private func canon(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    private func walk() -> [String] {
        MachOWalker.fatBinaries(in: bundleURL).map(canon)
    }

    // MARK: - Tests

    func testFindsMainExecutable() throws {
        let exec = bundleURL.appending(path: "Contents/MacOS/MainApp")
        try placeFatBinary(at: exec)
        XCTAssertEqual(walk(), [canon(exec)])
    }

    func testFindsFatBinariesInFrameworksAndXPCServices() throws {
        let main = bundleURL.appending(path: "Contents/MacOS/MainApp")
        let fw = bundleURL.appending(path: "Contents/Frameworks/Helper.framework/Versions/A/Helper")
        let xpc = bundleURL.appending(path: "Contents/XPCServices/Worker.xpc/Contents/MacOS/Worker")
        try placeFatBinary(at: main)
        try placeFatBinary(at: fw)
        try placeFatBinary(at: xpc)
        XCTAssertEqual(Set(walk()), Set([main, fw, xpc].map(canon)))
    }

    func testIgnoresNonMachOFiles() throws {
        try placeFatBinary(at: bundleURL.appending(path: "Contents/MacOS/MainApp"))
        try writeNonMachOFile(at: bundleURL.appending(path: "Contents/Info.plist"),
                              "<?xml version='1.0'?><plist/>")
        try writeNonMachOFile(at: bundleURL.appending(path: "Contents/Resources/strings.txt"))
        XCTAssertEqual(walk().count, 1,
                       "only the Mach-O should be returned, not plist or txt")
    }

    func testIgnoresSymlinks() throws {
        let real = bundleURL.appending(path: "Contents/Frameworks/F.framework/Versions/A/F")
        try placeFatBinary(at: real)
        // Canonical Versions/Current → A symlink.
        let parent = bundleURL.appending(path: "Contents/Frameworks/F.framework/Versions")
        let currentLink = parent.appending(path: "Current")
        try FileManager.default.createSymbolicLink(
            atPath: currentLink.path(percentEncoded: false),
            withDestinationPath: "A"
        )

        let found = walk()
        XCTAssertEqual(found.count, 1,
                       "Versions/Current symlink chain must not produce a duplicate")
        XCTAssertEqual(found.first, canon(real))
    }

    func testDeduplicatesHardLinks() throws {
        let original = bundleURL.appending(path: "Contents/MacOS/Main")
        try placeFatBinary(at: original)

        let linkURL = bundleURL.appending(path: "Contents/Resources/CopyOfMain")
        try FileManager.default.createDirectory(
            at: linkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.linkItem(at: original, to: linkURL)
        XCTAssertEqual(walk().count, 1,
                       "hard links to same inode must be deduped")
    }

    func testReturnsEmptyForBundleWithNoMachOFiles() throws {
        try writeNonMachOFile(at: bundleURL.appending(path: "Contents/Info.plist"), "<plist/>")
        XCTAssertTrue(walk().isEmpty)
    }

    func testReturnsEmptyForMissingBundle() {
        let bogus = URL(filePath: "/this/path/does/not/exist.app")
        XCTAssertTrue(MachOWalker.fatBinaries(in: bogus).isEmpty)
    }

    // MARK: - Magic-byte detection

    func testMagicByteCheck_acceptsFatMagic() throws {
        let url = bundleURL.appending(path: "fat.bin")
        let data = Data([0xCA, 0xFE, 0xBA, 0xBE] + Array(repeating: UInt8(0), count: 100))
        try writeNonMachOFile(at: url)
        try data.write(to: url)
        XCTAssertTrue(MachOWalker.isFatMachO(url: url))
    }

    func testMagicByteCheck_rejectsRegularExecutable() throws {
        let url = bundleURL.appending(path: "single.bin")
        // 0xFEEDFACE is the Mach-O magic for a single-arch binary, NOT fat.
        let data = Data([0xFE, 0xED, 0xFA, 0xCE] + Array(repeating: UInt8(0), count: 100))
        try writeNonMachOFile(at: url)
        try data.write(to: url)
        XCTAssertFalse(MachOWalker.isFatMachO(url: url),
                       "single-arch Mach-O magic 0xFEEDFACE must not be flagged as fat")
    }
}
