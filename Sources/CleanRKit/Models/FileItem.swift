import Foundation
import UniformTypeIdentifiers

public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let size: UInt64
    public let allocatedSize: UInt64
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isPackage: Bool
    public let contentType: UTType?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let lastAccessDate: Date?
    public let inode: UInt64
    public let deviceID: Int32

    public init(
        url: URL,
        name: String,
        size: UInt64,
        allocatedSize: UInt64,
        isDirectory: Bool,
        isSymlink: Bool = false,
        isPackage: Bool = false,
        contentType: UTType? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        lastAccessDate: Date? = nil,
        inode: UInt64 = 0,
        deviceID: Int32 = 0
    ) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.size = size
        self.allocatedSize = allocatedSize
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.contentType = contentType
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.lastAccessDate = lastAccessDate
        self.inode = inode
        self.deviceID = deviceID
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    public var fileExtension: String {
        url.pathExtension.lowercased()
    }

    public var age: TimeInterval? {
        modificationDate.map { Date().timeIntervalSince($0) }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}
