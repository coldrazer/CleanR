import Foundation

public struct ScanResult: Sendable {
    public let category: ScanCategory
    public var items: [FileItem]
    public let autoSelect: Bool

    /// `autoSelect` defaults to the category's own policy rather than `true`.
    ///
    /// The `ScanCategory.autoSelect` table exists precisely for the categories
    /// that must never be pre-checked — the Trash, whose clean is a permanent
    /// delete, plus app leftovers, deleted-user homes, duplicates and binary
    /// thinning. A literal `true` default silently overrode that table for
    /// every scanner that didn't repeat the flag, so Smart Scan pre-selected
    /// exactly the items it was told to leave for explicit consent.
    public init(category: ScanCategory, items: [FileItem], autoSelect: Bool? = nil) {
        self.category = category
        self.items = items
        self.autoSelect = autoSelect ?? category.autoSelect
    }

    public var totalSize: UInt64 {
        items.reduce(0) { $0 + $1.size }
    }

    public var fileCount: Int {
        items.count
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

public struct ModuleScanResult: Sendable {
    public let moduleID: String
    public let moduleName: String
    public var categories: [ScanResult]
    public let scanDuration: TimeInterval

    public init(moduleID: String, moduleName: String, categories: [ScanResult], scanDuration: TimeInterval) {
        self.moduleID = moduleID
        self.moduleName = moduleName
        self.categories = categories
        self.scanDuration = scanDuration
    }

    public var totalSize: UInt64 {
        categories.reduce(0) { $0 + $1.totalSize }
    }

    public var totalFileCount: Int {
        categories.reduce(0) { $0 + $1.fileCount }
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}
