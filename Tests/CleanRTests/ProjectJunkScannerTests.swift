import XCTest
import CleanRKit
@testable import CleanR

/// Runs the real scanner on a folder tree on disk. The finder's unit tests
/// feed it hand-built paths, which hid that directory URLs from the file
/// walker end in "/" and so never matched their parent.
final class ProjectJunkScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "project-junk-\(UUID().uuidString)", directoryHint: .isDirectory)
        for dir in [
            "web/node_modules/left-pad", "web/node_modules/.pnpm", "web/.next/cache", "web/dist",
            "action/dist", "py/.venv/bin", "api/target/debug", "tool/build",
        ] {
            try FileManager.default.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
        }
        write("web/package.json")
        write("web/.gitignore", "node_modules\n/dist\n")
        write("action/package.json")
        write("action/dist/index.js")
        write("py/requirements.txt")
        write("py/.venv/pyvenv.cfg")
        write("api/Cargo.toml")
        write("tool/build/deploy.sh")
        write("web/node_modules/left-pad/index.js", Data(count: 100_000))
        write("web/node_modules/.pnpm/store", Data(count: 400_000))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFindsRegenerableFoldersOnDisk() {
        let names = ProjectJunkScanner().scan(root: root)
            .map { $0.path.replacingOccurrences(of: ProjectJunkScanner.normalized(root) + "/", with: "") }
            .sorted()
        // action/dist is committed (no .gitignore) and tool/build has no
        // build-system marker beside it, so neither is listed.
        XCTAssertEqual(names, ["api/target", "py/.venv", "web/.next", "web/dist", "web/node_modules"])
    }

    func testSizeIncludesHiddenFilesLikeThePnpmStore() {
        let nodeModules = ProjectJunkScanner().scan(root: root).first { $0.path.hasSuffix("/node_modules") }
        XCTAssertGreaterThanOrEqual(nodeModules?.bytes ?? 0, 500_000)
    }

    func testReportsProgressUpToOne() {
        let seen = LockedValues()
        _ = ProjectJunkScanner().scan(root: root) { seen.append($0) }
        XCTAssertEqual(seen.values.first, ProjectJunkScanner.walkShare)
        XCTAssertEqual(seen.values.last ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(seen.values, seen.values.sorted())
    }

    func testResultsUseTheProjectJunkCategoryAndAreNeverPreselected() {
        let results = ProjectJunkScanner().asScanResults(ProjectJunkScanner().scan(root: root))
        XCTAssertEqual(results.map(\.category), [.projectJunk])
        XCTAssertFalse(results[0].autoSelect)
    }

    func testRefusesSystemAndLibraryRoots() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertFalse(ProjectJunkScanner.isAllowedRoot(URL(filePath: "/")))
        XCTAssertFalse(ProjectJunkScanner.isAllowedRoot(URL(filePath: "/System/Library")))
        XCTAssertFalse(ProjectJunkScanner.isAllowedRoot(URL(filePath: "/Applications")))
        XCTAssertFalse(ProjectJunkScanner.isAllowedRoot(home.appending(path: "Library/Application Support")))
        XCTAssertTrue(ProjectJunkScanner.isAllowedRoot(home.appending(path: "Code")))
        XCTAssertTrue(ProjectJunkScanner().scan(root: URL(filePath: "/System")).isEmpty)
    }

    private func write(_ relative: String, _ data: Data = Data()) {
        FileManager.default.createFile(atPath: root.appending(path: relative).path(percentEncoded: false), contents: data)
    }

    private func write(_ relative: String, _ text: String) {
        write(relative, Data(text.utf8))
    }
}

private final class LockedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    var values: [Double] { lock.withLock { storage } }
    func append(_ value: Double) { lock.withLock { storage.append(value) } }
}
