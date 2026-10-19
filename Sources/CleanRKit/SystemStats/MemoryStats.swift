import Foundation

/// Page-counted memory state from `host_statistics64(HOST_VM_INFO64)`.
/// Counts are in PAGES, not bytes — multiply by page size to get bytes.
public struct VMStatistics: Sendable, Equatable {
    public let activeCount: UInt64
    public let inactiveCount: UInt64
    public let wireCount: UInt64
    public let freeCount: UInt64
    public let compressorPageCount: UInt64

    public init(
        activeCount: UInt64,
        inactiveCount: UInt64,
        wireCount: UInt64,
        freeCount: UInt64,
        compressorPageCount: UInt64
    ) {
        self.activeCount = activeCount
        self.inactiveCount = inactiveCount
        self.wireCount = wireCount
        self.freeCount = freeCount
        self.compressorPageCount = compressorPageCount
    }
}

/// Memory pressure summary derived from `VMStatistics`.
/// "Used" matches the definition Activity Monitor displays: active + wired
/// + compressed. Inactive and free pages are considered reclaimable.
public struct MemoryUsage: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let swapUsed: UInt64

    /// Fraction of physical memory considered used (0…1).
    public var pressure: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    public init(
        physicalTotal: UInt64,
        vmStats: VMStatistics,
        pageSize: UInt64,
        swapUsed: UInt64 = 0
    ) {
        let active     = vmStats.activeCount         * pageSize
        let wired      = vmStats.wireCount           * pageSize
        let compressed = vmStats.compressorPageCount * pageSize
        self.total = physicalTotal
        self.used = active + wired + compressed
        self.swapUsed = swapUsed
    }

    public init(total: UInt64, used: UInt64, swapUsed: UInt64 = 0) {
        self.total = total
        self.used = used
        self.swapUsed = swapUsed
    }
}
