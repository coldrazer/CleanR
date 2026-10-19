import Foundation

public enum FileSizeFormatter {
    public static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func shortFormat(_ bytes: UInt64) -> (value: String, unit: String) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = false
        let value = formatter.string(fromByteCount: Int64(bytes))

        let unitFormatter = ByteCountFormatter()
        unitFormatter.countStyle = .file
        unitFormatter.includesCount = false
        let unit = unitFormatter.string(fromByteCount: Int64(bytes))

        return (value, unit)
    }
}
