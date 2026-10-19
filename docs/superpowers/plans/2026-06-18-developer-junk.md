# Developer & AI Tool Junk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a "Developer Junk" junk-scan category (cache-only, for npm/Cargo/Gradle/pip/Homebrew + Claude/Codex/Antigravity/Cursor) and an advanced "Reclaim Docker Space" Maintenance task.

**Architecture:** Pure-data category + constants in CleanRKit run through the existing TargetedScanner/SafetyGuard/trash-first engine. Docker is a `MaintenanceTask` special-cased in `MaintenanceExecutor` (CLI-gated, `docker system prune`). Safety boundary is the explicit target list, enforced by a unit test.

**Tech Stack:** Swift 6, XCTest. No new dependencies.

---

## File Structure
- Modify: `Sources/CleanRKit/Constants.swift`: dev/AI cache path constants.
- Modify: `Sources/CleanRKit/Models/ScanCategory.swift`: `.developerJunk` case + metadata.
- Create: `Sources/CleanRKit/Categories/DeveloperJunkCategory.swift`: the category.
- Modify: `Sources/CleanR/Modules/SystemJunk/SystemJunkModule.swift`: register it.
- Modify: `Sources/CleanRKit/MaintenanceTask.swift`: `.pruneDocker` case + `resolveDockerPath`.
- Modify: `Sources/CleanR/Modules/Maintenance/MaintenanceModule.swift`: executor special-case.
- Create: `Tests/CleanRKitTests/DeveloperJunkCategoryTests.swift`.
- Modify: `Tests/CleanRKitTests/MaintenanceTaskTests.swift`, `MaintenanceTaskPrivilegeTests.swift`, `Tests/CleanRTests/SystemJunkModuleTests.swift`.
- Modify: `VERSION`, `Sources/CleanRKit/Constants.swift` (appVersion): 1.14.0.

No `Co-Authored-By` / AI-attribution in commits. All user-facing strings via `L10n.tr`.

---

### Task 1: ScanCategory.developerJunk

**Files:** Modify `Sources/CleanRKit/Models/ScanCategory.swift`

- [ ] **Step 1: Add the case + all metadata (exhaustive switches must compile)**

Add the case after `case appLeftovers = "app_leftovers"`:
```swift
    case developerJunk = "developer_junk"
```
Add to `displayName` (after the `.appLeftovers` arm):
```swift
        case .developerJunk: L10n.tr("开发者垃圾", "Developer Junk")
```
Add to `subtitle`:
```swift
        case .developerJunk: L10n.tr("包管理器和 AI 工具的可重建缓存。", "Regenerable caches from package managers and AI tools.")
```
Add to `systemImage`:
```swift
        case .developerJunk: "curlybraces"
```
In `autoSelect`, add `.developerJunk` to the `false` group so the user reviews before cleaning (it touches AI tool cache dirs):
```swift
        case .unusedDiskImages, .largeFiles, .oldFiles, .duplicates,
             .universalBinaries, .appLeftovers, .developerJunk:
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/CleanRKit/Models/ScanCategory.swift
git commit -m "Add developerJunk ScanCategory"
```

---

### Task 2: Constants + DeveloperJunkCategory + register (TDD)

**Files:**
- Create: `Tests/CleanRKitTests/DeveloperJunkCategoryTests.swift`
- Modify: `Sources/CleanRKit/Constants.swift`
- Create: `Sources/CleanRKit/Categories/DeveloperJunkCategory.swift`
- Modify: `Sources/CleanR/Modules/SystemJunk/SystemJunkModule.swift`
- Modify: `Tests/CleanRTests/SystemJunkModuleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CleanRKitTests/DeveloperJunkCategoryTests.swift`:
```swift
import XCTest
@testable import CleanRKit

final class DeveloperJunkCategoryTests: XCTestCase {
    private var paths: [String] {
        DeveloperJunkCategory().targets.map { $0.path.path(percentEncoded: false) }
    }

    func testIncludesExpectedSafeCaches() {
        let p = paths
        func has(_ suffix: String) -> Bool { p.contains { $0.hasSuffix(suffix) } }
        XCTAssertTrue(has("/.npm/_cacache"))
        XCTAssertTrue(has("/.cargo/registry/cache"))
        XCTAssertTrue(has("/.cargo/registry/src"))
        XCTAssertTrue(has("/.gradle/caches"))
        XCTAssertTrue(has("/Library/Caches/Homebrew"))
        XCTAssertTrue(has("/Library/Caches/pip"))
        XCTAssertTrue(has("/.claude/cache"))
        XCTAssertTrue(has("/.codex/.tmp"))
        XCTAssertTrue(p.contains { $0.contains("Application Support/Antigravity/") && $0.hasSuffix("/Cache") })
        XCTAssertTrue(p.contains { $0.contains("Application Support/Cursor/") && $0.hasSuffix("/Cache") })
    }

    // Load-bearing safety test: never target user data.
    func testNeverTargetsUserData() {
        let forbidden = [
            "/.claude/projects", "/.claude/file-history",
            "/.codex/sessions", "/.codex/archived_sessions",
            "/extensions", "/Antigravity/User", "/Cursor/User",
            "com.docker.docker", "Docker.raw",
        ]
        for path in paths {
            for bad in forbidden {
                XCTAssertFalse(path.contains(bad), "Developer Junk must never target \(bad), found in \(path)")
            }
        }
    }

    func testTargetsAreNonRecursive() {
        XCTAssertTrue(DeveloperJunkCategory().targets.allSatisfy { !$0.recursive })
    }
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `swift test --filter DeveloperJunkCategoryTests`
Expected: FAIL to build, "cannot find 'DeveloperJunkCategory' in scope".

- [ ] **Step 3: Add the constants**

In `Sources/CleanRKit/Constants.swift`, after the `// MARK: - Dev Tool Caches` block (the one with `homebrewCache`/`npmCache`/`pipCache`/`cargoRegistry`), add:
```swift
    // MARK: - Developer & AI Tool Caches
    //
    // Cache-only. The tools below keep history/memory/sessions/extensions right
    // next to these caches; those are user data and are deliberately NOT listed.

    // npm's real cache on macOS is ~/.npm/_cacache (not ~/Library/Caches/npm).
    public static let npmCacache = home.appending(path: ".npm/_cacache")
    public static let cargoRegistryCache = home.appending(path: ".cargo/registry/cache")
    public static let cargoRegistrySrc = home.appending(path: ".cargo/registry/src")
    public static let gradleCaches = home.appending(path: ".gradle/caches")
    public static let gradleDaemon = home.appending(path: ".gradle/daemon")
    public static let gradleWrapperDists = home.appending(path: ".gradle/wrapper/dists")

    public static let claudeCache = home.appending(path: ".claude/cache")
    public static let claudePasteCache = home.appending(path: ".claude/paste-cache")
    public static let claudeShellSnapshots = home.appending(path: ".claude/shell-snapshots")
    public static let codexTmp = home.appending(path: ".codex/.tmp")
    public static let codexCache = home.appending(path: ".codex/cache")

    /// Standard VS Code-family Electron cache dirs under Application Support.
    /// `User/` and installed `extensions` are excluded (user data / software).
    public static func electronEditorCaches(_ appSupportName: String) -> [URL] {
        let base = userAppSupport.appending(path: appSupportName)
        return ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedProfilesData"]
            .map { base.appending(path: $0) }
    }
    public static var antigravityCaches: [URL] { electronEditorCaches("Antigravity") }
    public static var cursorCaches: [URL] { electronEditorCaches("Cursor") }
```

- [ ] **Step 4: Create the category**

Create `Sources/CleanRKit/Categories/DeveloperJunkCategory.swift`:
```swift
import Foundation

/// Regenerable caches from package managers and AI coding tools. Cache-only:
/// the matching history/memory/sessions/extensions live elsewhere and are never
/// targeted (see DeveloperJunkCategoryTests.testNeverTargetsUserData).
public struct DeveloperJunkCategory: JunkCategory {
    public init() {}
    public let scanCategory = ScanCategory.developerJunk
    public var targets: [ScanTarget] {
        var paths: [URL] = [
            MCConstants.npmCacache,
            MCConstants.cargoRegistryCache,
            MCConstants.cargoRegistrySrc,
            MCConstants.gradleCaches,
            MCConstants.gradleDaemon,
            MCConstants.gradleWrapperDists,
            MCConstants.homebrewCache,
            MCConstants.pipCache,
            MCConstants.claudeCache,
            MCConstants.claudePasteCache,
            MCConstants.claudeShellSnapshots,
            MCConstants.codexTmp,
            MCConstants.codexCache,
        ]
        paths += MCConstants.antigravityCaches
        paths += MCConstants.cursorCaches
        return paths.map { ScanTarget(path: $0, recursive: false) }
    }
}
```

- [ ] **Step 5: Register in the module + bump its count test**

In `Sources/CleanR/Modules/SystemJunk/SystemJunkModule.swift`, add to `allCategories` after `AppLeftoversCategory(),`:
```swift
        DeveloperJunkCategory(),
```
In `Tests/CleanRTests/SystemJunkModuleTests.swift:9`, change `17` to `18`:
```swift
        XCTAssertEqual(SystemJunkModule.allCategories.count, 18)
```

- [ ] **Step 6: Run tests, verify pass**

Run: `swift test --filter DeveloperJunkCategoryTests && swift test --filter SystemJunkModuleTests`
Expected: PASS.

- [ ] **Step 7: Commit**
```bash
git add Sources/CleanRKit/Constants.swift Sources/CleanRKit/Categories/DeveloperJunkCategory.swift Sources/CleanR/Modules/SystemJunk/SystemJunkModule.swift Tests/CleanRKitTests/DeveloperJunkCategoryTests.swift Tests/CleanRTests/SystemJunkModuleTests.swift
git commit -m "Add DeveloperJunkCategory (cache-only dev + AI tool junk)"
```

---

### Task 3: MaintenanceTask.pruneDocker + resolveDockerPath (TDD)

**Files:**
- Modify: `Sources/CleanRKit/MaintenanceTask.swift`
- Modify: `Tests/CleanRKitTests/MaintenanceTaskTests.swift`, `Tests/CleanRKitTests/MaintenanceTaskPrivilegeTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/CleanRKitTests/MaintenanceTaskTests.swift`, change the count assertion from `9` to `10`:
```swift
        XCTAssertEqual(MaintenanceTask.allCases.count, 10)
```
Append a new method to `MaintenanceTaskTests`:
```swift
    func testPruneDockerMetadata() {
        let t = MaintenanceTask.pruneDocker
        XCTAssertEqual(t.severity, .advanced)
        XCTAssertNil(t.systemCommand)              // executor special-cases it
        XCTAssertFalse(t.sideEffects.isEmpty)
    }

    func testResolveDockerPathReturnsFirstExisting() {
        let only = "/opt/homebrew/bin/docker"
        let path = MaintenanceTask.resolveDockerPath { $0 == only }
        XCTAssertEqual(path, only)
    }

    func testResolveDockerPathNilWhenNoneExist() {
        XCTAssertNil(MaintenanceTask.resolveDockerPath { _ in false })
    }
```
In `Tests/CleanRKitTests/MaintenanceTaskPrivilegeTests.swift`, append inside the existing test class a new method:
```swift
    func testPruneDockerRunsAsUser() {
        XCTAssertFalse(MaintenanceTask.pruneDocker.requiresAdmin)
    }
```

- [ ] **Step 2: Run, verify it fails**

Run: `swift test --filter MaintenanceTaskTests`
Expected: FAIL, "type 'MaintenanceTask' has no member 'pruneDocker'".

- [ ] **Step 3: Implement the case + all switch arms + resolver**

In `Sources/CleanRKit/MaintenanceTask.swift`:

Add the case after `case thinTimeMachineSnapshots = "Thin Time Machine Snapshots"`:
```swift
    case pruneDocker = "Reclaim Docker Space"
```
`title` arm:
```swift
        case .pruneDocker: L10n.tr("回收 Docker 空间", rawValue)
```
`icon` arm:
```swift
        case .pruneDocker: "shippingbox"
```
`description` arm:
```swift
        case .pruneDocker:
            L10n.tr("清理未使用的 Docker 镜像、已停止的容器和构建缓存", "Remove unused Docker images, stopped containers, and build cache")
```
`severity`: add `.pruneDocker` to the `.advanced` group:
```swift
        case .speedUpMail,
             .rebuildLaunchServices,
             .reindexSpotlight,
             .thinTimeMachineSnapshots,
             .pruneDocker:
            .advanced
```
`sideEffects` arm:
```swift
        case .pruneDocker:
            L10n.tr("运行 `docker system prune`，删除未使用的镜像、已停止的容器、未使用的网络和构建缓存。此操作不可撤销（不会进入废纸篓）。正在运行的容器、使用中的镜像和命名卷不受影响，磁盘映像 Docker.raw 也不会被直接删除。", "Runs `docker system prune`, removing unused images, stopped containers, unused networks, and build cache. This is irreversible (it does not go to the Trash). Running containers, in-use images, and named volumes are untouched, and the Docker.raw disk image is never deleted directly.")
```
`requiresAdmin`: add `.pruneDocker` to the `false` group:
```swift
        case .verifyStartupDisk, .speedUpMail, .rebuildLaunchServices,
             .flushDNSCache, .pruneDocker:
            false
```
`systemCommand` arm (nil; executor special-cases it like speedUpMail):
```swift
        case .pruneDocker:
            nil
```
Add the resolver inside the enum (after `systemCommand`):
```swift
    /// Where the Docker CLI may live, in priority order. Pure data so the
    /// resolver is unit-testable.
    public static let dockerCandidatePaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    /// First candidate path for which `existing` is true, or nil if Docker
    /// isn't installed. `existing` is injected so tests don't touch the disk.
    public static func resolveDockerPath(existing: (String) -> Bool) -> String? {
        dockerCandidatePaths.first(where: existing)
    }
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter MaintenanceTaskTests && swift test --filter MaintenanceTaskPrivilegeTests`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/CleanRKit/MaintenanceTask.swift Tests/CleanRKitTests/MaintenanceTaskTests.swift Tests/CleanRKitTests/MaintenanceTaskPrivilegeTests.swift
git commit -m "Add pruneDocker MaintenanceTask + docker path resolver"
```

---

### Task 4: Executor runs Docker prune

**Files:** Modify `Sources/CleanR/Modules/Maintenance/MaintenanceModule.swift`

- [ ] **Step 1: Special-case pruneDocker in execute()**

In `execute(_:)`, just after the `if case .speedUpMail = task { return await reindexMail() }` line, add:
```swift
        if case .pruneDocker = task { return await pruneDocker() }
```

- [ ] **Step 2: Add the pruneDocker method**

Add this method to `MaintenanceExecutor` (e.g. after `reindexMail()`):
```swift
    private func pruneDocker() async -> TaskResult {
        guard let docker = MaintenanceTask.resolveDockerPath(existing: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            return TaskResult(
                task: .pruneDocker, success: false, output: "",
                error: L10n.tr("未找到 Docker 命令行工具。请确认已安装 Docker Desktop。",
                               "Docker CLI not found. Make sure Docker Desktop is installed."))
        }
        return await runProcess(task: .pruneDocker, command: docker, args: ["system", "prune", "-f"])
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**
```bash
git add Sources/CleanR/Modules/Maintenance/MaintenanceModule.swift
git commit -m "Execute Docker prune (CLI-gated) in MaintenanceExecutor"
```

---

### Task 5: Version bump 1.14.0 + full gate + manual verification

**Files:** Modify `VERSION`, `Sources/CleanRKit/Constants.swift`

- [ ] **Step 1: Bump**

Set `VERSION` to exactly `1.14.0`, and in `Sources/CleanRKit/Constants.swift` change `appVersion = "1.13.0"` to `appVersion = "1.14.0"`.

- [ ] **Step 2: Full gate**

Run: `bash scripts/check-version-sync.sh && swift build && swift test`
Expected: `Version sync OK: 1.14.0`, `Build complete!`, full suite passes (new tests included).

- [ ] **Step 3: Manual verification (dev-install)**

Run: `bash scripts/dev-install.sh`
Then verify:
- System Junk lists a **Developer Junk** group; expanding it shows npm/Cargo/Homebrew/Claude/Codex/etc. cache items (only those present on disk), nothing auto-checked.
- Smart Scan includes Developer Junk in its sweep.
- Maintenance shows **Reclaim Docker Space** with the advanced (triangle) icon; tapping it opens the confirmation with the side-effects text. With Docker installed it runs `docker system prune -f`; without it, it reports "Docker CLI not found."

- [ ] **Step 4: Commit**
```bash
git add VERSION Sources/CleanRKit/Constants.swift
git commit -m "Bump version to 1.14.0 for developer junk + Docker prune"
```

---

## Notes for the implementer
- The MaintenanceView renders `MaintenanceTask.allCases`, so `pruneDocker` appears automatically with the advanced-confirmation path. No view change needed.
- Never widen the Developer Junk target list to whole tool directories. The exclusion test is the safety contract.
