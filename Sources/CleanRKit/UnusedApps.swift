import Foundation

/// How long an app must sit unused before it appears in the Unused Apps list.
public enum UnusedAppHorizon: String, CaseIterable, Sendable, Identifiable {
    case threeMonths = "3"
    case sixMonths = "6"
    case twelveMonths = "12"

    public var id: String { rawValue }

    public var months: Int {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .twelveMonths: 12
        }
    }

    public func cutoff(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -months, to: now) ?? now
    }

    public var label: String {
        switch self {
        case .threeMonths:
            L10n.tr("3 个月", "3 months", "3 месяца")
        case .sixMonths:
            L10n.tr("6 个月", "6 months", "6 месяцев")
        case .twelveMonths:
            L10n.tr("12 个月", "12 months", "12 месяцев")
        }
    }
}

/// One installed app considered for the Unused Apps module.
public struct UnusedAppRecord: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { path }

    public let name: String
    public let bundleIdentifier: String
    public let path: String
    public let appBytes: UInt64
    public let supportBytes: UInt64
    public let lastUsed: Date?
    public let isApple: Bool
    public let runsInBackground: Bool
    /// Running right now (including menu-bar apps): never "unused".
    public let isRunning: Bool

    public var totalBytes: UInt64 { appBytes &+ supportBytes }

    public init(
        name: String,
        bundleIdentifier: String,
        path: String,
        appBytes: UInt64,
        supportBytes: UInt64,
        lastUsed: Date?,
        isApple: Bool,
        runsInBackground: Bool,
        isRunning: Bool = false
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.appBytes = appBytes
        self.supportBytes = supportBytes
        self.lastUsed = lastUsed
        self.isApple = isApple
        self.runsInBackground = runsInBackground
        self.isRunning = isRunning
    }
}

/// Pure filtering/sorting for Unused Apps. UI and Spotlight probes live elsewhere.
public enum UnusedApps {
    /// Returns non-Apple apps whose last-used date is on or before the horizon
    /// cutoff, sorted by total footprint (app + support) descending, then name.
    /// Apps without a last-used date are omitted: macOS cannot prove they are idle.
    public static func unused(
        from apps: [UnusedAppRecord],
        horizon: UnusedAppHorizon,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UnusedAppRecord] {
        let cutoff = horizon.cutoff(from: now, calendar: calendar)
        return apps
            .filter { !$0.isApple && !$0.isRunning }
            .filter { app in
                guard let lastUsed = app.lastUsed else { return false }
                return lastUsed <= cutoff
            }
            .sorted { lhs, rhs in
                if lhs.totalBytes != rhs.totalBytes {
                    return lhs.totalBytes > rhs.totalBytes
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}

extension UnusedApps {
    /// True when Spotlight has no last-used date for most third-party apps
    /// (index disabled or broken). The list would then be mostly empty or
    /// misleading, so the UI should say so instead of implying "all in use".
    public static func usageDataUnavailable(in apps: [UnusedAppRecord]) -> Bool {
        let thirdParty = apps.filter { !$0.isApple }
        guard !thirdParty.isEmpty else { return false }
        let missing = thirdParty.filter { $0.lastUsed == nil }.count
        return Double(missing) / Double(thirdParty.count) >= 0.8
    }
}

/// Detects menu-bar / background-only apps from Info.plist keys so the UI can
/// warn before the user uninstalls something they never open as a window.
public enum AppRuntimeRole {
    public static func runsInBackground(infoPlist: [String: Any]) -> Bool {
        truthy(infoPlist["LSUIElement"]) || truthy(infoPlist["LSBackgroundOnly"])
    }

    private static func truthy(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "yes" || lowered == "true" || lowered == "1"
        default:
            return false
        }
    }
}
