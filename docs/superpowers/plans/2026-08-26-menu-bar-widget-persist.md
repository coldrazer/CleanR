# Menu-bar widget persist (#138) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the menu-bar helper from vanishing: keep-one-instance on duplicate launch, relaunch after unexpected exit while the toggle is on.

**Architecture:** Pure `MenuBarInstancePolicy` + `MenuBarKeepAlivePolicy` in CleanRKit. `MenuBarLauncher` and `CleanRMenuApp` stay thin I/O wrappers. Shared defaults flag for user-quit.

**Tech Stack:** Swift 6, AppKit, SMAppService, XCTest

## Global Constraints

- One feature per PR (CONTRIBUTING).
- Business logic in CleanRKit; I/O stays in CleanR / CleanRMenu.
- Do not call `SMAppService.register` / `unregister` from tests.
- Do not reintroduce a completion-handler `openApplication` (issue #58).
- Do not put `password` / `secret` / `api_key` / `token` in `Sources/`.
- Honest scope: no Control Center overflow claim; no #137 process-memory mix-in.

## Files

| File | Role |
|---|---|
| `Sources/CleanRKit/MenuBarHelperPolicy.swift` | Duplicate keep-one + keep-alive actions + user-quit key |
| `Sources/CleanR/Services/MenuBarLauncher.swift` | Wait-then-open, terminate observer, clear user-quit on enable |
| `Sources/CleanR/App/CleanRApp.swift` | Start watching on launch |
| `Sources/CleanRMenu/CleanRMenuApp.swift` | Policy-based duplicate exit; Quit sets user-quit |
| `Tests/CleanRKitTests/MenuBarHelperPolicyTests.swift` | Policy unit tests |
| `Tests/CleanRTests/MenuBarLauncherTests.swift` | Source guards + existing #58 path |

## Tasks

- [x] RED: MenuBarHelperPolicyTests
- [x] GREEN: MenuBarHelperPolicy
- [x] RED: launcher / helper source guards
- [x] GREEN: wire launcher, helper, AppDelegate, Quit
- [x] `swift test` full suite + CI secrets grep (779 passed, 3 skipped, 0 failures)
- [ ] PR Fixes #138
