import XCTest
@testable import CleanRKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: - isNewer (numeric semver compare)

    func testNewerPatchMinorMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("1.9.1", than: "1.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))   // 10 > 9 numerically
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }

    func testEqualAndOlderAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.10.0"))
    }

    func testShortAndMalformedComponents() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9.0"))   // pads as 1.10.0
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "1.9.0"))   // non-numeric reads as 0
    }

    func testAppcastComparisonPrefersMarketingVersionOverBuildNumber() throws {
        let candidate = try XCTUnwrap(UpdateChecker.preferredAppcastVersion(
            shortVersion: "2.1.0",
            buildVersion: "4012"
        ))
        XCTAssertEqual(candidate, "2.1.0")
        XCTAssertFalse(UpdateChecker.isNewer(candidate, than: "2.1.0"))
    }

    // MARK: - parseLatestRelease

    func testParseValidPayload() throws {
        let json = """
        {"tag_name": "v1.10.0", "html_url": "https://github.com/coldrazer/CleanR/releases/tag/v1.10.0", "name": "1.10.0"}
        """
        let parsed = try XCTUnwrap(UpdateChecker.parseLatestRelease(Data(json.utf8)))
        XCTAssertEqual(parsed.version, "1.10.0")
        XCTAssertEqual(parsed.url.absoluteString, "https://github.com/coldrazer/CleanR/releases/tag/v1.10.0")
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("{}".utf8)))
        // Tag that is only the "v" prefix yields an empty version: reject.
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data(#"{"tag_name": "v", "html_url": "https://example.com"}"#.utf8)))
    }

    // MARK: - Homebrew detection

    func testHomebrewDetection() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "caskroom-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertTrue(UpdateChecker.isHomebrewInstall(caskroomPaths: [tmp.path]))
        XCTAssertFalse(UpdateChecker.isHomebrewInstall(caskroomPaths: ["/nonexistent/caskroom/cleanr"]))
    }

    // MARK: - Align the updater with what Homebrew can actually deliver

    func testParseCaskVersion() {
        let json = #"{"token":"cleanr","version":"1.16.0","homepage":"https://github.com/coldrazer/CleanR"}"#
        XCTAssertEqual(UpdateChecker.parseCaskVersion(Data(json.utf8)), "1.16.0")
    }

    func testParseCaskVersionRejectsGarbageAndLatest() {
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data("{}".utf8)))
        // ":latest" casks have no comparable version.
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data(#"{"version":":latest"}"#.utf8)))
    }

    func testHomebrewInstallsCheckTheCaskAPINotGitHub() {
        // A Homebrew install must compare against the official cask version
        // (what `brew upgrade` can deliver), which lags GitHub releases while
        // autobump catches up, so the popup doesn't tell brew users to run a
        // command that no-ops.
        XCTAssertEqual(UpdateChecker.updateSourceURL(isHomebrew: true), MCConstants.homebrewCaskAPI)
        XCTAssertEqual(UpdateChecker.updateSourceURL(isHomebrew: false), MCConstants.latestReleaseAPI)
    }

    func testMissingCaskRecordFallsBackToTheGitHubRelease() {
        // A tap-hosted or not-yet-merged cask 404s on formulae.brew.sh. Erroring
        // there on every launch would make brew users ignore the updater.
        XCTAssertTrue(UpdateChecker.shouldFallBackToGitHubRelease(
            isHomebrew: true, result: .failed(message: "The update source returned HTTP 404.")))
        // Only for brew, and only on failure — an answer from the cask stands.
        XCTAssertFalse(UpdateChecker.shouldFallBackToGitHubRelease(
            isHomebrew: false, result: .failed(message: "offline")))
        XCTAssertFalse(UpdateChecker.shouldFallBackToGitHubRelease(
            isHomebrew: true, result: .upToDate))
        XCTAssertFalse(UpdateChecker.shouldFallBackToGitHubRelease(
            isHomebrew: true,
            result: .updateAvailable(version: "9.9.9", url: MCConstants.releasesURL)))
    }

    func testParseStrategyFollowsTheFetchedURL() {
        // The brew fallback path fetches GitHub's release JSON, so the Accept
        // header and decoder must key off the URL, not off the install type.
        XCTAssertTrue(UpdateChecker.isCaskEndpoint(MCConstants.homebrewCaskAPI))
        XCTAssertFalse(UpdateChecker.isCaskEndpoint(MCConstants.latestReleaseAPI))
    }

    // MARK: - The release URL is opened with NSWorkspace, so it is validated

    func testReleaseURLMustBeGitHubOverHTTPS() {
        XCTAssertTrue(UpdateChecker.isSafeReleaseURL(URL(string: "https://github.com/coldrazer/CleanR/releases/tag/v1.0.0")!))
        // Same host as a *label*, different host in fact.
        XCTAssertFalse(UpdateChecker.isSafeReleaseURL(URL(string: "https://github.com.evil.test/coldrazer/CleanR")!))
        XCTAssertFalse(UpdateChecker.isSafeReleaseURL(URL(string: "http://github.com/coldrazer/CleanR")!))
        XCTAssertFalse(UpdateChecker.isSafeReleaseURL(URL(string: "file:///tmp/Release")!))
        XCTAssertFalse(UpdateChecker.isSafeReleaseURL(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(UpdateChecker.isSafeReleaseURL(URL(filePath: "/tmp/x")))
    }

    func testPayloadWithForeignReleaseURLIsRejected() {
        let json = #"{"tag_name":"v9.9.9","html_url":"https://evil.test/coldrazer/CleanR/releases/tag/v9.9.9"}"#
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data(json.utf8)))
    }

    func testEveryShippedEndpointPassesTheHostGuard() {
        XCTAssertTrue(UpdateChecker.isExpectedEndpoint(MCConstants.latestReleaseAPI))
        XCTAssertTrue(UpdateChecker.isExpectedEndpoint(MCConstants.homebrewCaskAPI))
        XCTAssertFalse(UpdateChecker.isExpectedEndpoint(MCConstants.releasesURL))
        XCTAssertFalse(UpdateChecker.isExpectedEndpoint(nil))
        XCTAssertFalse(UpdateChecker.isExpectedEndpoint(URL(string: "https://api.github.com.evil.test/x")))
    }

    // MARK: - Version parsing refuses junk instead of quietly comparing zeros

    func testVersionComponentsParsesNumericCores() {
        XCTAssertEqual(UpdateChecker.versionComponents("1.10.0").components, [1, 10, 0])
        XCTAssertTrue(UpdateChecker.versionComponents("1.10.0").isNumeric)
        XCTAssertFalse(UpdateChecker.versionComponents("1.10.0").hasPrereleaseSuffix)
        XCTAssertTrue(UpdateChecker.versionComponents("1.10.0-rc1").hasPrereleaseSuffix)
    }

    func testVersionComponentsRejectsNonNumeric() {
        for junk in ["abc", "1.x.0", "", "v", "1.0.0-beta.1.2"] {
            XCTAssertFalse(UpdateChecker.versionComponents(junk).isNumeric, junk)
        }
    }

    func testPrereleaseNeverOutranksItsOwnRelease() {
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0-rc1", than: "1.9.0"))
        // The release does beat a pre-release we're somehow running.
        XCTAssertTrue(UpdateChecker.isNewer("1.9.0", than: "1.9.0-rc1"))
        // A pre-release of a genuinely higher version still counts.
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0-rc1", than: "1.9.0"))
    }

    func testNonNumericCandidateIsNeverNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("garbage", than: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.x.5", than: "1.9.0"))
    }

    func testCaskVersionMustBeNumeric() {
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data(#"{"version":"latest"}"#.utf8)))
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data(#"{"version":"v"}"#.utf8)))
    }
}
