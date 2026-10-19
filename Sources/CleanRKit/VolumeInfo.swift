import Foundation

/// Information about a mounted volume. The data portion is pure (lives here);
/// `mountedVolumes()` reads the actual filesystem and lives in the CleanR
/// target via an extension.
public struct VolumeInfo: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let totalCapacity: UInt64
    public let availableCapacity: UInt64
    public let fileSystemType: String?

    public init(
        name: String,
        url: URL,
        totalCapacity: UInt64,
        availableCapacity: UInt64,
        fileSystemType: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.fileSystemType = fileSystemType
    }

    public var usedCapacity: UInt64 {
        guard totalCapacity > availableCapacity else { return 0 }
        return totalCapacity - availableCapacity
    }

    public var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    public static func == (lhs: VolumeInfo, rhs: VolumeInfo) -> Bool {
        lhs.url == rhs.url
    }
}
