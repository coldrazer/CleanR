import Foundation
import CleanRKit

/// Per-category collapse state for FileListView. Categories are expanded by
/// default; only collapsed ones are stored. SwiftUI-free + unit-testable.
struct FileListExpansion {
    private var collapsed: Set<ScanCategory> = []

    func isExpanded(_ c: ScanCategory) -> Bool { !collapsed.contains(c) }

    /// Cheap, stable key of the collapse state (the set is at most a couple
    /// dozen categories). Used to memoize the flattened row list so it only
    /// rebuilds when expansion actually changes.
    var signature: String { collapsed.map(\.rawValue).sorted().joined(separator: ",") }

    mutating func toggle(_ c: ScanCategory) {
        if collapsed.contains(c) { collapsed.remove(c) } else { collapsed.insert(c) }
    }

    mutating func collapseAll(_ cats: [ScanCategory]) { collapsed.formUnion(cats) }

    mutating func expandAll() { collapsed.removeAll() }
}
