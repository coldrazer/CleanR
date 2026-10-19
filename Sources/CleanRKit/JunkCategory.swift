import Foundation

/// A System Junk category. Pure data declaration — describes *what* to scan.
/// Lives in CleanRKit so every category can be unit-tested without
/// touching the filesystem.
public protocol JunkCategory: Sendable {
    var scanCategory: ScanCategory { get }
    var targets: [ScanTarget] { get }
}
