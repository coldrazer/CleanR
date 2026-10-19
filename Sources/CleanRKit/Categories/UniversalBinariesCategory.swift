import Foundation

/// Identifies universal Mach-O binaries that contain a redundant architecture
/// slice (e.g. an x86_64 slice on an arm64 Mac, or vice versa).
///
/// The Mach-O inspection happens by shelling out to `lipo -info` in the
/// CleanR target; the *interpretation* of that output is pure and lives
/// here so it can be unit-tested.
public struct UniversalBinariesCategory: JunkCategory {
    public init() {}

    public let scanCategory = ScanCategory.universalBinaries

    public var targets: [ScanTarget] { [] }

    /// Parses one line of `lipo -info` output into an array of architecture names.
    ///
    /// Formats lipo can emit:
    ///   - "Architectures in the fat file: <path> are: x86_64 arm64"
    ///   - "Non-fat file: <path> is architecture: arm64"
    ///
    /// Returns `nil` if the output doesn't match either format.
    public static func parseLipoOutput(_ output: String) -> [String]? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "are:") {
            let archPart = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = archPart.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts
        }
        if let range = trimmed.range(of: "is architecture:") {
            let arch = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return arch.isEmpty ? nil : [arch]
        }
        return nil
    }

    /// Returns `true` if the binary at `architectures` has a redundant slice
    /// relative to the host architecture — i.e. it's fat AND it contains
    /// the host's "other" architecture.
    public static func hasRedundantSlice(architectures: [String], hostArch: String) -> Bool {
        guard architectures.count > 1 else { return false }
        let redundant = hostArch == "arm64" ? "x86_64" : "arm64"
        return architectures.contains(redundant)
    }
}
