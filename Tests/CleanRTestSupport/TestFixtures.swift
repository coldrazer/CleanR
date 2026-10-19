import Foundation
import CleanRKit
import XCTest

/// Test fixture helpers — build synthetic filesystem trees in temp directories
/// so tests don't touch the user's real home.
///
/// All helpers clean up after themselves on the way out (success or failure).
public enum TestFixtures {

    // MARK: - Temp dir + fake home

    /// Creates a uniquely-named temp directory, runs `body`, then removes it.
    public static func withTempDir<T>(
        _ body: (URL) throws -> T
    ) rethrows -> T {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cleanr-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    public static func withTempDir<T>(
        _ body: (URL) async throws -> T
    ) async rethrows -> T {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cleanr-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await body(url)
    }

    /// Creates a synthetic home directory mirroring the macOS `~/Library/...`
    /// structure under a temp prefix. Runs `body(home)`, then cleans up.
    /// Returns whatever `body` returns.
    public static func withTempHome<T>(
        _ body: (FakeHome) throws -> T
    ) rethrows -> T {
        try withTempDir { tmpRoot in
            let fakeHome = FakeHome(root: tmpRoot)
            try fakeHome.createDirectoryTree()
            return try body(fakeHome)
        }
    }

    public static func withTempHome<T>(
        _ body: (FakeHome) async throws -> T
    ) async rethrows -> T {
        try await withTempDir { tmpRoot in
            let fakeHome = FakeHome(root: tmpRoot)
            try fakeHome.createDirectoryTree()
            return try await body(fakeHome)
        }
    }

    // MARK: - Fake plist on disk

    /// Writes a plist (as binary format) at the given URL. Parent dirs are created.
    public static func writePlist(
        _ contents: [String: Any],
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents, format: .binary, options: 0
        )
        try data.write(to: url)
    }

    /// Writes corrupt bytes that will fail PropertyListSerialization.
    public static func writeCorruptPlist(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00, 0xFF, 0x00, 0xAB]).write(to: url)
    }

    // MARK: - Fake .app bundle

    /// Creates a minimal `.app` bundle (just Contents/Info.plist) at `url`.
    public static func writeFakeApp(
        at url: URL,
        bundleIdentifier: String,
        name: String,
        version: String = "1.0"
    ) throws {
        let contents = url.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try writePlist([
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
        ], to: contents.appending(path: "Info.plist"))
    }

    // MARK: - Fake file with specific size + age

    /// Creates an empty file padded to `size` bytes, with optional modification date.
    @discardableResult
    public static func writeFile(
        at url: URL,
        size: Int = 0,
        modificationDate: Date? = nil,
        contents: Data? = nil
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = contents ?? Data(count: size)
        try data.write(to: url)
        if let modDate = modificationDate {
            try FileManager.default.setAttributes(
                [.modificationDate: modDate],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }
        return url
    }
}

// MARK: - FakeHome

/// A synthetic `~/Library/...` directory tree, rooted in a temp dir.
/// Mirrors the subset of paths CleanR cares about.
public final class FakeHome {
    public let root: URL

    public var library: URL { root.appending(path: "Library") }
    public var caches: URL { library.appending(path: "Caches") }
    public var logs: URL { library.appending(path: "Logs") }
    public var preferences: URL { library.appending(path: "Preferences") }
    public var appSupport: URL { library.appending(path: "Application Support") }
    public var containers: URL { library.appending(path: "Containers") }
    public var launchAgents: URL { library.appending(path: "LaunchAgents") }
    public var downloads: URL { root.appending(path: "Downloads") }
    public var trash: URL { root.appending(path: ".Trash") }
    public var documents: URL { root.appending(path: "Documents") }

    init(root: URL) { self.root = root }

    func createDirectoryTree() throws {
        for dir in [library, caches, logs, preferences, appSupport,
                    containers, launchAgents, downloads, trash, documents] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
