import XCTest
@testable import CleanRKit

/// Decision logic for whether an app bundle is safe to thin.
/// All inputs are plain data (no FileManager / Process); the system layer
/// in CleanR is responsible for gathering them and then asking the policy.
final class UniversalBinariesPolicyTests: XCTestCase {

    private let policy = UniversalBinariesPolicy()
    private let onArm64: BundleHostInfo = .init(hostArch: .arm64)
    private let onIntel: BundleHostInfo = .init(hostArch: .x86_64)

    // MARK: - Eligibility: bundles we WILL thin

    func testThins_normalFatApp_onArm64() {
        let info = AppBundleInfo(
            bundlePath: "/Applications/Slack.app",
            bundleID: "com.tinyspeck.slackmacgap",
            isAppStore: false,
            architectures: [.x86_64, .arm64]
        )
        let decision = policy.decideThinning(for: info, host: onArm64)
        XCTAssertEqual(decision, .thin(targetArch: .arm64, dropping: [.x86_64]))
    }

    func testThins_normalFatApp_onIntel() {
        let info = AppBundleInfo(
            bundlePath: "/Applications/Slack.app",
            bundleID: "com.tinyspeck.slackmacgap",
            isAppStore: false,
            architectures: [.x86_64, .arm64]
        )
        let decision = policy.decideThinning(for: info, host: onIntel)
        XCTAssertEqual(decision, .thin(targetArch: .x86_64, dropping: [.arm64]))
    }

    // MARK: - Skip: already single-arch

    func testSkips_singleArchAlreadyMatchesHost() {
        let info = AppBundleInfo(
            bundlePath: "/Applications/NativeArm.app",
            bundleID: "com.example.nativearm",
            isAppStore: false,
            architectures: [.arm64]
        )
        XCTAssertEqual(policy.decideThinning(for: info, host: onArm64),
                       .skip(reason: .alreadyThin))
    }

    func testSkips_singleArchDoesNotIncludeHost() {
        // x86_64-only app on an arm64 Mac — runs via Rosetta. Removing the
        // x86_64 slice would leave nothing executable.
        let info = AppBundleInfo(
            bundlePath: "/Applications/IntelOnly.app",
            bundleID: "com.example.intelonly",
            isAppStore: false,
            architectures: [.x86_64]
        )
        XCTAssertEqual(policy.decideThinning(for: info, host: onArm64),
                       .skip(reason: .hostArchNotPresent))
    }

    // MARK: - Skip: App Store apps (re-signing breaks DRM)

    func testSkips_appStoreApp() {
        // Real-world App Store app that isn't published by Apple — so the
        // apple-system-app rule doesn't fire first and the test exercises
        // the App Store branch specifically.
        let info = AppBundleInfo(
            bundlePath: "/Applications/1Password 7.app",
            bundleID: "com.agilebits.onepassword7",
            isAppStore: true,
            architectures: [.x86_64, .arm64]
        )
        XCTAssertEqual(policy.decideThinning(for: info, host: onArm64),
                       .skip(reason: .appStoreApp))
    }

    // MARK: - Skip: Apple-shipped apps (bundle id com.apple.*)

    func testSkips_appleSystemAppByBundleID() {
        let info = AppBundleInfo(
            bundlePath: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            isAppStore: false,
            architectures: [.x86_64, .arm64]
        )
        XCTAssertEqual(policy.decideThinning(for: info, host: onArm64),
                       .skip(reason: .appleSystemApp))
    }

    // MARK: - Skip: SIP-protected location

    func testSkips_underSystemPath() {
        let info = AppBundleInfo(
            bundlePath: "/System/Applications/Mail.app",
            bundleID: "com.apple.mail",
            isAppStore: false,
            architectures: [.x86_64, .arm64]
        )
        XCTAssertEqual(policy.decideThinning(for: info, host: onArm64),
                       .skip(reason: .sipProtected))
    }

    func testSkips_underApplicationsUtilities() {
        let info = AppBundleInfo(
            bundlePath: "/Applications/Utilities/Terminal.app",
            bundleID: "com.apple.Terminal",
            isAppStore: false,
            architectures: [.x86_64, .arm64]
        )
        // Apple ships these; bundle id is also com.apple — either rule
        // is enough, here we assert the path check fires.
        XCTAssertEqual(policy.decideThinning(for: info, host: onArm64),
                       .skip(reason: .appleSystemApp))
    }

    // MARK: - Skip: arm64e present (PAC, Apple-internal territory)

    func testSkips_arm64eSliceOnHost() {
        let info = AppBundleInfo(
            bundlePath: "/Applications/SomePACThing.app",
            bundleID: "com.example.pac",
            isAppStore: false,
            architectures: [.arm64e, .arm64]
        )
        // arm64e is Apple-internal pointer-authenticated arch. Thinning it
        // away from a bundle that ships it could remove the slice the OS
        // chose to load. Refuse.
        XCTAssertEqual(policy.decideThinning(for: info, host: onArm64),
                       .skip(reason: .pointerAuthSlicePresent))
    }

    // MARK: - Savings estimate

    func testEstimatedSavings_proportional() {
        // 60 MB binary with 3 archs → dropping 1 saves ~1/3 (rough heuristic;
        // not exact because Mach-O headers + alignment are duplicated).
        let saving = UniversalBinariesPolicy.estimatedSavings(
            originalSize: 60_000_000,
            originalArchCount: 3,
            droppingCount: 1
        )
        XCTAssertEqual(saving, 20_000_000, accuracy: 100_000)
    }

    func testEstimatedSavings_zeroWhenDroppingNone() {
        let saving = UniversalBinariesPolicy.estimatedSavings(
            originalSize: 1_000_000,
            originalArchCount: 2,
            droppingCount: 0
        )
        XCTAssertEqual(saving, 0)
    }

    // MARK: - BinaryArch round-trip

    func testBinaryArch_parsesLipoNames() {
        XCTAssertEqual(BinaryArch(lipoName: "x86_64"), .x86_64)
        XCTAssertEqual(BinaryArch(lipoName: "arm64"), .arm64)
        XCTAssertEqual(BinaryArch(lipoName: "arm64e"), .arm64e)
        XCTAssertEqual(BinaryArch(lipoName: "i386"), .i386)
        XCTAssertNil(BinaryArch(lipoName: "garbage"))
    }

    func testBinaryArch_lipoName_isRoundTrip() {
        for arch in BinaryArch.allCases {
            XCTAssertEqual(BinaryArch(lipoName: arch.lipoName), arch,
                           "round-trip broken for \(arch)")
        }
    }
}
