# In-App Settings Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the separate Settings window with an in-app Settings page (sidebar footer button, Cmd-comma, deep link) adding appearance override, launch at login, Homebrew-aware update check, and an About section.

**Architecture:** `SidebarItem.settings` becomes a regular module destination rendered in the detail pane, selected by a pinned sidebar footer row that replaces the Menu Bar Widget toggle (the toggle moves into the page). Pure logic (semver compare, release JSON parsing, Homebrew detection) lives in `CleanRKit.UpdateChecker` and is unit-tested; AppKit side effects (NSApp.appearance, SMAppService) live in thin `CleanR` services.

**Tech Stack:** Swift 6, SwiftUI + AppKit, SwiftPM, XCTest, ServiceManagement (SMAppService), GitHub Releases REST API.

**Spec:** `docs/superpowers/specs/2026-06-05-settings-page-design.md`

**Conventions (from CLAUDE.md memory):** no Co-Authored-By lines, no AI attribution anywhere, no em dashes in public text, full `bash scripts/check-version-sync.sh && swift build && swift test` before push, all changes via PR.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/CleanR/Views/Sidebar/SidebarView.swift` | Modify | `SidebarItem.settings` case + footer swap |
| `Sources/CleanR/Views/Shared/GradientBackground.swift` | Modify | `ModuleTheme.settings` graphite theme |
| `Sources/CleanRKit/Constants.swift` | Modify | Project URLs + version bump |
| `Sources/CleanRKit/UpdateChecker.swift` | Create | Update check logic + network call |
| `Sources/CleanR/Services/AppearanceManager.swift` | Create | AppearanceMode enum + NSApp.appearance application |
| `Sources/CleanR/Services/LaunchAtLoginManager.swift` | Create | SMAppService.mainApp wrapper |
| `Sources/CleanR/Views/Settings/SettingsPageView.swift` | Create | The in-app Settings page |
| `Sources/CleanR/Views/Settings/SettingsView.swift` | Delete | Old Settings window content |
| `Sources/CleanR/App/CleanRApp.swift` | Modify | Remove Settings scene, add Cmd-comma command, apply appearance |
| `Sources/CleanR/App/ContentView.swift` | Modify | `.settings` case in `moduleView(for:)` |
| `Tests/CleanRTests/SettingsNavigationTests.swift` | Create | Deep link + sidebar exclusion tests |
| `Tests/CleanRTests/AppearanceModeTests.swift` | Create | Mode mapping tests |
| `Tests/CleanRKitTests/UpdateCheckerTests.swift` | Create | Semver/parsing/Homebrew tests |
| `VERSION` | Modify | 1.9.0 → 1.10.0 |

Branch: `feature/settings-page` (already created, spec committed).

---

### Task 1: SidebarItem.settings + ModuleTheme.settings (model layer)

**Files:**
- Test: `Tests/CleanRTests/SettingsNavigationTests.swift` (create)
- Modify: `Sources/CleanR/Views/Sidebar/SidebarView.swift` (enum parts only; footer is Task 6)
- Modify: `Sources/CleanR/Views/Shared/GradientBackground.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CleanRTests/SettingsNavigationTests.swift`:

```swift
import XCTest
@testable import CleanR

final class SettingsNavigationTests: XCTestCase {
    func testSettingsDeepLinkRoundTrips() {
        XCTAssertEqual(SidebarItem.settings.deepLinkID, "settings")
        XCTAssertEqual(SidebarItem(deepLinkID: "settings"), .settings)
    }

    /// Settings is opened from the pinned footer, never from the scrolling
    /// section list. If it leaks into a section the sidebar shows it twice.
    func testSettingsExcludedFromSidebarSections() {
        let listed = SidebarSection.allCases.flatMap(\.items)
        XCTAssertFalse(listed.contains(.settings))
        XCTAssertTrue(SidebarItem.allCases.contains(.settings))
    }

    /// Existing module rows must be unaffected by the items filter.
    func testExistingSectionsStillListTheirItems() {
        XCTAssertEqual(SidebarSection.main.items, [.smartScan])
        XCTAssertTrue(SidebarSection.cleanup.items.contains(.systemJunk))
        XCTAssertTrue(SidebarSection.files.items.contains(.shredder))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SettingsNavigationTests 2>&1 | tail -20`
Expected: compile FAILURE, `type 'SidebarItem' has no member 'settings'`

- [ ] **Step 3: Add the enum cases**

In `Sources/CleanR/Views/Sidebar/SidebarView.swift`:

3a. After `case shredder = "Shredder"` (line 28), add:

```swift

    // Footer (pinned below the list, not rendered in any section)
    case settings = "Settings"
```

3b. In `deepLinkID`, after `case .shredder: "shredder"`, add:

```swift
        case .settings: "settings"
```

3c. In `icon`, after `case .shredder: "scissors"`, add:

```swift
        case .settings: "gearshape"
```

3d. In `theme`, change the last line of the switch from
`case .spaceLens, .largeOldFiles, .duplicates, .shredder: .files` to:

```swift
        case .spaceLens, .largeOldFiles, .duplicates, .shredder: .files
        case .settings: .settings
```

3e. In `section`, after the `.files` line, add:

```swift
        case .settings: .main
```

3f. In `SidebarSection.items`, replace the body with:

```swift
    public var items: [SidebarItem] {
        // .settings is pinned to the footer; it never renders inside a section.
        SidebarItem.allCases.filter { $0.section == self && $0 != .settings }
    }
```

In `Sources/CleanR/Views/Shared/GradientBackground.swift`:

3g. Add `case settings` after `case files` (line 9).

3h. In `colors`, add before the closing brace of the switch:

```swift
        case .settings:
            [Color(red: 0.16, green: 0.17, blue: 0.21), Color(red: 0.26, green: 0.28, blue: 0.33), Color(red: 0.37, green: 0.39, blue: 0.45)]
```

3i. In `buttonColors`, add:

```swift
        case .settings:
            [Color(red: 0.30, green: 0.32, blue: 0.38), Color(red: 0.42, green: 0.44, blue: 0.51)]
```

- [ ] **Step 4: Make ContentView exhaustive again**

`ContentView.moduleView(for:)` switches over `SidebarItem` and no longer compiles. In `Sources/CleanR/App/ContentView.swift`, add to the switch in `moduleView(for:)` after `case .shredder:`:

```swift
        case .settings:
            // Placeholder until Task 5 lands SettingsPageView.
            Text("Settings")
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter SettingsNavigationTests 2>&1 | tail -5`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanR/Views/Sidebar/SidebarView.swift Sources/CleanR/Views/Shared/GradientBackground.swift Sources/CleanR/App/ContentView.swift Tests/CleanRTests/SettingsNavigationTests.swift
git commit -m "Add SidebarItem.settings destination with graphite theme and deep link"
```

---

### Task 2: UpdateChecker in CleanRKit

**Files:**
- Test: `Tests/CleanRKitTests/UpdateCheckerTests.swift` (create)
- Create: `Sources/CleanRKit/UpdateChecker.swift`
- Modify: `Sources/CleanRKit/Constants.swift` (project URLs)

- [ ] **Step 1: Write the failing test**

Create `Tests/CleanRKitTests/UpdateCheckerTests.swift`:

```swift
import XCTest
@testable import CleanRKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: - isNewer (numeric semver compare)

    func testNewerPatchMinorMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("1.9.1", than: "1.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))   // 10 > 9 numerically
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }

    func testEqualAndOlderAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.10.0"))
    }

    func testShortAndMalformedComponents() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9.0"))   // pads as 1.10.0
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "1.9.0"))   // non-numeric reads as 0
    }

    // MARK: - parseLatestRelease

    func testParseValidPayload() throws {
        let json = """
        {"tag_name": "v1.10.0", "html_url": "https://github.com/cleanr/CleanR/releases/tag/v1.10.0", "name": "1.10.0"}
        """
        let parsed = try XCTUnwrap(UpdateChecker.parseLatestRelease(Data(json.utf8)))
        XCTAssertEqual(parsed.version, "1.10.0")
        XCTAssertEqual(parsed.url.absoluteString, "https://github.com/cleanr/CleanR/releases/tag/v1.10.0")
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("{}".utf8)))
        // Tag that is only the "v" prefix yields an empty version: reject.
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data(#"{"tag_name": "v", "html_url": "https://example.com"}"#.utf8)))
    }

    // MARK: - Homebrew detection

    func testHomebrewDetection() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "caskroom-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertTrue(UpdateChecker.isHomebrewInstall(caskroomPaths: [tmp.path]))
        XCTAssertFalse(UpdateChecker.isHomebrewInstall(caskroomPaths: ["/nonexistent/caskroom/cleanr"]))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -10`
Expected: compile FAILURE, `cannot find 'UpdateChecker' in scope`

- [ ] **Step 3: Add project URLs to MCConstants**

In `Sources/CleanRKit/Constants.swift`, immediately before the `// MARK: - App version` block (line 174), insert:

```swift
    // MARK: - Project links

    public static let repoURL = URL(string: "https://github.com/cleanr/CleanR")!
    public static let issuesURL = URL(string: "https://github.com/cleanr/CleanR/issues/new/choose")!
    public static let releasesURL = URL(string: "https://github.com/cleanr/CleanR/releases")!
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/cleanr/CleanR/releases/latest")!

```

- [ ] **Step 4: Implement UpdateChecker**

Create `Sources/CleanRKit/UpdateChecker.swift`:

```swift
import Foundation

/// Manual "Check for updates" against the GitHub Releases API.
///
/// Pure logic (semver compare, JSON parsing, Homebrew detection) is static
/// and unit-tested with fixtures; `check(...)` is the only networked entry
/// point and is never called at launch, only from the Settings button.
public enum UpdateChecker {
    public enum CheckResult: Equatable, Sendable {
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(message: String)
    }

    /// Subset of the GitHub "latest release" payload we use.
    private struct LatestRelease: Decodable {
        let tag_name: String
        let html_url: String
    }

    /// Parse the latest-release JSON into (version without "v" prefix,
    /// release page URL). Returns nil for malformed payloads.
    public static func parseLatestRelease(_ data: Data) -> (version: String, url: URL)? {
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
              let url = URL(string: release.html_url) else { return nil }
        var version = release.tag_name
        if version.hasPrefix("v") { version.removeFirst() }
        guard !version.isEmpty else { return nil }
        return (version, url)
    }

    /// Numeric component comparison: "1.10.0" is newer than "1.9.0".
    /// Missing components pad as 0; non-numeric components read as 0, so a
    /// garbage tag never reports itself as an update.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Caskroom locations for Apple Silicon and Intel Homebrew prefixes.
    public static let defaultCaskroomPaths = [
        "/opt/homebrew/Caskroom/cleanr",
        "/usr/local/Caskroom/cleanr",
    ]

    /// True when the app was installed via the Homebrew cask. The Settings
    /// UI then shows `brew upgrade --cask cleanr` instead of a DMG link,
    /// so brew's receipt and the installed app never drift.
    public static func isHomebrewInstall(
        caskroomPaths: [String] = defaultCaskroomPaths,
        fileManager: FileManager = .default
    ) -> Bool {
        caskroomPaths.contains { fileManager.fileExists(atPath: $0) }
    }

    /// Query GitHub and classify the result. Failures are returned as
    /// values, never thrown: the Settings UI renders them inline.
    public static func check(
        currentVersion: String = MCConstants.appVersion,
        session: URLSession = .shared
    ) async -> CheckResult {
        var request = URLRequest(url: MCConstants.latestReleaseAPI, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await session.data(for: request)
            guard let (version, url) = parseLatestRelease(data) else {
                return .failed(message: "Unexpected response from GitHub.")
            }
            return isNewer(version, than: currentVersion)
                ? .updateAvailable(version: version, url: url)
                : .upToDate
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -5`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanRKit/UpdateChecker.swift Sources/CleanRKit/Constants.swift Tests/CleanRKitTests/UpdateCheckerTests.swift
git commit -m "Add UpdateChecker: GitHub latest-release check with Homebrew detection"
```

---

### Task 3: AppearanceMode + AppearanceManager

**Files:**
- Test: `Tests/CleanRTests/AppearanceModeTests.swift` (create)
- Create: `Sources/CleanR/Services/AppearanceManager.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CleanRTests/AppearanceModeTests.swift`:

```swift
import XCTest
@testable import CleanR

final class AppearanceModeTests: XCTestCase {
    func testNSAppearanceMapping() {
        XCTAssertNil(AppearanceMode.system.nsAppearance)   // nil clears the override
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }

    func testRawValuesRoundTrip() {
        for mode in AppearanceMode.allCases {
            XCTAssertEqual(AppearanceMode(rawValue: mode.rawValue), mode)
        }
        XCTAssertNil(AppearanceMode(rawValue: "nonsense"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AppearanceModeTests 2>&1 | tail -10`
Expected: compile FAILURE, `cannot find 'AppearanceMode' in scope`

- [ ] **Step 3: Implement**

Create `Sources/CleanR/Services/AppearanceManager.swift`:

```swift
import AppKit

/// Light/Dark/System override for the whole app, stored in UserDefaults
/// under `AppearanceManager.defaultsKey`. `.system` clears the override so
/// the app follows the OS appearance again.
///
/// The menu bar helper is a separate process and keeps following the
/// system appearance; this override applies to the main app only.
public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "follow the system" (clears `NSApp.appearance`).
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Applies the stored mode at launch and on picker changes. @MainActor
/// because `NSApp.appearance` is main-thread state; both call sites
/// (applicationDidFinishLaunching, SwiftUI onChange) are already on main.
/// Do NOT call from completion handlers (macOS 26 SIGTRAP, issue #58).
@MainActor
public enum AppearanceManager {
    public static let defaultsKey = "appearanceMode"

    public static var storedMode: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return AppearanceMode(rawValue: raw) ?? .system
    }

    public static func applyStored() {
        apply(storedMode)
    }

    public static func apply(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AppearanceModeTests 2>&1 | tail -5`
Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanR/Services/AppearanceManager.swift Tests/CleanRTests/AppearanceModeTests.swift
git commit -m "Add AppearanceMode override (light/dark/system) applied via NSApp.appearance"
```

---

### Task 4: LaunchAtLoginManager

**Files:**
- Create: `Sources/CleanR/Services/LaunchAtLoginManager.swift`

No unit test: the class is a thin `SMAppService.mainApp` wrapper with system side effects (login item registration); its pattern is copied from the proven `MenuBarLauncher`. UI verification happens in Task 7.

- [ ] **Step 1: Implement**

Create `Sources/CleanR/Services/LaunchAtLoginManager.swift`:

```swift
import Foundation
import ServiceManagement

/// Registers / unregisters the main app as a login item via
/// `SMAppService.mainApp`. Mirrors `MenuBarLauncher`: best-effort
/// `setEnabled`, errors surfaced through `lastError` for the Settings UI.
///
/// Under `swift run` (no .app bundle) registration fails and the error
/// shows in Settings; same dev-workflow caveat as the widget toggle.
@MainActor
@Observable
public final class LaunchAtLoginManager {
    public enum LaunchAtLoginError: Error, LocalizedError {
        case updateFailed(enabling: Bool, message: String)

        public var errorDescription: String? {
            switch self {
            case .updateFailed(let enabling, let message):
                let verb = enabling ? "enable" : "disable"
                return "Couldn't \(verb) launch at login: \(message)"
            }
        }
    }

    public static let shared = LaunchAtLoginManager()

    public internal(set) var lastError: LaunchAtLoginError?

    private let service = SMAppService.mainApp

    public var isEnabled: Bool { service.status == .enabled }
    public var status: SMAppService.Status { service.status }

    private init() {}

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            lastError = nil
        } catch {
            lastError = .updateFailed(enabling: enabled, message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/CleanR/Services/LaunchAtLoginManager.swift
git commit -m "Add LaunchAtLoginManager (SMAppService.mainApp wrapper)"
```

---

### Task 5: SettingsPageView + app wiring

**Files:**
- Create: `Sources/CleanR/Views/Settings/SettingsPageView.swift`
- Delete: `Sources/CleanR/Views/Settings/SettingsView.swift`
- Modify: `Sources/CleanR/App/CleanRApp.swift`
- Modify: `Sources/CleanR/App/ContentView.swift` (replace Task 1 placeholder)

- [ ] **Step 1: Create the page**

Create `Sources/CleanR/Views/Settings/SettingsPageView.swift`. The Menu Bar and Language Cleanup sections are carried over from the old `SettingsView` (same bindings, status row, and discovery flow):

```swift
import SwiftUI
import AppKit
import ServiceManagement
import CleanRKit

/// In-app Settings page rendered in the detail pane. Opened from the
/// pinned sidebar footer, the Cmd-comma "Settings…" menu item, or
/// cleanr://module/settings. Replaced the separate Settings window
/// (spec: docs/superpowers/specs/2026-06-05-settings-page-design.md).
struct SettingsPageView: View {
    enum UpdateUIState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(message: String)
    }

    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage(AppearanceManager.defaultsKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @State private var launcher = MenuBarLauncher.shared
    @State private var loginLauncher = LaunchAtLoginManager.shared
    @State private var updateState: UpdateUIState = .idle
    @State private var refreshTick = 0
    @State private var keptLanguages: Set<String> = []
    @State private var selectable: [(name: String, lprojs: [String])] = []
    @State private var languageSearch: String = ""

    /// Selectable languages filtered by the search field (case-insensitive).
    private var filteredLanguages: [(name: String, lprojs: [String])] {
        guard !languageSearch.isEmpty else { return selectable }
        return selectable.filter { $0.name.localizedCaseInsensitiveContains(languageSearch) }
    }

    var body: some View {
        Form {
            headerSection
            generalSection
            appearanceSection
            languageSection
            aboutSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .id(refreshTick)
        .onAppear {
            keptLanguages = LanguagePreferences.userKept
            selectable = LanguagePreferences.selectableLanguages()
            Task.detached(priority: .userInitiated) {
                let found = LanguageScanner().discoverLproj(in: LanguageScanner.defaultRoots)
                await MainActor.run {
                    LanguagePreferences.discoveredLproj = found
                    selectable = LanguagePreferences.selectableLanguages()
                }
            }
        }
    }

    // MARK: - Header (version + update check)

    private var headerSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MCConstants.appName)
                        .font(.title2.weight(.semibold))
                    Text("Version \(MCConstants.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                updateControl
            }
            if case .available(let version, let url) = updateState {
                updateAvailableRow(version: version, url: url)
            }
        }
    }

    @ViewBuilder
    private var updateControl: some View {
        switch updateState {
        case .idle:
            Button("Check for Updates") { startUpdateCheck() }
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Up to date")
            }
        case .available:
            EmptyView()   // detail rendered by updateAvailableRow
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button("Retry") { startUpdateCheck() }
            }
        }
    }

    @ViewBuilder
    private func updateAvailableRow(version: String, url: URL) -> some View {
        if UpdateChecker.isHomebrewInstall() {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version \(version) is available. Update with Homebrew:")
                    Text(Self.brewUpgradeCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.brewUpgradeCommand, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        } else {
            HStack {
                Text("Version \(version) is available.")
                Spacer()
                Button("View Release") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    static let brewUpgradeCommand = "brew upgrade --cask cleanr"

    @MainActor
    private func startUpdateCheck() {
        updateState = .checking
        Task {
            let result = await UpdateChecker.check()
            switch result {
            case .upToDate:
                updateState = .upToDate
            case .updateAvailable(let version, let url):
                updateState = .available(version: version, url: url)
            case .failed(let message):
                updateState = .failed(message: message)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Open \(MCConstants.appName) automatically when you sign in to macOS. You can also manage this in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: launchAtLogin) { _, newValue in
                loginLauncher.setEnabled(newValue)
                refreshTick &+= 1
            }
            if loginLauncher.status == .requiresApproval {
                Label("Needs approval in System Settings → General → Login Items",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            if let err = loginLauncher.lastError {
                Label(err.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Toggle(isOn: $showMenuBarWidget) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show \(MCConstants.appName) in the menu bar")
                    Text("Live CPU, memory, disk, battery, and network at the top of your screen. Click to expand the popover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: showMenuBarWidget) { _, newValue in
                launcher.setEnabled(newValue)
                refreshTick &+= 1
            }
            widgetStatusRow
            if let err = launcher.lastError {
                Label(err.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearanceRaw) { _, newValue in
                AppearanceManager.apply(AppearanceMode(rawValue: newValue) ?? .system)
            }
        }
    }

    // MARK: - Language Cleanup (carried over from the old Settings window)

    private var languageSection: some View {
        Section("Language Cleanup") {
            Text("English is always kept. Checked languages are preserved; unchecked language files can be removed by System Junk.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if selectable.isEmpty {
                Text("Detecting installed languages…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Search languages", text: $languageSearch)
                    .textFieldStyle(.roundedBorder)

                if filteredLanguages.isEmpty {
                    Text("No languages match “\(languageSearch)”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(filteredLanguages, id: \.name) { lang in
                    // One toggle covers every folder variant of the
                    // language (e.g. "fr.lproj" + legacy "French.lproj").
                    Toggle(lang.name, isOn: Binding(
                        get: { lang.lprojs.allSatisfy { keptLanguages.contains($0) } },
                        set: { on in
                            if on { keptLanguages.formUnion(lang.lprojs) }
                            else { lang.lprojs.forEach { keptLanguages.remove($0) } }
                            LanguagePreferences.userKept = keptLanguages
                        }
                    ))
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            aboutRow(icon: "chevron.left.forwardslash.chevron.right", tint: .orange,
                     title: "Source code", caption: "Browse the codebase on GitHub",
                     url: MCConstants.repoURL)
            aboutRow(icon: "exclamationmark.bubble", tint: .blue,
                     title: "Report an issue", caption: "Bug reports and feature requests",
                     url: MCConstants.issuesURL)
            aboutRow(icon: "tag", tint: .green,
                     title: "Release notes", caption: "Changelog and previous versions",
                     url: MCConstants.releasesURL)
        }
    }

    private func aboutRow(icon: String, tint: Color, title: String, caption: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    // MARK: - Widget status (carried over from the old Settings window)

    @ViewBuilder
    private var widgetStatusRow: some View {
        HStack {
            Image(systemName: statusGlyph)
                .foregroundStyle(statusColor)
            Text("Widget status:")
                .foregroundStyle(.secondary)
            Text(statusText)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
        .font(.caption)
    }

    private var statusGlyph: String {
        switch launcher.status {
        case .enabled: return "checkmark.circle.fill"
        case .notRegistered: return "minus.circle"
        case .notFound: return "questionmark.circle"
        case .requiresApproval: return "exclamationmark.triangle.fill"
        @unknown default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch launcher.status {
        case .enabled: return .green
        case .requiresApproval: return .orange
        default: return .secondary
        }
    }

    private var statusText: String {
        switch launcher.status {
        case .enabled: return "running"
        case .notRegistered: return "not registered"
        case .notFound: return "helper not found in bundle"
        case .requiresApproval: return "needs approval in System Settings → Login Items"
        @unknown default: return "unknown"
        }
    }
}
```

- [ ] **Step 2: Delete the old window content and wire the app**

2a. Delete the old file:

```bash
git rm Sources/CleanR/Views/Settings/SettingsView.swift
```

2b. In `Sources/CleanR/App/ContentView.swift`, replace the Task 1 placeholder:

```swift
        case .settings:
            // Placeholder until Task 5 lands SettingsPageView.
            Text("Settings")
```

with:

```swift
        case .settings:
            SettingsPageView()
```

2c. In `Sources/CleanR/App/CleanRApp.swift`, remove the scene:

```swift

        Settings {
            SettingsView()
        }
```

2d. In the same file, after `.defaultSize(width: 960, height: 620)`, add the command (keeps the standard "Settings…" menu item and Cmd-comma working, now routing in-app):

```swift
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appState.selectedSidebarItem = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
```

2e. In `AppDelegate.applicationDidFinishLaunching`, add as the first line:

```swift
        AppearanceManager.applyStored()
```

- [ ] **Step 3: Verify no dangling references and build**

Run: `grep -rn "SettingsView" Sources Tests`
Expected: matches only `SettingsPageView` (no bare `SettingsView` left).

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Run the full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/CleanR
git commit -m "Replace Settings window with in-app Settings page (appearance, launch at login, update check, About)"
```

---

### Task 6: Sidebar footer swap (widget toggle → Settings button)

**Files:**
- Modify: `Sources/CleanR/Views/Sidebar/SidebarView.swift:114-222` (struct `SidebarView` only)

- [ ] **Step 1: Remove the widget footer state**

In `struct SidebarView`, delete these two properties:

```swift
    @AppStorage("showMenuBarWidget") private var showMenuBarWidget = true
    @State private var launcher = MenuBarLauncher.shared
```

- [ ] **Step 2: Swap the footer**

In `body`, replace `menuBarFooter` with `settingsFooter`. Then delete the entire `menuBarFooter` computed property (the `/// Always-visible footer…` doc comment through its closing brace, including the `.onChange(of: showMenuBarWidget)` modifier) and add in its place:

```swift
    /// Pinned footer: opens the in-app Settings page. Replaced the old
    /// Menu Bar Widget toggle row; that toggle now lives inside Settings.
    private var settingsFooter: some View {
        Button {
            selection = .settings
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(selection == .settings ? Color.accentColor : Color.secondary)
                Text("Settings")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selection == .settings ? Color.primary.opacity(0.10) : Color.clear)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel("Settings")
    }
```

- [ ] **Step 3: Build and test**

Run: `swift build 2>&1 | tail -3` then `swift test 2>&1 | tail -5`
Expected: `Build complete!`, 0 failures. (If `import` of ServiceManagement or MenuBarLauncher symbols become unused in SidebarView.swift, leave the file's existing imports untouched; SwiftUI-only imports remain valid.)

- [ ] **Step 4: Manual smoke test**

Run: `swift run CleanR` and verify:
- Sidebar footer shows "⚙ Settings"; clicking it opens the page and highlights the row; List selection clears.
- Cmd-comma opens the page.
- Appearance picker flips the app light/dark/system live.
- Widget toggle works from the page (status row updates).
- About rows open the browser. "Check for Updates" reaches GitHub (expect "Up to date" or an available banner).
- Launch at login toggle shows an inline error under `swift run` (no .app bundle); that is the documented dev-workflow caveat, not a bug.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanR/Views/Sidebar/SidebarView.swift
git commit -m "Sidebar: replace widget toggle footer with pinned Settings button"
```

---

### Task 7: Version bump + full local gate

**Files:**
- Modify: `VERSION` (1.9.0 → 1.10.0)
- Modify: `Sources/CleanRKit/Constants.swift:182` (`appVersion = "1.10.0"`)

- [ ] **Step 1: Bump both versions**

`VERSION` file content becomes exactly:

```
1.10.0
```

In `Sources/CleanRKit/Constants.swift`, change:

```swift
    public static let appVersion = "1.9.0"
```

to:

```swift
    public static let appVersion = "1.10.0"
```

- [ ] **Step 2: Run the full local gate (required before any push)**

Run: `bash scripts/check-version-sync.sh && swift build && swift test`
Expected: `Version sync OK: 1.10.0`, `Build complete!`, 0 test failures.

- [ ] **Step 3: Commit**

```bash
git add VERSION Sources/CleanRKit/Constants.swift
git commit -m "Bump version to 1.10.0"
```

---

### Task 8: Push + PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/settings-page
```

- [ ] **Step 2: Open the PR**

No AI attribution, no Co-Authored-By, no em dashes in the PR body:

```bash
gh pr create --title "In-app Settings page: appearance override, launch at login, update check, About (1.10.0)" --body "## What

- Settings now lives in the main window as a full page (pinned sidebar footer button, Cmd-comma, and cleanr://module/settings all route to it). The separate Settings window is gone.
- New: Appearance override (Light / Dark / System).
- New: Launch at login toggle (SMAppService.mainApp), with the same status/error surfacing pattern as the widget toggle.
- New: Check for updates against GitHub releases. Homebrew installs get a copyable brew upgrade command; direct installs get a link to the release page. Manual only, no network at launch.
- New: About section (Source code, Report an issue, Release notes).
- Moved: the Menu Bar Widget toggle now lives only in Settings; the sidebar footer hosts the Settings button instead.

## Tests

- UpdateChecker: semver comparison, release JSON parsing fixtures, Homebrew detection with injected paths.
- AppearanceMode: NSAppearance mapping and raw value round trip.
- Navigation: settings deep link round trip, settings excluded from sidebar sections.

Spec: docs/superpowers/specs/2026-06-05-settings-page-design.md (committed on this branch)."
```

- [ ] **Step 3: Hand off for review**

User reviews and merges the PR (repo rule: no direct pushes to main, user merges).

---

## Self-Review Notes

- Spec coverage: navigation/entry points (Tasks 1, 5, 6), page content (Task 5), appearance (Tasks 3, 5), update checker (Tasks 2, 5), launch at login (Tasks 4, 5), tests (Tasks 1, 2, 3), version/process (Tasks 7, 8). The spec's "settings deep link slug round-trip" test lives in `SettingsNavigationTests` rather than `DeepLinkRoutingTests`; same coverage.
- Type consistency: `UpdateChecker.CheckResult` (Kit) maps onto the view's `UpdateUIState` in `startUpdateCheck()`; `AppearanceManager.defaultsKey` is the single source for the AppStorage key; `SidebarItem.settings` is referenced by ContentView, SidebarView footer, and the Cmd-comma command.
- ContentView keep-alive: `SidebarItem.allCases` now includes `.settings`; the `visited` machinery handles it like any module, and `GradientBackgroundView(theme: .settings)` renders the graphite gradient behind the form.
