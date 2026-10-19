import Foundation

/// Pre-clean safety breakdown of the current selection: how much of it is
/// recoverable (moved to the Trash, restorable from Clean History) versus
/// permanent (already in the Trash, deleted forever). The confirmation UI
/// must never promise "you can recover this" for the permanent portion —
/// this summary is the single source that keeps that promise honest.
public struct CleanSafetySummary: Equatable, Sendable {
    public let selectedCount: Int
    public let recoverableCount: Int
    public let permanentCount: Int
    public let recoverableBytes: UInt64
    public let permanentBytes: UInt64

    public var totalBytes: UInt64 { recoverableBytes + permanentBytes }

    /// Permanent deletions always need an explicit confirmation, at any size.
    public var requiresExplicitConfirmation: Bool { permanentCount > 0 }

    public init(results: [ScanResult], selectedItems: Set<URL>) {
        var recCount = 0, permCount = 0
        var recBytes: UInt64 = 0, permBytes: UInt64 = 0
        // Dedupe by URL, matching the size the Clean action will report:
        // the same file can appear under two categories but is trashed once.
        var seen = Set<URL>()
        for result in results {
            let permanent = result.category == .trashBins
            for item in result.items where selectedItems.contains(item.url) && seen.insert(item.url).inserted {
                if permanent {
                    permCount += 1
                    permBytes += item.size
                } else {
                    recCount += 1
                    recBytes += item.size
                }
            }
        }
        selectedCount = recCount + permCount
        recoverableCount = recCount
        permanentCount = permCount
        recoverableBytes = recBytes
        permanentBytes = permBytes
    }
}

public extension Array where Element == ScanResult {
    func safetySummary(selectedItems: Set<URL>) -> CleanSafetySummary {
        CleanSafetySummary(results: self, selectedItems: selectedItems)
    }
}
