import XCTest
@testable import CleanRKit

final class UnusedAppsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Fixed instant so month arithmetic does not depend on the clock.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testThreeMonthWindowKeepsAppsLastUsedBeforeTheCutoff() {
        let stale = record(name: "Old", monthsAgo: 4)
        let recent = record(name: "Fresh", monthsAgo: 1)
        let listed = UnusedApps.unused(from: [recent, stale], horizon: .threeMonths, now: now, calendar: calendar)
        XCTAssertEqual(listed.map(\.name), ["Old"])
    }

    func testExactlyOnTheCutoffCountsAsUnused() {
        let cutoff = UnusedAppHorizon.threeMonths.cutoff(from: now, calendar: calendar)
        let exact = record(name: "Exact", lastUsed: cutoff)
        let justAfter = record(name: "After", lastUsed: cutoff.addingTimeInterval(1))
        let listed = UnusedApps.unused(from: [exact, justAfter], horizon: .threeMonths, now: now, calendar: calendar)
        XCTAssertEqual(listed.map(\.name), ["Exact"])
    }

    func testSixAndTwelveMonthWindowsAreStricter() {
        let four = record(name: "Four", monthsAgo: 4)
        let eight = record(name: "Eight", monthsAgo: 8)
        let fourteen = record(name: "Fourteen", monthsAgo: 14)
        let six = UnusedApps.unused(from: [four, eight, fourteen], horizon: .sixMonths, now: now, calendar: calendar)
        let twelve = UnusedApps.unused(from: [four, eight, fourteen], horizon: .twelveMonths, now: now, calendar: calendar)
        XCTAssertEqual(six.map(\.name), ["Eight", "Fourteen"])
        XCTAssertEqual(twelve.map(\.name), ["Fourteen"])
    }

    func testAppleAppsAndUnknownDatesAreOmitted() {
        let apple = record(name: "Safari", monthsAgo: 24, isApple: true)
        let unknown = record(name: "Mystery", lastUsed: nil)
        let real = record(name: "Editor", monthsAgo: 8)
        let listed = UnusedApps.unused(from: [apple, unknown, real], horizon: .threeMonths, now: now, calendar: calendar)
        XCTAssertEqual(listed.map(\.name), ["Editor"])
    }

    func testBackgroundAppsStayAndStayMarked() {
        let menu = record(name: "MenuBar", monthsAgo: 10, runsInBackground: true)
        let listed = UnusedApps.unused(from: [menu], horizon: .threeMonths, now: now, calendar: calendar)
        XCTAssertEqual(listed.map(\.name), ["MenuBar"])
        XCTAssertTrue(listed[0].runsInBackground)
    }

    func testSortsByAppPlusSupportBytesThenName() {
        let smallAppHugeSupport = record(name: "Zed", monthsAgo: 9, appBytes: 10, supportBytes: 5_000)
        let largeApp = record(name: "Alpha", monthsAgo: 9, appBytes: 4_000, supportBytes: 0)
        let tieLow = record(name: "Bravo", monthsAgo: 9, appBytes: 100, supportBytes: 0)
        let tieHigh = record(name: "AlphaSmall", monthsAgo: 9, appBytes: 100, supportBytes: 0)
        let listed = UnusedApps.unused(
            from: [tieLow, largeApp, smallAppHugeSupport, tieHigh],
            horizon: .threeMonths,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(listed.map(\.name), ["Zed", "Alpha", "AlphaSmall", "Bravo"])
        XCTAssertEqual(listed[0].totalBytes, 5_010)
    }

    func testBackgroundRoleReadsMenuBarAndBackgroundOnlyFlags() {
        XCTAssertTrue(AppRuntimeRole.runsInBackground(infoPlist: ["LSUIElement": true]))
        XCTAssertTrue(AppRuntimeRole.runsInBackground(infoPlist: ["LSBackgroundOnly": 1]))
        XCTAssertTrue(AppRuntimeRole.runsInBackground(infoPlist: ["LSUIElement": "YES"]))
        XCTAssertFalse(AppRuntimeRole.runsInBackground(infoPlist: ["LSUIElement": false]))
        XCTAssertFalse(AppRuntimeRole.runsInBackground(infoPlist: ["LSBackgroundOnly": 0]))
        XCTAssertFalse(AppRuntimeRole.runsInBackground(infoPlist: [:]))
    }

    func testRunningAppsAreNeverListedAsUnused() {
        let running = record(name: "Daemon", monthsAgo: 10, isRunning: true)
        let idle = record(name: "Idle", monthsAgo: 10)
        let listed = UnusedApps.unused(from: [running, idle], horizon: .threeMonths, now: now, calendar: calendar)
        XCTAssertEqual(listed.map(\.name), ["Idle"])
    }

    func testUsageDataIsUnavailableWhenMostAppsHaveNoLastUsedDate() {
        let blind = (0..<9).map { record(name: "App\($0)", lastUsed: nil) } + [record(name: "One", monthsAgo: 1)]
        XCTAssertTrue(UnusedApps.usageDataUnavailable(in: blind))
        let healthy = (0..<9).map { record(name: "App\($0)", monthsAgo: 1) } + [record(name: "New", lastUsed: nil)]
        XCTAssertFalse(UnusedApps.usageDataUnavailable(in: healthy))
        XCTAssertFalse(UnusedApps.usageDataUnavailable(in: []))
    }

    private func record(
        name: String,
        monthsAgo: Int? = nil,
        lastUsed: Date? = nil,
        appBytes: UInt64 = 100,
        supportBytes: UInt64 = 0,
        isApple: Bool = false,
        runsInBackground: Bool = false,
        isRunning: Bool = false
    ) -> UnusedAppRecord {
        let used: Date?
        if let monthsAgo {
            used = calendar.date(byAdding: .month, value: -monthsAgo, to: now)
        } else {
            used = lastUsed
        }
        return UnusedAppRecord(
            name: name,
            bundleIdentifier: "com.example.\(name)",
            path: "/Applications/\(name).app",
            appBytes: appBytes,
            supportBytes: supportBytes,
            lastUsed: used,
            isApple: isApple,
            runsInBackground: runsInBackground,
            isRunning: isRunning
        )
    }
}
