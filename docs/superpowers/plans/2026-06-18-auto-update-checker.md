# Automatic Update Checker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect a newer stable release while the app is open and show a non-nagging modal that points the user to the right update path for how they installed.

**Architecture:** Pure decision logic lives in a unit-tested `UpdateScheduler` (CleanRKit). A thin `@MainActor` `UpdateCoordinator` (CleanR) reads prefs, calls the existing `UpdateChecker`, persists the last-check date, and publishes a pending update. `ContentView` runs the check ~3s after launch (and on app-activation) and presents it as an `.alert`. Settings gains an on-by-default toggle.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest. Builds on the existing `UpdateChecker` (GitHub Releases API + Homebrew detection). No new dependencies.

---

## File Structure

- Create: `Sources/CleanRKit/UpdateScheduler.swift`: pure logic (is-check-due, should-prompt, source-aware action) plus the `UpdateAction` enum.
- Create: `Tests/CleanRKitTests/UpdateSchedulerTests.swift`: unit tests for the above.
- Create: `Sources/CleanR/Services/UpdateCoordinator.swift`: `@MainActor @Observable` glue that runs the check, persists state, publishes `pendingUpdate`.
- Modify: `Sources/CleanR/App/ContentView.swift`: own the coordinator, run the check on launch/activation, present the `.alert`.
- Modify: `Sources/CleanR/Views/Settings/SettingsPageView.swift`: "Automatically check for updates" toggle plus a "Last checked" line.
- Modify: `README.md` and `README.zh-CN.md`: honesty edit on the "no network" claim.
- Modify: `VERSION`, `Sources/CleanRKit/Constants.swift`: bump to 1.13.0.

Persistence keys (UserDefaults.standard, shared by coordinator and Settings):
- `automaticUpdateChecks` (Bool, default true)
- `lastUpdateCheckDate` (Double, `timeIntervalSinceReferenceDate`; 0 = never)
- `skippedUpdateVersion` (String)

Note for every task: no `Co-Authored-By` and no AI-attribution lines in commits. All new user-facing strings use `L10n.tr("中文", "English")`.

---

### Task 1: `UpdateScheduler.isCheckDue` + `UpdateAction`

**Files:**
- Create: `Sources/CleanRKit/UpdateScheduler.swift`
- Test: `Tests/CleanRKitTests/UpdateSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CleanRKitTests/UpdateSchedulerTests.swift`:

```swift
import XCTest
@testable import CleanRKit

final class UpdateSchedulerTests: XCTestCase {

    // MARK: - isCheckDue

    func testCheckDueWhenNeverChecked() {
        XCTAssertTrue(UpdateScheduler.isCheckDue(now: Date(), lastCheck: nil, interval: 86_400))
    }

    func testCheckDueAfterInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let last = now.addingTimeInterval(-90_000) // older than 86_400
        XCTAssertTrue(UpdateScheduler.isCheckDue(now: now, lastCheck: last, interval: 86_400))
    }

    func testNotDueWithinInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let last = now.addingTimeInterval(-1_000)
        XCTAssertFalse(UpdateScheduler.isCheckDue(now: now, lastCheck: last, interval: 86_400))
    }

    func testDueAtExactInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let last = now.addingTimeInterval(-86_400)
        XCTAssertTrue(UpdateScheduler.isCheckDue(now: now, lastCheck: last, interval: 86_400))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter UpdateSchedulerTests`
Expected: FAIL to build with "cannot find 'UpdateScheduler' in scope".

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/CleanRKit/UpdateScheduler.swift`:

```swift
import Foundation

/// The action the update popup offers, chosen by install source.
public enum UpdateAction: Equatable, Sendable {
    /// Homebrew install: copy this command rather than overwrite the cask.
    case brewCommand(String)
    /// Direct/DMG install: open this release page.
    case openRelease(URL)
}

/// Pure decision logic for the automatic update checker. No I/O, so every rule
/// is deterministic and unit-tested; `UpdateCoordinator` supplies the dates,
/// prefs, and network result.
public enum UpdateScheduler {
    /// Once-a-day cadence, the macOS-standard interval.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Due when we've never checked, or the last check is at least `interval`
    /// old. `now`/`lastCheck` are injected so tests are deterministic.
    public static func isCheckDue(
        now: Date,
        lastCheck: Date?,
        interval: TimeInterval = checkInterval
    ) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanRKit/UpdateScheduler.swift Tests/CleanRKitTests/UpdateSchedulerTests.swift
git commit -m "Add UpdateScheduler.isCheckDue + UpdateAction"
```

---

### Task 2: `UpdateScheduler.shouldPrompt`

**Files:**
- Modify: `Sources/CleanRKit/UpdateScheduler.swift`
- Test: `Tests/CleanRKitTests/UpdateSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Append these methods inside `UpdateSchedulerTests`:

```swift
    // MARK: - shouldPrompt

    func testShouldPromptForNewNonSkippedVersion() {
        let r = UpdateChecker.CheckResult.updateAvailable(
            version: "1.13.0", url: URL(string: "https://example.com")!)
        XCTAssertTrue(UpdateScheduler.shouldPrompt(result: r, skippedVersion: nil))
        XCTAssertTrue(UpdateScheduler.shouldPrompt(result: r, skippedVersion: "1.12.0"))
    }

    func testNoPromptForSkippedVersion() {
        let r = UpdateChecker.CheckResult.updateAvailable(
            version: "1.13.0", url: URL(string: "https://example.com")!)
        XCTAssertFalse(UpdateScheduler.shouldPrompt(result: r, skippedVersion: "1.13.0"))
    }

    func testNoPromptForUpToDateOrFailed() {
        XCTAssertFalse(UpdateScheduler.shouldPrompt(result: .upToDate, skippedVersion: nil))
        XCTAssertFalse(UpdateScheduler.shouldPrompt(result: .failed(message: "x"), skippedVersion: nil))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter UpdateSchedulerTests`
Expected: FAIL to build with "type 'UpdateScheduler' has no member 'shouldPrompt'".

- [ ] **Step 3: Write the minimal implementation**

Add this method to `UpdateScheduler` in `Sources/CleanRKit/UpdateScheduler.swift` (after `isCheckDue`):

```swift
    /// Show the popup only for a newer version the user hasn't skipped.
    public static func shouldPrompt(
        result: UpdateChecker.CheckResult,
        skippedVersion: String?
    ) -> Bool {
        guard case .updateAvailable(let version, _) = result else { return false }
        return version != skippedVersion
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanRKit/UpdateScheduler.swift Tests/CleanRKitTests/UpdateSchedulerTests.swift
git commit -m "Add UpdateScheduler.shouldPrompt (suppress skipped versions)"
```

---

### Task 3: `UpdateScheduler.updateAction`

**Files:**
- Modify: `Sources/CleanRKit/UpdateScheduler.swift`
- Test: `Tests/CleanRKitTests/UpdateSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Append these methods inside `UpdateSchedulerTests`:

```swift
    // MARK: - updateAction

    func testActionForHomebrewIsBrewCommand() {
        let a = UpdateScheduler.updateAction(
            isHomebrew: true,
            releaseURL: URL(string: "https://example.com")!,
            brewCommand: "brew upgrade --cask cleanr")
        XCTAssertEqual(a, .brewCommand("brew upgrade --cask cleanr"))
    }

    func testActionForDMGIsOpenRelease() {
        let url = URL(string: "https://github.com/cleanr/CleanR/releases/tag/v1.13.0")!
        let a = UpdateScheduler.updateAction(
            isHomebrew: false, releaseURL: url, brewCommand: "ignored")
        XCTAssertEqual(a, .openRelease(url))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter UpdateSchedulerTests`
Expected: FAIL to build with "type 'UpdateScheduler' has no member 'updateAction'".

- [ ] **Step 3: Write the minimal implementation**

Add this method to `UpdateScheduler` in `Sources/CleanRKit/UpdateScheduler.swift`:

```swift
    /// Homebrew installs copy the upgrade command (overwriting the cask in place
    /// would desync brew's receipt); everyone else opens the release page.
    public static func updateAction(
        isHomebrew: Bool,
        releaseURL: URL,
        brewCommand: String
    ) -> UpdateAction {
        isHomebrew ? .brewCommand(brewCommand) : .openRelease(releaseURL)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter UpdateSchedulerTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanRKit/UpdateScheduler.swift Tests/CleanRKitTests/UpdateSchedulerTests.swift
git commit -m "Add UpdateScheduler.updateAction (source-aware)"
```

---

### Task 4: `UpdateCoordinator` (app glue)

This is `@MainActor` UI glue with no pure logic of its own (all decisions go
through `UpdateScheduler`/`UpdateChecker`), so it is verified by build + the
manual check in Task 8, not a unit test.

**Files:**
- Create: `Sources/CleanR/Services/UpdateCoordinator.swift`

- [ ] **Step 1: Write the implementation**

Create `Sources/CleanR/Services/UpdateCoordinator.swift`:

```swift
import SwiftUI
import AppKit
import CleanRKit

/// Drives the automatic update check and publishes a pending update for the UI.
/// All decisions live in `UpdateScheduler` (pure, unit-tested); this type is
/// glue: read prefs, call the checker, persist the last-check date, publish.
/// Uses async APIs only (no @MainActor completion closures, per the macOS 26
/// off-main SIGTRAP).
@MainActor
@Observable
final class UpdateCoordinator {
    struct PendingUpdate: Identifiable, Equatable {
        let version: String
        let action: UpdateAction
        var id: String { version }
    }

    /// Non-nil when a newer, non-skipped version was found this session.
    var pendingUpdate: PendingUpdate?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let autoCheck = "automaticUpdateChecks"
        static let lastCheck = "lastUpdateCheckDate"
        static let skipped = "skippedUpdateVersion"
    }

    /// Default ON: absent key reads as enabled.
    private var automaticChecksEnabled: Bool {
        defaults.object(forKey: Key.autoCheck) == nil ? true : defaults.bool(forKey: Key.autoCheck)
    }

    private var lastCheck: Date? {
        let t = defaults.double(forKey: Key.lastCheck)
        return t == 0 ? nil : Date(timeIntervalSinceReferenceDate: t)
    }

    /// Run a check if automatic checks are on and one is due. Safe to call on
    /// launch and on app-activation; the persisted last-check date throttles it
    /// to once per `UpdateScheduler.checkInterval`, and one popup per session.
    func runCheckIfDue() async {
        guard automaticChecksEnabled, pendingUpdate == nil else { return }
        guard UpdateScheduler.isCheckDue(now: Date(), lastCheck: lastCheck) else { return }

        let result = await UpdateChecker.check()
        // Stamp the time even on failure so a flaky network can't tight-loop.
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: Key.lastCheck)

        guard UpdateScheduler.shouldPrompt(
            result: result,
            skippedVersion: defaults.string(forKey: Key.skipped)
        ), case .updateAvailable(let version, let url) = result else { return }

        let action = UpdateScheduler.updateAction(
            isHomebrew: UpdateChecker.isHomebrewInstall(),
            releaseURL: url,
            brewCommand: "brew upgrade --cask cleanr"
        )
        pendingUpdate = PendingUpdate(version: version, action: action)
    }

    /// "Skip this version": never prompt for it again.
    func skip(_ version: String) {
        defaults.set(version, forKey: Key.skipped)
        pendingUpdate = nil
    }

    /// "Later": dismiss for now; reappears on the next due check.
    func dismiss() {
        pendingUpdate = nil
    }

    /// Run the popup's primary action (copy brew command, or open the release).
    func performPrimaryAction() {
        switch pendingUpdate?.action {
        case .brewCommand(let cmd):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
        case .openRelease(let url):
            NSWorkspace.shared.open(url)
        case nil:
            break
        }
        pendingUpdate = nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/CleanR/Services/UpdateCoordinator.swift
git commit -m "Add UpdateCoordinator: launch/active update check + pending state"
```

---

### Task 5: Wire the coordinator into `ContentView`

**Files:**
- Modify: `Sources/CleanR/App/ContentView.swift`

- [ ] **Step 1: Add the coordinator state and scenePhase**

In `Sources/CleanR/App/ContentView.swift`, find:

```swift
    @State private var visited: Set<SidebarItem> = []
```

Add directly below it:

```swift
    @State private var updateCoordinator = UpdateCoordinator()
    @Environment(\.scenePhase) private var scenePhase
```

- [ ] **Step 2: Attach the check + alert to the view**

In the same file, find the end of the `body` chain:

```swift
        .navigationTitle("")
        // Mark the current selection visited (runs initially too) so its view
        // is created on first visit and then retained.
        .onChange(of: appState.selectedSidebarItem, initial: true) { _, newValue in
            if let newValue { visited.insert(newValue) }
        }
```

Replace it with:

```swift
        .navigationTitle("")
        // Mark the current selection visited (runs initially too) so its view
        // is created on first visit and then retained.
        .onChange(of: appState.selectedSidebarItem, initial: true) { _, newValue in
            if let newValue { visited.insert(newValue) }
        }
        // Automatic update check: ~3s after launch (never blocks startup) and
        // again whenever the app becomes active. UpdateCoordinator throttles to
        // once per day and one popup per session.
        .task {
            try? await Task.sleep(for: .seconds(3))
            await updateCoordinator.runCheckIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await updateCoordinator.runCheckIfDue() }
            }
        }
        .alert(
            L10n.tr("发现新版本", "Update available"),
            isPresented: Binding(
                get: { updateCoordinator.pendingUpdate != nil },
                set: { if !$0 { updateCoordinator.dismiss() } }
            ),
            presenting: updateCoordinator.pendingUpdate
        ) { pending in
            switch pending.action {
            case .brewCommand:
                Button(L10n.tr("复制升级命令", "Copy Upgrade Command")) {
                    updateCoordinator.performPrimaryAction()
                }
            case .openRelease:
                Button(L10n.tr("下载", "Download")) {
                    updateCoordinator.performPrimaryAction()
                }
            }
            Button(L10n.tr("跳过此版本", "Skip This Version")) {
                updateCoordinator.skip(pending.version)
            }
            Button(L10n.tr("稍后", "Later"), role: .cancel) {
                updateCoordinator.dismiss()
            }
        } message: { pending in
            switch pending.action {
            case .brewCommand(let cmd):
                Text(L10n.tr(
                    "CleanR \(pending.version) 已发布。使用 Homebrew 升级：\n\(cmd)",
                    "CleanR \(pending.version) is available. Upgrade with Homebrew:\n\(cmd)"))
            case .openRelease:
                Text(L10n.tr(
                    "CleanR \(pending.version) 已发布。",
                    "CleanR \(pending.version) is available."))
            }
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/CleanR/App/ContentView.swift
git commit -m "Wire UpdateCoordinator into ContentView (launch check + alert)"
```

---

### Task 6: Settings toggle + "Last checked" line

**Files:**
- Modify: `Sources/CleanR/Views/Settings/SettingsPageView.swift`

- [ ] **Step 1: Add the persisted properties**

In `Sources/CleanR/Views/Settings/SettingsPageView.swift`, find:

```swift
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
```

Add directly below it:

```swift
    @AppStorage("automaticUpdateChecks") private var automaticUpdateChecks = true
    @AppStorage("lastUpdateCheckDate") private var lastUpdateCheckTimestamp: Double = 0
```

- [ ] **Step 2: Add the toggle + last-checked row to the updates Section**

In the same file, find the `if case .available` block inside the version/update `Section`:

```swift
            if case .available(let version, let url) = updateState {
                updateAvailableRow(version: version, url: url)
            }
        }
    }
```

Replace it with:

```swift
            if case .available(let version, let url) = updateState {
                updateAvailableRow(version: version, url: url)
            }
            Toggle(L10n.tr("自动检查更新", "Automatically check for updates"),
                   isOn: $automaticUpdateChecks)
            if lastUpdateCheckTimestamp > 0 {
                Text(L10n.tr(
                    "上次检查：\(lastCheckedDescription)",
                    "Last checked: \(lastCheckedDescription)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastCheckedDescription: String {
        let date = Date(timeIntervalSinceReferenceDate: lastUpdateCheckTimestamp)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/CleanR/Views/Settings/SettingsPageView.swift
git commit -m "Settings: automatic update-check toggle + last-checked line"
```

---

### Task 7: README honesty edit (both languages)

**Files:**
- Modify: `README.md:305`
- Modify: `README.zh-CN.md:305`

- [ ] **Step 1: Edit the English README**

In `README.md`, replace this line:

```markdown
- **No network access** — the app never phones home, no telemetry, no analytics
```

with:

```markdown
- **No telemetry or analytics.** The only network call is an optional update check (one request to the GitHub Releases API), which you can turn off in Settings
```

- [ ] **Step 2: Edit the Chinese README**

In `README.zh-CN.md`, replace this line:

```markdown
- **无网络访问**：应用从不回传，无遥测、无分析
```

with:

```markdown
- **无遥测、无分析。** 唯一的网络请求是可选的更新检查（一次对 GitHub Releases API 的请求），可在设置中关闭
```

- [ ] **Step 3: Commit**

```bash
git add README.md README.zh-CN.md
git commit -m "docs: qualify the no-network claim for the opt-out update check"
```

---

### Task 8: Version bump to 1.13.0 + full gate + manual verification

**Files:**
- Modify: `VERSION`
- Modify: `Sources/CleanRKit/Constants.swift`

- [ ] **Step 1: Bump the version**

Set `VERSION` file contents to exactly `1.13.0` (no trailing newline), and in
`Sources/CleanRKit/Constants.swift` change:

```swift
    public static let appVersion = "1.12.3"
```

to:

```swift
    public static let appVersion = "1.13.0"
```

- [ ] **Step 2: Run the full local gate**

Run: `bash scripts/check-version-sync.sh && swift build && swift test`
Expected: `Version sync OK: 1.13.0`, `Build complete!`, and the full suite passes with 0 failures (UpdateSchedulerTests included).

- [ ] **Step 3: Manual verification (dev-install)**

Run: `bash scripts/dev-install.sh`
Then verify:
- Launch the app. With `lastUpdateCheckDate` unset and a real newer release present, the alert appears ~3s after launch. (To force it during testing, temporarily set the app's `appVersion` lower, or run `defaults delete com.cleanr.app lastUpdateCheckDate` and ensure a newer GitHub release exists.)
- Homebrew install shows "Copy Upgrade Command"; copying puts `brew upgrade --cask cleanr` on the clipboard. Direct install shows "Download" and opens the release page.
- "Skip This Version" then relaunch: no popup for that version. `defaults read com.cleanr.app skippedUpdateVersion` shows the version.
- Settings shows the "Automatically check for updates" toggle (on) and a "Last checked" line after a check. Turning it off and relaunching: no automatic popup.

- [ ] **Step 4: Commit**

```bash
git add VERSION Sources/CleanRKit/Constants.swift
git commit -m "Bump version to 1.13.0 for automatic update checker"
```

---

## Notes for the implementer

- The whole feature is gated behind a real newer release existing on GitHub. There is no fake/auto-pop path; do not add one for testing, use the `defaults`/version tricks in Task 8.
- Do not let the coordinator install anything in place. Homebrew users always get the copyable command; DMG users always get the release link. This is the core safety property of the design.
- Keep all decision logic in `UpdateScheduler`; if you find yourself adding an `if` to the coordinator that decides *whether/what* to show, move it into `UpdateScheduler` with a test.
