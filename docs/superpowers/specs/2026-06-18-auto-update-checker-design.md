# Automatic update checker with notification popup

Date: 2026-06-18
Status: Design (awaiting review)

## Problem

CleanR only checks for its own updates when the user clicks "Check for Updates"
in Settings. Most users never open Settings, so they stay on old versions and
miss fixes. We want the app to detect a newer release on its own and surface it,
without nagging.

## Goal

When a newer stable release exists, show the user a popup that points them to the
right way to update for how they installed the app, on a cadence that does not
annoy. Keep it lightweight, testable, and aligned with how CleanR is actually
distributed (Homebrew cask first, direct DMG second).

## Non-goals

- No Sparkle, no in-app one-click auto-download/install. CleanR is distributed
  primarily through Homebrew; installing a new build in place corrupts brew's
  receipt and causes version drift. An in-app installer is also a new
  security-sensitive code path for an app whose pitch is "notarized, auditable,
  no telemetry."
- No background daemon. Checks run only while the app is open.
- No auto-update of the menu-bar helper as a separate channel; it ships inside
  the main app bundle and updates with it.

## Approach

Extend the existing `UpdateChecker` (GitHub Releases API, semver compare,
Homebrew detection) with:

1. A pure, unit-tested scheduler that decides when a check is due and whether a
   result should be shown to the user.
2. A thin `@MainActor` coordinator in the app that runs the check shortly after
   launch (if due) and once per 24h while running, then presents the popup.
3. A modal popup whose action branches on install source.
4. A Settings toggle to disable automatic checks (manual check stays).

The action the popup offers depends on install source (already detectable via
`UpdateChecker.isHomebrewInstall()`):

- Homebrew install: show the copyable `brew upgrade --cask cleanr` command and
  an "Open Releases" link. Do not attempt to overwrite the cask.
- Direct/DMG install: a "Download" button that opens the release page, plus
  "Later".

## Behavior and UX

Cadence (matches the macOS-standard ~24h interval used by Sparkle and others):

- On launch: if automatic checks are enabled and a check is due (no successful
  check in the last 24h), run one check ~3s after launch so it never blocks
  startup.
- While running: re-check when the app becomes active if a check is due, capped
  to once per 24h via the persisted last-check date.
- Every completed check (success or failure) updates the last-check date so a
  flaky network does not cause a tight retry loop. (Failures are silent; the
  popup only appears on a real newer version.)

Popup rules (gentle-reminder principles):

- Appears only when the check returns a version newer than the running one.
- "Skip this version" persists that version; it is never shown again.
- "Later" dismisses; it can reappear on the next due check (next day, or next
  launch if a day has passed).
- At most one automatic popup per app session.
- Presented as a sheet/alert on the main window; it does not steal focus from
  other apps aggressively.
- The manual "Check for Updates" in Settings is unchanged and always shows its
  result inline (including "up to date").

## Architecture

Pure logic (CleanRKit, fully unit-tested):

- `UpdateChecker` (existing): `isNewer`, `parseLatestRelease`, `isHomebrewInstall`,
  `check()`. Unchanged except possibly a small helper.
- New `UpdateScheduler` (pure, no I/O):
  - `isCheckDue(now: Date, lastCheck: Date?, interval: TimeInterval) -> Bool`
  - `shouldPrompt(result: UpdateChecker.CheckResult, skippedVersion: String?) -> Bool`
  - `updateAction(isHomebrew: Bool) -> UpdateAction` where
    `UpdateAction` is `.brewCommand(String)` or `.openRelease(URL)`.

App wiring (CleanR, thin, `@MainActor`):

- New `Services/UpdateCoordinator.swift`: holds the published "pending update"
  state, runs the check on launch/active when `isCheckDue`, applies
  `shouldPrompt`, and exposes the data the popup binds to. Persists state via the
  keys below. Uses async AppKit/URLSession only (no `@MainActor` completion
  closures, per the macOS 26 trap).
- `CleanRApp` / `ContentView`: presents the update modal bound to the
  coordinator's pending-update state.
- New update modal view (or an `.alert`) in `Views/Shared/`.
- `SettingsPageView`: add an "Automatically check for updates" toggle and a
  "Last checked: ..." line; keep the manual button.

## Persistence (UserDefaults)

- `automaticUpdateChecks: Bool` (default `true`)
- `lastUpdateCheckDate: Date?`
- `skippedUpdateVersion: String?`

## Privacy note (honesty edit)

The app currently advertises "No network access, the app never phones home." An
automatic check makes one outbound GitHub API call. To keep that claim honest:

- Default the toggle ON but make it clearly labeled and easy to turn off.
- Update the README security section to say: no telemetry or analytics; the only
  network call is the update check, which can be disabled.

## Testing (TDD, test-first)

Unit tests (`Tests/CleanRKitTests/UpdateSchedulerTests.swift` plus existing
`UpdateChecker` tests):

- `isCheckDue`: true when never checked; true when last check older than
  interval; false when within interval; boundary at exactly the interval.
- `shouldPrompt`: true for `.updateAvailable` with a non-skipped version; false
  when that version is the skipped version; false for `.upToDate` and `.failed`.
- `updateAction`: `.brewCommand` when Homebrew, `.openRelease` otherwise.
- Extend `isNewer` edge cases if any gaps remain.

Not unit-tested (thin seams + manual verification via dev-install): the SwiftUI
modal presentation, real network fetch, app-lifecycle timing.

## Versioning

New feature, minor bump: 1.12.3 -> 1.13.0.

## Risks / open questions

- Release notes in the popup: show just the version and a link, or pull the
  GitHub release body ("What's new")? Default to version + link for v1; the body
  can be added later.
- Exact re-prompt timing for "Later": re-checking on next due check (24h or next
  launch if a day passed) is the proposed behavior.
