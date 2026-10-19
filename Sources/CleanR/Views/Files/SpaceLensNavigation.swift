import Foundation

/// Pure navigation state for SpaceLens drill-down ("zoom"). SwiftUI-free so
/// the back/up/home logic is unit-testable.
struct SpaceLensNavigation: Equatable {
    private(set) var breadcrumbs: [URL]
    private var pendingNavigationBreadcrumbs: [URL]?

    init(root: URL) { breadcrumbs = [root] }

    // Invariant: `breadcrumbs` is never empty — seeded with the root in
    // init and no method ever removes the last element (up() guards count>1,
    // home() resets to [root]).
    var current: URL { breadcrumbs.last! }
    var canGoUp: Bool { breadcrumbs.count > 1 }

    mutating func drillInto(_ url: URL) {
        beginPendingNavigation()
        breadcrumbs.append(url)
    }

    mutating func up() {
        guard breadcrumbs.count > 1 else { return }
        beginPendingNavigation()
        breadcrumbs.removeLast()
    }

    mutating func home() {
        guard breadcrumbs.count > 1, let root = breadcrumbs.first else { return }
        beginPendingNavigation()
        breadcrumbs = [root]
    }

    mutating func navigate(to url: URL) {
        guard let i = breadcrumbs.firstIndex(of: url), i < breadcrumbs.count - 1 else { return }
        beginPendingNavigation()
        breadcrumbs = Array(breadcrumbs.prefix(through: i))
    }

    mutating func commitPendingNavigation() {
        pendingNavigationBreadcrumbs = nil
    }

    mutating func cancelPendingNavigation() {
        guard let previousBreadcrumbs = pendingNavigationBreadcrumbs else { return }
        breadcrumbs = previousBreadcrumbs
        pendingNavigationBreadcrumbs = nil
    }

    private mutating func beginPendingNavigation() {
        if pendingNavigationBreadcrumbs == nil {
            pendingNavigationBreadcrumbs = breadcrumbs
        }
    }
}
