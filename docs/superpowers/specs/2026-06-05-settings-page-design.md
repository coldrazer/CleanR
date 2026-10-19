# In-App Settings Page: Design

Date: 2026-06-05
Target version: 1.10.0

## Goal

Replace the separate macOS Settings window with an in-app Settings page that lives in the
detail pane, opened from a pinned sidebar footer button. Add an appearance override
(light/dark/system), launch at login, a Homebrew-aware update check, and an About section.
The Menu Bar Widget toggle moves into this page and the sidebar footer toggle is removed.

## Navigation and entry points

- New `SidebarItem.settings` case ("Settings", icon `gearshape`, deep link slug `settings`).
  It is excluded from the scrolling sidebar sections.
- New neutral graphite `ModuleTheme.settings` case (gradient, button colors, accent).
- The sidebar footer is replaced: the Menu Bar Widget toggle row goes away, and a pinned
  "Settings" row takes its place. Clicking it sets `selectedSidebarItem = .settings`.
  The row draws a selected background when the page is active. Because no List row carries
  the `.settings` tag, the List selection clears automatically.
- The `Settings { }` scene in `CleanRApp` is removed. A
  `CommandGroup(replacing: .appSettings)` provides "Settings…" with Cmd-comma, routing to
  the in-app page so the standard shortcut and app menu item keep working.
- `cleanr://module/settings` deep links to the page (works automatically through
  `SidebarItem(deepLinkID:)`).
- `ContentView.moduleView(for:)` gains a `.settings` case returning the new page. The
  keep-alive `visited` machinery applies unchanged.

## Settings page content

A new `SettingsPageView` (replacing `SettingsView`) rendered as a native
`.formStyle(.grouped)` form with `scrollContentBackground(.hidden)` over the graphite
gradient. Sections top to bottom:

1. **Header**: "CleanR" plus `MCConstants.appVersion`, trailing "Check for updates"
   button with inline states: idle, checking (spinner), up to date, update available.
2. **General**:
   - *Launch at login* (new): `SMAppService.mainApp` register/unregister, default off,
     caption: "Open CleanR automatically when you sign in to macOS. You can also manage
     this in System Settings > General > Login Items." Status and error surfacing mirror
     the `MenuBarLauncher` pattern (requiresApproval and friends).
   - *Menu Bar Widget*: the existing toggle, status row, and error label move here
     unchanged. This page becomes the only place to toggle the widget.
3. **Appearance**: segmented picker Light | Dark | System, default System.
4. **Language Cleanup**: existing section carried over unchanged.
5. **About**: three full-row external links, each with a circular tinted icon badge,
   title, caption, and a trailing up-right arrow; the whole row is clickable and opens
   the browser:
   - Source code: repository home page.
   - Report an issue: issues/new/choose.
   - Release notes: releases page.

## Appearance override

- `AppearanceMode: String, CaseIterable` with cases `system`, `light`, `dark`, stored in
  `@AppStorage("appearanceMode")`, default `system`.
- Applied via `NSApp.appearance = nil | NSAppearance(named: .aqua) | .darkAqua` at launch
  (in `applicationDidFinishLaunching`, already on the main thread) and on change from the
  picker. No `@MainActor` completion-closure patterns (macOS 26 SIGTRAP rule, issue #58).
- The menu bar helper is a separate process and keeps following the system appearance.
  Out of scope.

## Update checker

- New `UpdateChecker` in CleanRKit. GET
  `https://api.github.com/repos/cleanr/CleanR/releases/latest` (URLSession, short
  timeout), parse `tag_name` (strip leading "v"), compare to `MCConstants.appVersion`
  with numeric semver component comparison.
- Result type: `upToDate`, `updateAvailable(version: String, url: URL)`,
  `failed(message: String)`.
- Homebrew detection: installed-via-brew when `/opt/homebrew/Caskroom/cleanr` or
  `/usr/local/Caskroom/cleanr` exists (paths injectable for tests).
- When an update is available: brew installs get a copyable
  `brew upgrade --cask cleanr` row; direct installs get a button opening the release
  page.
- Manual check only. No network calls at launch.

## Testing

- Semver comparison edge cases (equal, patch/minor/major newer, malformed tags).
- Release JSON parsing from a fixture (no live network in tests).
- Homebrew detection with injected paths.
- `AppearanceMode` to `NSAppearance` name mapping.
- `settings` deep link slug round-trip.

## Process

- Version bump to 1.10.0 (minor: new features).
- Local gate before push: `bash scripts/check-version-sync.sh && swift build && swift test`.
- Ship via branch and PR per repo workflow.
