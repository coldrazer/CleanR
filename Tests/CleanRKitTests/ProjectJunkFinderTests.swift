import XCTest
@testable import CleanRKit

final class ProjectJunkFinderTests: XCTestCase {
    func testFindsRegenerableFoldersAndNeverTheProjectItself() {
        let root = "/Users/me/Code"
        let nodes = [
            dir("\(root)/web", children: ["package.json", "node_modules", ".next", "dist", "src", ".gitignore"],
                gitignore: ["node_modules", "dist/"]),
            dir("\(root)/web/node_modules", bytes: 500, children: ["left-pad"]),
            dir("\(root)/web/.next", bytes: 80, children: ["cache"]),
            dir("\(root)/web/dist", bytes: 20, children: ["index.js"]),
            dir("\(root)/api", children: ["Cargo.toml", "target", "src"]),
            dir("\(root)/api/target", bytes: 900, children: ["debug"]),
            dir("\(root)/py", children: ["pyproject.toml", ".venv"]),
            dir("\(root)/py/.venv", bytes: 300, children: ["bin", "pyvenv.cfg"]),
            dir("\(root)/android", children: ["build.gradle", "build"]),
            dir("\(root)/android/build", bytes: 40, children: ["outputs"]),
            dir("\(root)/java", children: ["pom.xml", "target"]),
            dir("\(root)/java/target", bytes: 15, children: ["classes"]),
            dir("\(root)/ios", children: ["Podfile", "Pods", ".gitignore"], gitignore: ["Pods/"]),
            dir("\(root)/ios/Pods", bytes: 200, children: ["Headers"]),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        let paths = Set(found.map(\.path))
        XCTAssertTrue(paths.contains("\(root)/web/node_modules"))
        XCTAssertTrue(paths.contains("\(root)/web/.next"))
        XCTAssertTrue(paths.contains("\(root)/web/dist"))
        XCTAssertTrue(paths.contains("\(root)/api/target"))
        XCTAssertTrue(paths.contains("\(root)/py/.venv"))
        XCTAssertTrue(paths.contains("\(root)/android/build"))
        XCTAssertTrue(paths.contains("\(root)/java/target"))
        XCTAssertTrue(paths.contains("\(root)/ios/Pods"))
        XCTAssertFalse(paths.contains("\(root)/web"))
        XCTAssertFalse(paths.contains("\(root)/api"))
        XCTAssertEqual(found.first { $0.path.hasSuffix("node_modules") }?.kind, .nodeModules)
        XCTAssertEqual(found.first { $0.path.hasSuffix("/api/target") }?.kind, .rustTarget)
        XCTAssertEqual(found.first { $0.path.hasSuffix("/java/target") }?.kind, .mavenBuild)
        XCTAssertEqual(found.first { $0.path.hasSuffix("/android/build") }?.kind, .gradleBuild)
    }

    func testIgnoresAmbiguousFoldersWithoutAProjectMarker() {
        let nodes = [
            dir("/tmp/notes", children: ["target", "build", "dist", "venv", "Pods"]),
            dir("/tmp/notes/target", bytes: 10, children: []),
            dir("/tmp/notes/build", bytes: 10, children: []),
            dir("/tmp/notes/dist", bytes: 10, children: []),
            dir("/tmp/notes/venv", bytes: 10, children: []),
            dir("/tmp/notes/Pods", bytes: 10, children: []),
        ]
        XCTAssertTrue(ProjectJunkFinder.find(nodes: nodes).isEmpty)
    }

    func testKeepsOnlyTheOutermostJunkDirectory() {
        let nodes = [
            dir("/Code/app", children: ["package.json", "node_modules"]),
            dir("/Code/app/node_modules", bytes: 100, children: ["pkg"]),
            dir("/Code/app/node_modules/pkg", children: ["node_modules"]),
            dir("/Code/app/node_modules/pkg/node_modules", bytes: 5, children: []),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        XCTAssertEqual(found.map(\.path), ["/Code/app/node_modules"])
    }

    func testStaleProjectsSortFirstAndNothingIsPreselected() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 9_000)
        let nodes = [
            dir("/Code/new", modified: newer, children: ["package.json", "node_modules"]),
            dir("/Code/new/node_modules", bytes: 10, children: []),
            dir("/Code/old", modified: older, children: ["package.json", "node_modules"]),
            dir("/Code/old/node_modules", bytes: 1, children: []),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        XCTAssertEqual(found.map(\.projectPath), ["/Code/old", "/Code/new"])
        XCTAssertTrue(ProjectJunkFinder.defaultSelection.isEmpty)
    }

    func testPythonVenvRequiresAPythonMarker() {
        let nodes = [
            dir("/Code/tool", children: ["requirements.txt", "venv"]),
            dir("/Code/tool/venv", bytes: 12, children: ["bin", "pyvenv.cfg"]),
            dir("/Code/docs", children: ["requirements.txt", "venv"]),
            dir("/Code/docs/venv", bytes: 12, children: ["notes.md"]),
        ]
        let found = ProjectJunkFinder.find(nodes: nodes)
        XCTAssertEqual(found.map(\.kind), [.pythonVenv])
        XCTAssertEqual(found[0].projectPath, "/Code/tool")
    }

    // MARK: - dist and Pods need a .gitignore entry

    /// GitHub Actions and some libraries commit dist/, and many iOS repos
    /// commit Pods/. Without a .gitignore entry they are someone's source.
    func testCommittedDistAndPodsAreNeverListed() {
        let nodes = [
            dir("/Code/action", children: ["package.json", "dist", ".git"]),
            dir("/Code/action/dist", bytes: 50, children: ["index.js"]),
            dir("/Code/app", children: ["Podfile", "Pods", ".gitignore", ".git"], gitignore: ["build/", "*.xcuserstate"]),
            dir("/Code/app/Pods", bytes: 70, children: ["Headers"]),
        ]
        XCTAssertTrue(ProjectJunkFinder.find(nodes: nodes).isEmpty)
    }

    func testIgnoredDistAndPodsAreListed() {
        for line in ["dist", "dist/", "/dist", "**/dist", "dist/*", "dist/**", "  dist/  "] {
            let nodes = [
                dir("/Code/web", children: ["package.json", "dist", ".gitignore"], gitignore: ["# build output", line]),
                dir("/Code/web/dist", bytes: 5, children: ["main.js"]),
            ]
            XCTAssertEqual(ProjectJunkFinder.find(nodes: nodes).map(\.kind), [.dist], "pattern \"\(line)\"")
        }
        let pods = [
            dir("/Code/ios", children: ["Podfile", "Pods", ".gitignore"], gitignore: ["/Pods/"]),
            dir("/Code/ios/Pods", bytes: 5, children: ["Headers"]),
        ]
        XCTAssertEqual(ProjectJunkFinder.find(nodes: pods).map(\.kind), [.cocoaPods])
    }

    /// Monorepos usually ignore dist once, at the repository root.
    func testRepositoryRootGitignoreCoversNestedPackages() {
        let nodes = [
            dir("/Code/mono", children: ["package.json", "packages", ".gitignore", ".git"], gitignore: ["dist"]),
            dir("/Code/mono/packages", children: ["ui"]),
            dir("/Code/mono/packages/ui", children: ["package.json", "dist"]),
            dir("/Code/mono/packages/ui/dist", bytes: 5, children: ["index.js"]),
        ]
        XCTAssertEqual(ProjectJunkFinder.find(nodes: nodes).map(\.path), ["/Code/mono/packages/ui/dist"])
    }

    /// `/dist` only means the dist folder next to that .gitignore.
    func testAnchoredPatternDoesNotCoverNestedPackages() {
        let nodes = [
            dir("/Code/mono", children: ["package.json", "packages", ".gitignore", ".git"], gitignore: ["/dist"]),
            dir("/Code/mono/packages", children: ["ui"]),
            dir("/Code/mono/packages/ui", children: ["package.json", "dist"]),
            dir("/Code/mono/packages/ui/dist", bytes: 5, children: ["index.js"]),
        ]
        XCTAssertTrue(ProjectJunkFinder.find(nodes: nodes).isEmpty)
    }

    /// A .gitignore outside the project's repository says nothing about it.
    func testGitignoreAboveTheRepositoryRootIsIgnored() {
        let nodes = [
            dir("/Code", children: ["lib", ".gitignore"], gitignore: ["dist"]),
            dir("/Code/lib", children: ["package.json", "dist", ".git"]),
            dir("/Code/lib/dist", bytes: 5, children: ["index.js"]),
        ]
        XCTAssertTrue(ProjectJunkFinder.find(nodes: nodes).isEmpty)
    }

    func testNegatedAndCommentedLinesDoNotCount() {
        for line in ["!dist", "# dist", "dist/index.js", "distribution", "src/dist"] {
            XCTAssertFalse(
                ProjectJunkFinder.gitignoreLine(line, names: "dist", anchoredHere: true),
                "pattern \"\(line)\""
            )
        }
    }

    private func dir(
        _ path: String,
        bytes: UInt64 = 0,
        modified: Date? = nil,
        children: [String],
        gitignore: [String] = []
    ) -> ProjectTreeNode {
        ProjectTreeNode(
            path: path, bytes: bytes, modified: modified,
            childNames: children, gitignoreLines: gitignore
        )
    }
}
