import Foundation

public struct AppInfo: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let bundleIdentifier: String
    public let name: String
    public let path: URL
    public let version: String?
    public let size: UInt64
    public let lastOpened: Date?
    public let iconPath: URL?
    public let isAppleApp: Bool

    public init(
        bundleIdentifier: String,
        name: String,
        path: URL,
        version: String? = nil,
        size: UInt64 = 0,
        lastOpened: Date? = nil,
        iconPath: URL? = nil,
        isAppleApp: Bool = false
    ) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.version = version
        self.size = size
        self.lastOpened = lastOpened
        self.iconPath = iconPath
        self.isAppleApp = isAppleApp
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    public var isUnused: Bool {
        guard let lastOpened else { return false }
        return Date().timeIntervalSince(lastOpened) > 180 * 24 * 3600 // 6 months
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(path)
    }

    public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.path == rhs.path
    }
}
