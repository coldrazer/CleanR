import Foundation

/// Mach-O architecture slice names that lipo emits.
public enum BinaryArch: String, CaseIterable, Sendable, Hashable {
    case x86_64
    case arm64
    case arm64e   // Apple-internal PAC variant of arm64
    case i386     // 32-bit Intel (legacy)

    public init?(lipoName: String) {
        self.init(rawValue: lipoName)
    }

    public var lipoName: String { rawValue }
}

public struct BundleHostInfo: Sendable, Equatable {
    public let hostArch: BinaryArch

    public init(hostArch: BinaryArch) {
        self.hostArch = hostArch
    }

    /// The arch this build of CleanR is running on. Compile-time check —
    /// Rosetta-translated x86_64 builds would report x86_64 here, which is
    /// the right answer for "what code is loaded right now."
    public static var current: BundleHostInfo {
        #if arch(arm64)
        BundleHostInfo(hostArch: .arm64)
        #else
        BundleHostInfo(hostArch: .x86_64)
        #endif
    }
}

public struct AppBundleInfo: Sendable, Equatable {
    public let bundlePath: String
    public let bundleID: String
    public let isAppStore: Bool
    public let architectures: Set<BinaryArch>

    public init(
        bundlePath: String,
        bundleID: String,
        isAppStore: Bool,
        architectures: Set<BinaryArch>
    ) {
        self.bundlePath = bundlePath
        self.bundleID = bundleID
        self.isAppStore = isAppStore
        self.architectures = architectures
    }
}

public enum ThinDecision: Equatable, Sendable {
    case thin(targetArch: BinaryArch, dropping: Set<BinaryArch>)
    case skip(reason: SkipReason)

    public enum SkipReason: String, Sendable {
        case alreadyThin
        case hostArchNotPresent
        case appStoreApp
        case appleSystemApp
        case sipProtected
        case pointerAuthSlicePresent
    }
}

/// Decides whether an app bundle is safe to thin and what to drop.
///
/// Pure logic — no FileManager / Process / sysctl. The system layer in
/// CleanR is responsible for gathering the `AppBundleInfo` (walking
/// the bundle, running `lipo -info`, reading the receipt) and then
/// asking the policy. That separation lets us test the policy without
/// touching disk.
public struct UniversalBinariesPolicy: Sendable {
    public init() {}

    /// Skip order matters — most-specific first so the user sees the most
    /// relevant reason in the UI.
    public func decideThinning(
        for bundle: AppBundleInfo,
        host: BundleHostInfo
    ) -> ThinDecision {
        if bundle.bundlePath.hasPrefix("/System/") {
            return .skip(reason: .sipProtected)
        }
        if bundle.bundleID.hasPrefix("com.apple.") ||
           bundle.bundlePath.hasPrefix("/Applications/Utilities/") {
            return .skip(reason: .appleSystemApp)
        }
        if bundle.isAppStore {
            return .skip(reason: .appStoreApp)
        }
        if bundle.architectures.contains(.arm64e) {
            return .skip(reason: .pointerAuthSlicePresent)
        }
        if bundle.architectures.count <= 1 {
            return bundle.architectures.contains(host.hostArch)
                ? .skip(reason: .alreadyThin)
                : .skip(reason: .hostArchNotPresent)
        }
        guard bundle.architectures.contains(host.hostArch) else {
            return .skip(reason: .hostArchNotPresent)
        }
        let dropping = bundle.architectures.subtracting([host.hostArch])
        return .thin(targetArch: host.hostArch, dropping: dropping)
    }

    /// Rough proportional estimate. Underestimates slightly because Mach-O
    /// headers are duplicated per slice, so the universal file is somewhat
    /// larger than the sum of single-arch sizes. Good enough for "you'll
    /// save about X MB" UI.
    public static func estimatedSavings(
        originalSize: UInt64,
        originalArchCount: Int,
        droppingCount: Int
    ) -> UInt64 {
        guard originalArchCount > 0, droppingCount > 0 else { return 0 }
        return originalSize * UInt64(droppingCount) / UInt64(originalArchCount)
    }
}
