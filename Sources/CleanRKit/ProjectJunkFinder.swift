import Foundation

/// A directory entry fed into `ProjectJunkFinder`. The live scanner builds these
/// from the filesystem; tests inject fixtures so the logic stays pure.
public struct ProjectTreeNode: Equatable, Sendable {
    public let path: String
    public let bytes: UInt64
    public let modified: Date?
    public let childNames: [String]
    /// Lines of this folder's `.gitignore`, when it has one.
    public let gitignoreLines: [String]

    public init(
        path: String,
        bytes: UInt64,
        modified: Date?,
        childNames: [String],
        gitignoreLines: [String] = []
    ) {
        self.path = path
        self.bytes = bytes
        self.modified = modified
        self.childNames = childNames
        self.gitignoreLines = gitignoreLines
    }

    public var name: String { (path as NSString).lastPathComponent }
}

public enum ProjectJunkKind: String, Equatable, Sendable {
    case nodeModules
    case nextBuild
    case dist
    case rustTarget
    case pythonVenv
    case gradleBuild
    case mavenBuild
    case cocoaPods
}

public struct ProjectJunkItem: Equatable, Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let projectPath: String
    public let kind: ProjectJunkKind
    public let bytes: UInt64
    public let projectModified: Date?

    public init(
        path: String,
        projectPath: String,
        kind: ProjectJunkKind,
        bytes: UInt64,
        projectModified: Date?
    ) {
        self.path = path
        self.projectPath = projectPath
        self.kind = kind
        self.bytes = bytes
        self.projectModified = projectModified
    }
}

/// Finds regenerable build/dependency folders inside user-chosen project roots.
/// Never returns the project folder itself — only the junk directory inside it.
public enum ProjectJunkFinder {
    /// Nothing is auto-selected; the user must opt in to each folder.
    public static let defaultSelection: Set<String> = []

    private static let nodeMarkers: Set<String> = ["package.json"]
    private static let rustMarkers: Set<String> = ["Cargo.toml"]
    private static let pythonMarkers: Set<String> = [
        "pyproject.toml", "requirements.txt", "setup.py", "Pipfile",
    ]
    private static let gradleMarkers: Set<String> = [
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
    ]
    private static let mavenMarkers: Set<String> = ["pom.xml"]
    private static let podsMarkers: Set<String> = ["Podfile"]

    public static func find(nodes: [ProjectTreeNode]) -> [ProjectJunkItem] {
        let byPath = Dictionary(nodes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var candidates: [ProjectJunkItem] = []

        for node in nodes {
            guard let kind = kind(for: node, byPath: byPath) else { continue }
            let projectPath = (node.path as NSString).deletingLastPathComponent
            let project = byPath[projectPath]
            candidates.append(
                ProjectJunkItem(
                    path: node.path,
                    projectPath: projectPath,
                    kind: kind,
                    bytes: node.bytes,
                    projectModified: project?.modified
                )
            )
        }

        let outermost = candidates.filter { item in
            !candidates.contains { other in
                other.path != item.path && item.path.hasPrefix(other.path + "/")
            }
        }

        return outermost.sorted { lhs, rhs in
            let left = lhs.projectModified ?? .distantFuture
            let right = rhs.projectModified ?? .distantFuture
            if left != right { return left < right }
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.path < rhs.path
        }
    }

    private static func kind(
        for node: ProjectTreeNode,
        byPath: [String: ProjectTreeNode]
    ) -> ProjectJunkKind? {
        let parentPath = (node.path as NSString).deletingLastPathComponent
        guard let parent = byPath[parentPath] else { return nil }
        let siblings = Set(parent.childNames)

        switch node.name {
        case "node_modules" where !siblings.isDisjoint(with: nodeMarkers):
            return .nodeModules
        case ".next" where !siblings.isDisjoint(with: nodeMarkers):
            return .nextBuild
        case "dist" where !siblings.isDisjoint(with: nodeMarkers):
            // Some projects commit dist/ (GitHub Actions ship it), so only
            // list it when git is told to ignore it.
            return isGitIgnored(node, byPath: byPath) ? .dist : nil
        case "target":
            if !siblings.isDisjoint(with: rustMarkers) { return .rustTarget }
            if !siblings.isDisjoint(with: mavenMarkers) { return .mavenBuild }
            return nil
        case "build" where !siblings.isDisjoint(with: gradleMarkers):
            return .gradleBuild
        case ".venv", "venv":
            // pyvenv.cfg is written by every venv/virtualenv; a folder that
            // merely happens to be called "venv" does not have one.
            guard node.childNames.contains("pyvenv.cfg") else { return nil }
            return siblings.isDisjoint(with: pythonMarkers) ? nil : .pythonVenv
        case "Pods" where !siblings.isDisjoint(with: podsMarkers):
            // Many iOS repos commit Pods/ on purpose.
            return isGitIgnored(node, byPath: byPath) ? .cocoaPods : nil
        default:
            return nil
        }
    }

    /// Whether a `.gitignore` in the project, or in a folder above it up to
    /// the repository root, names this folder. Simple line matching only:
    /// `dist`, `dist/`, `/dist`, `**/dist`, `dist/*`, `dist/**`. A pattern
    /// with a leading slash only applies to the folder holding that file.
    /// Anything unmatched counts as not ignored, so the folder is left alone.
    static func isGitIgnored(_ node: ProjectTreeNode, byPath: [String: ProjectTreeNode]) -> Bool {
        var dirPath = (node.path as NSString).deletingLastPathComponent
        var isProjectFolder = true
        while let dir = byPath[dirPath] {
            for line in dir.gitignoreLines
            where gitignoreLine(line, names: node.name, anchoredHere: isProjectFolder) {
                return true
            }
            // A .gitignore above the repository root does not apply.
            if dir.childNames.contains(".git") { break }
            let parent = (dirPath as NSString).deletingLastPathComponent
            if parent == dirPath { break }
            dirPath = parent
            isProjectFolder = false
        }
        return false
    }

    static func gitignoreLine(_ rawLine: String, names name: String, anchoredHere: Bool) -> Bool {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("!") else { return false }
        for suffix in ["/**", "/*", "/"] where line.hasSuffix(suffix) {
            line.removeLast(suffix.count)
            break
        }
        if line.hasPrefix("**/") {
            line.removeFirst(3)
        } else if line.hasPrefix("/") {
            guard anchoredHere else { return false }
            line.removeFirst()
        }
        return line == name
    }
}
