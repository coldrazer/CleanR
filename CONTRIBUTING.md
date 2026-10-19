# Contributing to CleanR

Thank you for your interest in contributing! CleanR is a community-driven project and we welcome contributions of all kinds — bug fixes, new features, documentation improvements, and more.

## Code of Conduct

Be respectful, constructive, and inclusive. We're building software together.

## Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/CleanR.git`
3. **Build**: `swift build`
4. **Run tests**: `swift test` (must pass with 0 failures)
5. **Create a branch**: `git checkout -b feature/your-feature`

## Pull Request Guidelines

### Before Submitting

- [ ] Your code compiles with `swift build` (zero errors)
- [ ] All tests pass (`swift test`)
- [ ] You've added tests for new functionality (see "Testing pattern" below)
- [ ] No new compiler warnings introduced
- [ ] You've tested the feature in the running app (not just compilation)
- [ ] Safety-critical changes (`SafetyGuard.swift`, `CleaningEngine.swift`, `PlistJunkFilter.swift`) come with adversarial test cases

### PR Format

```
## Summary
Brief description of what this PR does and why.

## Changes
- Bullet list of specific changes

## Test Plan
- How you tested this
- Edge cases considered

## Screenshots
If UI changes, include before/after screenshots.
```

### PR Size

- Keep PRs focused — one feature or fix per PR
- Large features should be broken into smaller, reviewable chunks
- Refactors should be separate from feature work

### Commit Messages

- Use present tense: "Add feature" not "Added feature"
- First line under 72 characters
- Reference issues when applicable: "Fix #42: handle empty scan results"

## Testing pattern

This is the architectural rule that every PR must follow. It's how the
codebase stays testable without dragging in real filesystem state.

**Rule:** *Business logic lives in `CleanRKit` as pure functions; system
dependencies (`FileManager`, `NSWorkspace`, `Process`, Mach APIs) are injected
as closures at the boundary.* The thin wrappers in the `CleanR` target are
where real implementations get wired up.

### Example: the `PlistJunkFilter` pattern

```swift
// ❌ Don't do this — untestable, mixes logic with FS calls
struct BrokenPreferencesCategory: JunkCategory {
    func filterBroken(_ items: [FileItem]) -> [FileItem] {
        items.filter { item in
            guard let data = try? Data(contentsOf: item.url) else { return true }
            // ... decision logic mixed with FS state ...
        }
    }
}

// ✅ Do this — pure function in Kit, injected loader, fully testable
public enum PlistJunkFilter {
    public static func isLikelyBroken(
        at url: URL,
        loadData: (URL) -> Data?,                  // injected
        appExistsForBundleID: (String) -> Bool     // injected
    ) -> Bool {
        // pure decision logic — no I/O
    }
}

// And the thin wrapper in CleanR target
struct BrokenPreferencesCategory: JunkCategory {
    func filterBroken(_ items: [FileItem]) -> [FileItem] {
        items.filter { item in
            PlistJunkFilter.isLikelyBroken(
                at: item.url,
                loadData: { try? Data(contentsOf: $0) },
                appExistsForBundleID: { NSWorkspace.shared.urlForApplication(...) != nil }
            )
        }
    }
}
```

### Available test fixtures

Use these helpers from `Tests/CleanRTestSupport/` so your tests don't touch
the real home directory:

- `TestFixtures.withTempDir { dir in ... }` — temp dir, auto-cleaned
- `TestFixtures.withTempHome { fakeHome in ... }` — synthetic `~/Library/...` tree
- `TestFixtures.writeFakeApp(at:bundleIdentifier:name:)` — synthetic `.app` bundle
- `TestFixtures.writePlist(_:to:)` and `writeCorruptPlist(at:)` — synthetic plists
- `TestFixtures.writeFile(at:size:modificationDate:contents:)` — synthetic files
- `MockClock` — controllable time for date-based logic

### Where tests live

- `Tests/CleanRKitTests/` — pure unit tests against `CleanRKit` only
- `Tests/CleanRTests/` — integration tests that exercise the `CleanR` shell
- `Tests/CleanRTestSupport/` — shared fixture helpers (don't add test cases here)

## Code Style

### Swift Conventions

- **Swift 6** with strict concurrency — use actors, `@Sendable`, `async/await`
- Use `@Observable` for view models (not `ObservableObject`)
- Prefer `async/await` over completion handlers
- Use `TaskGroup` for parallel work
- No force unwrapping (`!`) except in tests

### Architecture

- **Modules** implement the `ScanModule` protocol
- **Views** use `ModuleContainerView` for consistent scan/results/done flow
- **Safety first** — all file operations go through `SafetyGuard` and `CleaningEngine`
- Keep scanning logic in modules, not in views

### File Organization

```
New module? Follow this structure:
Sources/CleanR/Modules/YourModule/
├── YourModuleModule.swift      # Implements ScanModule
└── (optional helpers)

Sources/CleanR/Views/YourSection/
└── YourModuleView.swift        # SwiftUI view
```

### What NOT to Do

- Don't bypass `SafetyGuard` for file operations
- Don't add network calls without discussion (CleanR is offline-first)
- Don't add telemetry or analytics
- Don't add third-party dependencies without an issue discussion first
- Don't modify protected paths lists without security review

## Types of Contributions

### Bug Reports

Open an issue with:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Console output (if relevant)

### Feature Requests

Open an issue describing:
- What the feature does
- Why it's useful
- How CleanMyMac (or similar tools) handle it (if applicable)

### New Scan Categories

To add a new System Junk category:
1. Create a new file in `Sources/CleanR/Modules/SystemJunk/Categories/`
2. Implement the `JunkCategory` protocol
3. Add it to the `SystemJunkModule` categories array
4. Add a corresponding `ScanCategory` enum case
5. Add tests in `Tests/`

### New Modules

To add a new scan module:
1. Create `Sources/CleanR/Modules/YourModule/YourModuleModule.swift`
2. Implement `ScanModule` protocol
3. Create the view in `Sources/CleanR/Views/`
4. Add sidebar entry in `SidebarView.swift`
5. Wire it up in `ContentView.swift`
6. Register in `AppState.swift`
7. Add tests

## Security

If you discover a security vulnerability, please **do not** open a public issue. Instead, email the maintainers directly. We take security seriously and will respond promptly.

### Security Review Required For

- Changes to `SafetyGuard.swift`
- Changes to protected paths in `Constants.swift`
- Changes to `CleaningEngine.swift`
- Changes to XPC helper operations
- Any new file deletion logic

## Development Tips

### Running the App

```bash
# Quick launch (builds + creates .app bundle + opens)
swift build && cp "$(swift build --show-bin-path)/CleanR" \
  /tmp/CleanR.app/Contents/MacOS/CleanR && \
  open /tmp/CleanR.app
```

### Dry-Run Mode

The cleaning engine defaults to `dryRun` mode during development. To test actual cleaning:
1. Change `.dryRun` to `.trash` in the relevant view's `clean()` method
2. **Never** use `.permanent` during development
3. Revert before committing

### Full Disk Access

Some modules need FDA to find results. If your scan returns empty:
1. Build the app bundle (see README)
2. Grant FDA in System Settings
3. Restart the app

## Questions?

Open a discussion or issue — we're happy to help you get started.
