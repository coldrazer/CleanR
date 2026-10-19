import CoreServices
import Foundation
import CleanRKit

/// Discovers installed apps and builds `UnusedAppRecord`s with Spotlight
/// last-used dates and support-file footprint.
public struct UnusedAppsClient: Sendable {
    private let discovery = AppDiscovery()
    private let pathFinder = AppPathFinder()

    public init() {}

    /// Every installed app with its Spotlight last-used date. Support files
    /// are sized only for apps idle past the shortest horizon, so switching
    /// horizons can filter this in memory instead of rescanning.
    /// `runningAppPaths` comes from NSWorkspace on the main actor.
    public func records(runningAppPaths: Set<String>) async -> [UnusedAppRecord] {
        let apps = await discovery.discoverApps()
        let shortestCutoff = UnusedAppHorizon.threeMonths.cutoff(from: Date())
        return apps.map { app -> UnusedAppRecord in
            // No atime fallback: a bundle's access date is not updated on
            // launch, so it made apps in daily use look idle for months.
            let lastUsed = Self.spotlightLastUsed(at: app.path)
            let path = app.path.path(percentEncoded: false)
            let isCandidate = !app.isAppleApp && (lastUsed.map { $0 <= shortestCutoff } ?? false)
            let supportBytes = isCandidate
                ? pathFinder.findAssociatedFiles(for: app).reduce(UInt64(0)) { $0 &+ $1.size }
                : 0
            let runsInBackground = Self.readsBackgroundRole(at: app.path)
            return UnusedAppRecord(
                name: app.name,
                bundleIdentifier: app.bundleIdentifier,
                path: path,
                appBytes: app.size,
                supportBytes: supportBytes,
                lastUsed: lastUsed,
                isApple: app.isAppleApp,
                runsInBackground: runsInBackground,
                isRunning: runningAppPaths.contains(path)
            )
        }
    }

    static func spotlightLastUsed(at url: URL) -> Date? {
        let path = url.path(percentEncoded: false) as CFString
        guard let item = MDItemCreate(nil, path) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func readsBackgroundRole(at url: URL) -> Bool {
        let plistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return AppRuntimeRole.runsInBackground(infoPlist: plist)
    }
}
