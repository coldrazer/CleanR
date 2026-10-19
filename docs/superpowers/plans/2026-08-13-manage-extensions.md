# Manage Extensions (#53) Implementation Plan

> **For agentic workers:** Use TDD. One feature per PR.

**Goal:** Applications module that lists third-party preference panes, Internet Plug-Ins, and Safari extensions; Trash only allowlisted user-domain panes/plug-ins/legacy Safari packages; never delete `.appex` under `.app/Contents/`.

**Architecture:** Pure policy + parsers in CleanRKit; injected filesystem / `pluginkit` / workspace in CleanR; SwiftUI list with per-kind actions.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `SafetyGuard`, `CleaningEngine`

## Global Constraints

- One feature per PR (CONTRIBUTING).
- Business logic in CleanRKit; I/O in CleanR with injected closures.
- Trash allowlist is evaluated **before** `SafetyGuard`. Any path containing `.app/Contents/` is refused.
- No `pluginkit -e`. No admin `osascript` in v1.
- `L10n.tr(zh, en, ru)` for new copy.
- No `password` / `secret` / `api_key` / `token` in `Sources/`.

## Files

| File | Role |
|---|---|
| `Sources/CleanRKit/ManagedExtensions.swift` | Models, policy, catalog, pluginkit parser |
| `Tests/CleanRKitTests/ManagedExtensionsTests.swift` | Policy + parser + adversarial paths |
| `Sources/CleanR/Modules/Extensions/ManagedExtensionsClient.swift` | Injected listing + open/reveal |
| `Tests/CleanRTests/ManagedExtensionsClientTests.swift` | Injected I/O, no live pluginkit |
| `Sources/CleanR/Views/Applications/ExtensionsView.swift` | UI |
| `Sources/CleanR/Views/Sidebar/SidebarView.swift` | Item after Uninstaller |
| `Sources/CleanR/App/ContentView.swift` | Route |
| `Sources/CleanRKit/Localization.swift` | Sidebar fallbacks |
| `Tests/CleanRTests/DeepLinkRoutingTests.swift` | `extensions` slug |
| `Tests/CleanRTests/KeyboardShortcutRoutingTests.swift` | ⌘9 still Uninstaller |

## Tasks

- [x] RED/GREEN Kit policy, catalog, pluginkit parser
- [x] RED/GREEN client listing + trash plan
- [x] Sidebar + view + L10n
- [x] `swift test` (702 passed, 3 skipped, 0 failures) + CI secrets grep
- [ ] PR
