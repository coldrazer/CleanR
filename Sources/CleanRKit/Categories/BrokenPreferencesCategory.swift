import Foundation

/// Identifies preference plists that are corrupt (fail to deserialize).
///
/// **Important:** never flag a plist as broken just because Launch Services
/// doesn't recognize its owning bundle ID. See `PlistJunkFilter` for the
/// safety contract and tests.
public struct BrokenPreferencesCategory: JunkCategory {
    public init() {}

    public let scanCategory = ScanCategory.brokenPreferences

    public var targets: [ScanTarget] {
        [
            ScanTarget(
                path: MCConstants.userPreferences,
                recursive: false,
                fileExtensions: ["plist"]
            ),
        ]
    }

    /// Pure filter: keep only items whose plists are provably corrupt.
    /// `loadData` and `appExistsForBundleID` are injected so this is fully
    /// testable without disk I/O.
    public func filterBroken(
        _ items: [FileItem],
        loadData: (URL) -> Data?,
        appExistsForBundleID: (String) -> Bool
    ) -> [FileItem] {
        items.filter { item in
            PlistJunkFilter.isLikelyBroken(
                at: item.url,
                loadData: loadData,
                appExistsForBundleID: appExistsForBundleID
            )
        }
    }
}
