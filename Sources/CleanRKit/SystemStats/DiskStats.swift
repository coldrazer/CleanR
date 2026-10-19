import Foundation

/// Volume usage summary from `URLResourceValues` or `statfs`.
public struct DiskUsage: Sendable, Equatable {
    public let total: UInt64
    public let free: UInt64

    public init(total: UInt64, free: UInt64) {
        self.total = total
        self.free = min(free, total) // sanity: free can never exceed total
    }

    /// Build from raw `statfs` fields, where capacities are reported as block
    /// counts that must be scaled by the filesystem block size. The menu-bar
    /// collector uses `statfs("/")` for the live disk number specifically
    /// because it never consults the purgeable-space / Spotlight machinery that
    /// `.volumeAvailableCapacityForImportantUsageKey` does (issue #78 hang).
    public static func fromStatfs(blocks: UInt64, availableBlocks: UInt64, blockSize: UInt64) -> DiskUsage {
        DiskUsage(total: blocks &* blockSize, free: availableBlocks &* blockSize)
    }

    public var used: UInt64 { total >= free ? total - free : 0 }

    /// Fraction of the volume that's in use (0…1).
    public var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}
