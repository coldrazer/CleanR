# Reset App to Defaults (#52) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real “Reset to Defaults” in the Uninstaller: trash caches/prefs/saved state, keep the app.

**Architecture:** Pure `AppResetPolicy` in CleanRKit; `AppReset.plan` in CleanR (mirrors `AppUninstaller`); UninstallerView confirmation + `CleanActions.executeUserClean`.

**Tech Stack:** Swift 6, SwiftUI, XCTest, SafetyGuard, CleaningEngine

## Global Constraints

- One feature per PR (CONTRIBUTING).
- Business logic in CleanRKit; I/O stays in CleanR.
- File deletion only via SafetyGuard + CleaningEngine (`.trash`, never `.dryRun`).
- No force unwraps in production code.
- New strings via `L10n.tr(zh, en, ru)`.
- Do not modify `SafetyGuard` protected-path lists.

## Files

| File | Role |
|---|---|
| `Sources/CleanRKit/AppResetPolicy.swift` | Pure classify / filter |
| `Sources/CleanR/Views/Applications/AppReset.swift` | Plan from selection |
| `Sources/CleanR/Views/Applications/UninstallerView.swift` | Button + alert + action |
| `Tests/CleanRKitTests/AppResetPolicyTests.swift` | Classification + adversarial |
| `Tests/CleanRTests/AppResetTests.swift` | Plan never includes bundle / user data |

## Tasks

- [x] Spec written
- [x] RED: AppResetPolicyTests
- [x] GREEN: AppResetPolicy
- [x] RED: AppResetTests
- [x] GREEN: AppReset.plan
- [x] Wire UninstallerView
- [x] `swift test` full suite (684 passed, 3 skipped, 0 failures)
- [ ] PR
