# Forget Saved Wi-Fi (#50) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Protection module to list preferred Wi-Fi networks and forget selected ones via `networksetup` + admin prompt.

**Architecture:** Pure parse/command builders in CleanRKit; Process/osascript injected in CleanR; SwiftUI list + confirm.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `networksetup`, `MaintenanceShell`

## Global Constraints

- One feature per PR (CONTRIBUTING).
- Business logic in CleanRKit; I/O in CleanR with injected runners.
- SSIDs never concatenated unquoted into a shell string.
- No telemetry / network.
- `L10n.tr(zh, en, ru)` for new copy.

## Files

| File | Role |
|---|---|
| `Sources/CleanRKit/PreferredWiFi.swift` | Model, parser, commands |
| `Tests/CleanRKitTests/PreferredWiFiTests.swift` | Parser + quoting |
| `Sources/CleanR/Modules/WiFi/PreferredWiFiClient.swift` | Process + admin |
| `Sources/CleanR/Views/Protection/WiFiNetworksView.swift` | UI |
| `Sources/CleanR/Views/Sidebar/SidebarView.swift` | New item |
| `Sources/CleanR/App/ContentView.swift` | Route |
| `Tests/CleanRTests/PreferredWiFiClientTests.swift` | Injected I/O |

## Tasks

- [x] RED/GREEN Kit parser + commands
- [x] RED/GREEN client
- [x] Sidebar + view
- [x] `swift test` (702 passed, 3 skipped, 0 failures)
- [ ] PR
