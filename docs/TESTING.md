# CleanR Testing Plan

This document is the engineering plan for getting CleanR from "65 tests passing" to "real, defensible test coverage." It's both a roadmap for contributors and a public commitment to safety standards.

## TL;DR

**Today:** 65 tests, ~15–20% real coverage. The most safety-critical files (`SafetyGuard`, `CleaningEngine`) are barely tested. There are zero end-to-end tests. The "tests passing" badge is misleading.

**Target:** 85%+ coverage overall, **100% on safety-critical paths** (`SafetyGuard`, `CleaningEngine`, `XPCClient`). Real e2e tests that build a synthetic home directory, run a scan, and verify the cleanup behavior in a sandboxed temp dir. Coverage enforced by CI.

**Effort:** ~15–20 days of focused work, broken into 7 phases that can be tackled independently or by parallel contributors.

---

## The brutal honest baseline

```
Source                        Lines     Tests  Real coverage
─────────────────────────────────────────────────────────────
CleanRKit                     511      ~50         ~70%
CleanR/Core/Cleaner          208       3          <10%   ← SafetyGuard + CleaningEngine
CleanR/Core/Scanner          420       0           0%
CleanR/Core/Cache            273       0           0%
CleanR/Core/FSMonitor        185       0           0%
CleanR/Modules               2454      0           0%    ← 13 modules + 16 categories
CleanR/Services              110       0           0%
CleanR/ViewModels            113       0           0%
CleanRMenu                   500       0           0%
CleanRHelper                 165       0           0%
─────────────────────────────────────────────────────────────
TOTAL                         ~5100     ~65         ~17%
```

What the existing 65 tests actually cover:
- Basic model equality and formatting (FileItem, ScanResult, ScanCategory, AppInfo)
- Path constants (verifying file paths exist and look reasonable)
- Protected-paths blocklist contents (verifying the list, not the gate logic)
- The 10,000-file cap math
- Live filesystem sanity (your `~/Library/Caches` is readable)
- `PlistJunkFilter` (added during the May 2026 bug fix that exposed the false-positive issue)

What's **not** tested (incomplete list):
- `SafetyGuard.validatePath` adversarial inputs (symlinks, traversal, NULL bytes, SIP paths)
- `CleaningEngine.clean` — the actual deletion engine. Dry-run vs trash vs permanent. Error handling.
- Any of the 13 scan modules end-to-end
- 15 of 16 System Junk categories
- `DuplicatesModule`'s progressive hash pipeline
- `SquarifiedTreemap` layout algorithm
- `AppPathFinder`'s 10-level matching engine
- `FSEventMonitor` incremental replay
- GRDB cache layer (migrations, CRUD, WAL behavior)
- XPC privileged helper
- Menu bar Mach API collectors
- Any e2e cycle (scan → results → clean)

---

## Architectural approach: "Sandboxed Logic"

The root cause of low coverage isn't lack of tests — it's that **business logic is tangled with system dependencies**. `FileManager`, `NSWorkspace`, `Process`, Mach APIs, and the actual filesystem are scattered through every module. That makes pure unit testing impossible without spinning up real macOS state.

The fix is the same pattern used for `PlistJunkFilter` during the May 2026 bug fix:

```
┌─────────────────────────────────────────────────┐
│  CleanR target (thin shell)                   │
│  ─────────────────────────                       │
│  - Wires up real system implementations         │
│  - SwiftUI views                                │
│  - View models                                  │
└──────────────┬──────────────────────────────────┘
               │ calls into
               ▼
┌─────────────────────────────────────────────────┐
│  CleanRKit (pure, testable library)           │
│  ──────────────────────────────────             │
│  - All business logic as pure functions         │
│  - System interactions injected as closures     │
│  - No FileManager / NSWorkspace / Process       │
│  - 100% testable from XCTest                    │
└─────────────────────────────────────────────────┘
```

**Rule:** any new business logic added to the project must be:
- A pure function in `CleanRKit`, OR
- A thin wrapper in `CleanR` that calls into a pure Kit function with injected system closures

This is a strict architectural constraint enforced by code review.

---

## Test pyramid

| Layer | % | Where | Speed | Purpose |
|---|---|---|---|---|
| **Unit** (pure logic) | 80% | `Tests/CleanRKitTests/` | <10 ms per test | Catch logic bugs |
| **Integration** (real FS in tmp dir) | 15% | `Tests/CleanRIntegrationTests/` | <1 s per test | Catch wiring bugs |
| **End-to-end** (full scan→clean cycle) | 5% | `Tests/CleanRE2ETests/` | <30 s per test | Catch interaction bugs |

UI tests are deliberately out of scope. SwiftUI views are tested by visual inspection during development and by the SwiftUI framework itself.

---

## Test framework choice

**Migrate from custom `CleanRTestRunner` executable to XCTest.**

| | Current (`CleanRTestRunner`) | After (`XCTest`) |
|---|---|---|
| Test discovery | Manual via `test()` calls | Automatic via XCTest |
| Code coverage | None | Built-in via `swift test --enable-code-coverage` |
| Xcode integration | None | Full (run-on-fail, breakpoints, etc.) |
| Parallel execution | No | Yes |
| Fixture support | DIY | XCTest setUp/tearDown |
| CI integration | Custom | Standard `swift test` |

The `CleanRTestRunner` target was built when only command-line tools were installed (no Xcode). Now that Xcode 16+ is installed and CI uses macos-15, XCTest is unblocked. `CleanRTestRunner` will be removed after migration.

---

## Phase plan

Each phase produces independently shippable value. Phases can be reordered if priorities change. Phases 0 and 2 must come first; everything else can parallelize.

### Phase 0 — Test infrastructure (1–2 days)

**Goal:** XCTest works end-to-end. Coverage is measurable.

- [ ] Fix the existing broken `Tests/CleanRTests/SafetyGuardTests.swift` and `Tests/CleanRKitTests/FileItemTests.swift` so `swift test` runs cleanly
- [ ] Create `Tests/Shared/TestFixtures.swift` with helpers:
  - `withTempHome { fakeHome in ... }` — creates a tmp dir mimicking `~/Library/...` structure, cleans up after
  - `withFakeApp(bundleID:version:at:) { url in ... }` — synthesizes a `.app` bundle on disk
  - `withFakePlist(name:contents:at:) { url in ... }` — writes a plist for tests
  - `withFakeCacheTree(specs:) { ... }` — builds a synthetic `~/Library/Caches` tree
- [ ] Add `Tests/Shared/MockClock.swift` — controllable time for tests of date-based logic
- [ ] Configure `swift test --enable-code-coverage` and document how to view coverage locally
- [ ] Wire `swift test` into CI workflow (`.github/workflows/ci.yml`) — replaces the `CleanRTestRunner` invocation
- [ ] Add coverage threshold check: PR fails if total coverage drops below 80% on safety-critical files

**Acceptance:** `swift test` runs all tests with coverage report. CI runs them on every push.

### Phase 1 — Refactor for testability (3–4 days)

**Goal:** Pure logic from `CleanR/` moved into `CleanRKit/`. System dependencies injected.

Pattern (apply to every category and module):

```swift
// Before: tangled
struct UserCacheCategory: JunkCategory {
    func filter(_ items: [FileItem]) -> [FileItem] {
        items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }
}

// After: pure logic + injection
public enum UserCacheFilter {
    public static func filter(
        _ items: [FileItem],
        fileExists: (URL) -> Bool
    ) -> [FileItem] {
        items.filter { fileExists($0.url) }
    }
}

struct UserCacheCategory: JunkCategory {
    func filter(_ items: [FileItem]) -> [FileItem] {
        UserCacheFilter.filter(items, fileExists: { FileManager.default.fileExists(atPath: $0.path) })
    }
}
```

- [ ] Extract pure logic from all 16 System Junk categories → `CleanRKit/CategoryFilters/`
- [ ] Extract pure logic from each of 13 scan modules → `CleanRKit/ModuleLogic/`
- [ ] Extract `SquarifiedTreemap` algorithm into Kit (currently in `SpaceLensModule`)
- [ ] Extract `AppPathFinder` matching engine into Kit
- [ ] Extract `DuplicatesModule` pipeline into Kit (the hash logic; FileHandle stays in the thin wrapper)
- [ ] Document the pattern in `CONTRIBUTING.md`

**Acceptance:** ≥80% of business logic lives in `CleanRKit` and is referenced by the thin shells in `CleanR/Modules/`.

### Phase 2 — Safety-critical tests (highest priority) (2–3 days)

**Goal:** 100% coverage on the death-and-life files: `SafetyGuard`, `CleaningEngine`. These deserve adversarial testing.

#### `SafetyGuard` adversarial test suite

- [ ] `/System/Library` — rejected (SIP)
- [ ] `/usr/bin/ls` — rejected (protected)
- [ ] `/etc/passwd` — rejected
- [ ] `/Applications/Safari.app` — rejected (Apple system app)
- [ ] `/Applications/Mail.app` — rejected
- [ ] `~/Library/Caches/com.test.foo` — allowed
- [ ] Symlink in tmp pointing at `/System` — rejected after resolve
- [ ] Symlink chain (a→b→/System) — rejected
- [ ] Path with `..` traversal: `/tmp/x/../etc/passwd` — rejected after resolve
- [ ] Path with NULL byte — rejected (security)
- [ ] Empty path — rejected
- [ ] Unicode-tricky paths (RTL override, zero-width chars) — handled, not crashed
- [ ] 10,000 files in one batch — allowed
- [ ] 10,001 files — rejected entirely
- [ ] Mixed batch: 10 safe + 1 unsafe → unsafe one rejected, others continue
- [ ] `validatePath` is idempotent (calling twice gives same result)
- [ ] `isProtectedApp("com.apple.Safari")` — true
- [ ] `isProtectedApp("com.spotify.client")` — false
- [ ] `isSafeForOrphanDeletion` on `~/Library/Caches/x` — true
- [ ] `isSafeForOrphanDeletion` on `~/Library/Preferences/x` — false

#### `CleaningEngine` test suite

Setup: each test uses `withTempHome` to create a tmp tree with known files.

- [ ] `dryRun` mode: file still exists after clean, count returned correctly
- [ ] `trash` mode: file moved to `~/.Trash`, count and bytes returned correctly
- [ ] `permanent` mode: file no longer exists
- [ ] File missing between scan and clean → graceful skip, error logged
- [ ] Permission denied on file → graceful skip, listed in errors
- [ ] 10,001 items submitted → entire batch fails safety validation, nothing deleted
- [ ] Mid-cleanup cancellation (`Task.cancel()`) → respects cancellation, partial result returned
- [ ] Operation log file written for every action
- [ ] Operation log includes ISO8601 timestamp
- [ ] Operation log path is inside `~/Library/Logs/CleanR/` and never escapes
- [ ] Operation log line distinguishes `[DRY-RUN]` from `[REMOVED]`
- [ ] `clean([])` (empty input) → zero counts, no errors, no log entries
- [ ] Mixed safe/unsafe items: safe ones cleaned, unsafe ones skipped with errors

**Acceptance:** ≥95% line coverage on `SafetyGuard.swift` and `CleaningEngine.swift`. All adversarial cases above pass. No `XCTSkip` allowed in this suite.

### Phase 3 — Scan modules (4–5 days)

**Goal:** Every module has integration tests against synthetic fixtures.

For each module (`SystemJunk`, `Malware`, `Privacy`, `Optimization`, `Maintenance`, `Uninstaller`, `Updater`, `SpaceLens`, `LargeOldFiles`, `Duplicates`, `Shredder`, `MailAttachments`, `TrashBins`):

- [ ] Unit tests for the pure filter logic (after Phase 1 extraction)
- [ ] Integration test: build a synthetic fixture matching what the module scans, run the module, assert it finds the expected items and ignores files outside its scope
- [ ] Negative test: scan a clean tree, assert empty result (not a false positive)

For all 16 System Junk categories:

- [ ] Build a category-specific fixture (e.g., for `XcodeJunkCategory`: fake `~/Library/Developer/Xcode/DerivedData/...`)
- [ ] Verify the category finds the right files
- [ ] Verify it ignores files outside its scope
- [ ] Verify `autoSelect` defaults match the safety expectations

**Acceptance:** every module file has a corresponding test file. Coverage ≥80% per module.

### Phase 4 — Algorithms (1–2 days)

**Goal:** The interesting algorithms have property-based tests.

- [ ] **SquarifiedTreemap**: given N nodes with known sizes, assert (a) total output area ≈ container area, (b) aspect ratio of every rect ≤ configurable threshold for top-K, (c) order preserved, (d) empty input returns empty output without crashing, (e) single node fills the entire container
- [ ] **Progressive duplicate detection**: given files with known contents, assert (a) duplicates correctly identified, (b) hard links recognized via inode and not flagged, (c) files >500 MB skipped, (d) parallelism gives same result as sequential
- [ ] **AppPathFinder 10-level matching**: build synthetic apps with various bundle IDs and verify each level catches its case

**Acceptance:** each algorithm has a dedicated test file with property-based assertions.

### Phase 5 — End-to-end (1–2 days)

**Goal:** Real scan→clean cycles in tmp directories.

- [ ] `withTempHome { ... }` setup → register modules → run `ScanCoordinator.scanAll()` → verify results aggregation
- [ ] Smart Scan e2e: synthetic home with junk in 8 categories → run Smart Scan → verify each category found correctly
- [ ] Clean cycle: scan finds N items → cleaning engine removes them in `trash` mode → verify Trash receives them
- [ ] Dry-run e2e: same flow but `dryRun` mode → verify NOTHING deleted, but counts match
- [ ] Cancellation: start scan → cancel mid-way → state returns to `.idle`, no leaked tasks
- [ ] Coordinator state machine: idle → scanning → completed → idle (and failure path)

**Acceptance:** at least one e2e test for the full Smart Scan flow.

### Phase 6 — Adjacent systems (2–3 days)

**Goal:** Subsystems beyond the scan/clean core.

- [ ] **GRDB cache** (`Database.swift`): migrations run forward and back, CRUD on each table works, WAL mode behavior verified, schema version recorded correctly
- [ ] **FSEventMonitor**: receives events when a file is created/modified/deleted in a watched dir, `invalidatedPaths` computes correctly, `getChangesSince` returns historical events
- [ ] **ProcessMonitorAdvanced**: returns reasonable values for self process (we know our own PID), handles missing processes gracefully
- [ ] **NetworkMonitor**: byte counters increase over time, delta computation correct
- [ ] **SystemStatsCollector**: returns reasonable values (CPU 0–100%, memory non-zero, etc.)
- [ ] **XPC helper protocol**: protocol conformance, code signature validation logic
- [ ] **SystemJunkViewModel** state machine: idle → scanning → results → cleaning → done → idle

**Acceptance:** each subsystem has a smoke test verifying it doesn't crash and returns sensible values.

### Phase 7 — Hygiene, CI, badges (1 day)

**Goal:** Make the work visible and enforced.

- [ ] Replace the misleading "tests-65 passing" README badge with an honest **coverage** badge (Codecov or self-hosted)
- [ ] Add a "good first issue: increase coverage for X" template
- [ ] Update `CONTRIBUTING.md` with the testing pattern, fixture helpers, and the architectural rule
- [ ] Delete the `CleanRTestRunner` target once migration is complete
- [ ] Document how to add new tests in the README
- [ ] Add the coverage threshold check (PR blocker if total drops below 80%)
- [ ] Optional: add mutation testing pass (e.g., [muter](https://github.com/muter-mutation-testing/muter)) to validate test quality

**Acceptance:** README badge is honest. CI fails when coverage regresses.

---

## Coverage targets per file

Not all code deserves equal coverage. This table is the contract:

| File / Area | Target | Rationale |
|---|---|---|
| `SafetyGuard.swift` | **100%** | Deletes user data; bugs here cause real loss |
| `CleaningEngine.swift` | **100%** | Same |
| `XPCClient.swift` | **95%** | Privileged operations; code-signature critical |
| `CleanRHelper/*` | **95%** | Runs as root |
| `CleanRKit/*` | **90%** | Pure logic; easiest to test |
| `Core/Scanner/*` | **90%** | Foundation of every module |
| `Core/Cache/Database.swift` | **85%** | Data persistence |
| `Core/FSMonitor/*` | **85%** | Incremental update logic |
| Each Module file | **80%** | User-facing scan logic |
| Each Category file | **80%** | Same |
| `ViewModels/*` | **75%** | State machines |
| SwiftUI Views | **0% (excluded)** | Visual; tested by inspection |
| `CleanRMenu/*` system stats | **70%** | Mach API wrappers |
| **Project total** | **≥85%** | |

---

## Acceptance criteria for "done"

A reasonable observer can run these checks and conclude the project is well-tested:

1. ✅ `swift test --enable-code-coverage` runs cleanly, no skipped tests
2. ✅ Coverage report shows ≥85% line coverage overall
3. ✅ `SafetyGuard.swift` and `CleaningEngine.swift` show 100% line coverage
4. ✅ The README badge displays a real coverage percentage (not just "tests passing")
5. ✅ CI enforces the coverage threshold and blocks PRs that regress
6. ✅ At least one e2e test exercises the full scan→results→clean cycle in a tmp dir
7. ✅ The "architectural rule" (pure logic in Kit, system deps injected) is documented in `CONTRIBUTING.md`
8. ✅ The `CleanRTestRunner` executable target has been removed (migration complete)

---

## Anti-patterns to avoid

The following are tempting but make tests less valuable:

- **Mocking the filesystem entirely.** Real filesystem behavior in a tmp dir is more honest than mocks. Use `withTempHome` instead of stubbing `FileManager`.
- **Testing the framework, not your logic.** Don't test that `FileManager.default.createDirectory` works. Test that *your code calls it correctly with the right args*.
- **One-assertion-per-test cargo cult.** Group related assertions; favor clarity.
- **`XCTAssertNotNil(result)` without checking what `result` is.** Always assert the actual expected value.
- **Snapshot tests for backend logic.** Snapshots are for UI. For logic, assert the actual fields/values.
- **Test code that hides bugs.** If a fixture has to bend over backwards to make a test pass, the production code probably has a design problem worth fixing instead.

---

## Tracking progress

Open one GitHub issue per phase (labeled `testing`, `phase-0` through `phase-7`). Each issue lists the phase's checklist as a task list so progress is visible in the issue view.

Contributors can claim individual checkboxes within a phase rather than the whole phase.

---

## Why this is worth doing

For a Mac utility that deletes user files, **test coverage is a safety story, not a vanity metric**. Right now, the project's safety claims rest on:

- A blocklist of protected paths (well-defined, easy to verify)
- A `SafetyGuard` that we *believe* validates paths correctly (but is barely tested)
- A `CleaningEngine` that we *believe* respects dry-run mode (but is barely tested)

After this plan executes, the safety claims rest on:

- A blocklist of protected paths
- A `SafetyGuard` with 100% coverage and adversarial test cases for symlinks, traversal, NULL bytes, SIP paths, and protected apps
- A `CleaningEngine` with 100% coverage and tests that verify dry-run never deletes, trash mode moves correctly, permanent mode does what it says, errors are handled gracefully, and operations are logged
- End-to-end tests that exercise the full scan→clean cycle against synthetic file trees
- A CI gate that prevents regressions

That's the difference between *claiming* a project is safe and *being able to prove it*.
