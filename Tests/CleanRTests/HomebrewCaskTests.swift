import XCTest
import Foundation

/// Guards issue #147: Homebrew deprecated `url … verified:` (brew#23280).
/// The release workflow copies this template into `coldrazer/homebrew-cleanr`,
/// so a stale `verified:` here resurfaces as a `brew update` warning.
final class HomebrewCaskTests: XCTestCase {

    private var caskSource: String {
        get throws {
            let url = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Casks/cleanr.rb")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testCaskHasNoDeprecatedVerifiedParameter() throws {
        let src = try caskSource
        // Match the Homebrew url kwarg form (`verified: "…"`). Single-quoted
        // values are unused in this cask; official homebrew/cask omits it.
        let deprecated = src.range(
            of: #"\bverified:\s*""#,
            options: .regularExpression
        )
        XCTAssertNil(
            deprecated,
            "Casks/cleanr.rb must not use the deprecated url verified: parameter (issue #147)"
        )
    }

    func testCaskUrlPointsAtGitHubReleaseDMG() throws {
        let src = try caskSource
        XCTAssertTrue(
            src.contains("url \"https://github.com/coldrazer/CleanR/releases/download/v#{version}/CleanR-#{version}.dmg\""),
            "Casks/cleanr.rb must download the GitHub release DMG"
        )
    }

    func testCaskDeclaresRequiredStanzas() throws {
        let src = try caskSource
        for needle in ["cask \"cleanr\"", "version ", "sha256 ", "homepage ", "app \"CleanR.app\""] {
            XCTAssertTrue(src.contains(needle), "Casks/cleanr.rb missing \(needle)")
        }
    }
}
