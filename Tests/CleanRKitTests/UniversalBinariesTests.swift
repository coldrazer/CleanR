import XCTest
import Foundation
@testable import CleanRKit

final class UniversalBinariesTests: XCTestCase {

    // MARK: - parseLipoOutput — fat file format

    func testParseFatFile() {
        let output = "Architectures in the fat file: /Applications/Safari.app/Contents/MacOS/Safari are: x86_64 arm64"
        XCTAssertEqual(UniversalBinariesCategory.parseLipoOutput(output), ["x86_64", "arm64"])
    }

    func testParseFatFileWithThreeArchs() {
        let output = "Architectures in the fat file: /path are: x86_64 arm64 arm64e"
        XCTAssertEqual(UniversalBinariesCategory.parseLipoOutput(output), ["x86_64", "arm64", "arm64e"])
    }

    func testParseFatFileWithTrailingNewline() {
        let output = "Architectures in the fat file: /path are: x86_64 arm64\n"
        XCTAssertEqual(UniversalBinariesCategory.parseLipoOutput(output), ["x86_64", "arm64"])
    }

    // MARK: - parseLipoOutput — non-fat format

    func testParseNonFatFile() {
        let output = "Non-fat file: /Applications/Foo.app/Contents/MacOS/Foo is architecture: arm64"
        XCTAssertEqual(UniversalBinariesCategory.parseLipoOutput(output), ["arm64"])
    }

    func testParseNonFatX86() {
        let output = "Non-fat file: /path is architecture: x86_64"
        XCTAssertEqual(UniversalBinariesCategory.parseLipoOutput(output), ["x86_64"])
    }

    // MARK: - parseLipoOutput — invalid input

    func testParseUnrecognizedFormat() {
        XCTAssertNil(UniversalBinariesCategory.parseLipoOutput("nothing useful here"))
    }

    func testParseEmptyInput() {
        XCTAssertNil(UniversalBinariesCategory.parseLipoOutput(""))
    }

    // MARK: - hasRedundantSlice

    func testRedundantWhenArmAndX86OnArm() {
        XCTAssertTrue(UniversalBinariesCategory.hasRedundantSlice(
            architectures: ["x86_64", "arm64"], hostArch: "arm64"
        ))
    }

    func testRedundantWhenX86AndArmOnX86() {
        XCTAssertTrue(UniversalBinariesCategory.hasRedundantSlice(
            architectures: ["x86_64", "arm64"], hostArch: "x86_64"
        ))
    }

    func testNotRedundantWhenSingleArch() {
        XCTAssertFalse(UniversalBinariesCategory.hasRedundantSlice(
            architectures: ["arm64"], hostArch: "arm64"
        ))
    }

    func testNotRedundantWhenOnlyHostArch() {
        // Truly fat-but-only-host: shouldn't be considered redundant (only 1 arch counted)
        XCTAssertFalse(UniversalBinariesCategory.hasRedundantSlice(
            architectures: ["arm64"], hostArch: "arm64"
        ))
    }

    func testRedundantWithThreeArchs() {
        XCTAssertTrue(UniversalBinariesCategory.hasRedundantSlice(
            architectures: ["x86_64", "arm64", "arm64e"], hostArch: "arm64"
        ))
    }
}
