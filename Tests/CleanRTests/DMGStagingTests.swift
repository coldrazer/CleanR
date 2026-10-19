import XCTest
import Foundation

/// Guards issue #149: the release DMG must be a drag-to-Applications installer
/// (symlink to /Applications) and must not ship build-only junk like
/// entitlements.plist (used only for codesign, not by end users).
final class DMGStagingTests: XCTestCase {

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var prepareScript: URL {
        repoRoot.appending(path: "scripts/prepare-dmg-staging.sh")
    }

    func testPrepareScriptExistsAndIsExecutable() {
        var isDir: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: prepareScript.path(percentEncoded: false), isDirectory: &isDir),
            "scripts/prepare-dmg-staging.sh must exist (issue #149)"
        )
        XCTAssertFalse(isDir.boolValue)
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: prepareScript.path(percentEncoded: false)),
            "prepare-dmg-staging.sh must be executable"
        )
    }

    func testStagingGetsApplicationsSymlinkAndDropsBuildJunk() throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appending(path: "cleanr-dmg-staging-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }

        try fm.createDirectory(at: staging.appending(path: "CleanR.app/Contents"), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: staging.appending(path: "entitlements.plist"))
        try Data("zip".utf8).write(to: staging.appending(path: "CleanR-notarize.zip"))
        try Data("keep".utf8).write(to: staging.appending(path: "CleanR.app/Contents/Info.plist"))

        let result = try runPrepare(staging: staging)
        XCTAssertEqual(result.status, 0, "prepare failed: \(result.stderr)\n\(result.stdout)")

        let appsLink = staging.appending(path: "Applications")
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: appsLink.path(percentEncoded: false), isDirectory: &isDir))
        let attrs = try fm.attributesOfItem(atPath: appsLink.path(percentEncoded: false))
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(
            try fm.destinationOfSymbolicLink(atPath: appsLink.path(percentEncoded: false)),
            "/Applications"
        )

        XCTAssertFalse(
            fm.fileExists(atPath: staging.appending(path: "entitlements.plist").path(percentEncoded: false)),
            "entitlements.plist is codesign-only and must not ship in the DMG"
        )
        XCTAssertFalse(
            fm.fileExists(atPath: staging.appending(path: "CleanR-notarize.zip").path(percentEncoded: false)),
            "notarize zip leftovers must not ship in the DMG"
        )
        XCTAssertTrue(
            fm.fileExists(atPath: staging.appending(path: "CleanR.app/Contents/Info.plist").path(percentEncoded: false)),
            "the app bundle must remain"
        )
    }

    func testBuildDmgScriptUsesPrepareHelperAndKeepsEntitlementsOutOfStaging() throws {
        let buildScript = try String(
            contentsOf: repoRoot.appending(path: "scripts/build-dmg.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(
            buildScript.contains("prepare-dmg-staging.sh"),
            "build-dmg.sh must invoke prepare-dmg-staging.sh before hdiutil (issue #149)"
        )
        XCTAssertTrue(
            buildScript.contains("APP_ZIP=\".build/${APP_NAME}-notarize.zip\""),
            "notarize zip must live under .build/, not DMG_DIR"
        )
        // Entitlements must live outside the DMG staging folder so a forgotten
        // cleanup cannot reintroduce the loose plist into the image.
        XCTAssertFalse(
            buildScript.contains("\"${DMG_DIR}/entitlements.plist\""),
            "entitlements.plist must not be written under DMG_DIR"
        )
        XCTAssertTrue(
            buildScript.contains("ENTITLEMENTS_FILE=\".build/entitlements.plist\""),
            "codesign entitlements must live under .build/"
        )
        // Ordering: prepare must appear before hdiutil create.
        let prepareRange = buildScript.range(of: "prepare-dmg-staging.sh")!
        let hdiutilRange = buildScript.range(of: "hdiutil create")!
        XCTAssertLessThan(
            prepareRange.lowerBound,
            hdiutilRange.lowerBound,
            "prepare-dmg-staging.sh must run before hdiutil create"
        )
    }

    private func runPrepare(staging: URL) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = [prepareScript.path(percentEncoded: false), staging.path(percentEncoded: false)]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
