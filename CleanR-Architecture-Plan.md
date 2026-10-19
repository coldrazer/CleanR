# CleanR — Architecture & Merge Plan

A single macOS Mac-care app **CleanR**, built by merging three downloaded open-source
projects that have been de-branded and re-branded as **Apex Studio_1 / _2 / _3**:

| Downloaded repo | Re-branded as | Code identifiers | License | Stack | Role in CleanR |
|---|---|---|---|---|---|
| **MacSai** | **Apex Studio_1** | `ApexStudio1` / `ApexStudio1Kit` / `ApexStudio1Menu`, `com.apexstudio1.*` | BSD-3-Clause | Swift 6, SwiftUI, SwiftPM | **Foundation.** CleanR forks/evolves this codebase. |
| **PureMac** | **Apex Studio_2** | `ApexStudio2`, `com.apexstudio2.app` | MIT | Swift 5.9, SwiftUI, XcodeGen | **Donor.** Unique features ported *in* as new CleanR-style modules. |
| **Mole** | **Apex Studio_3** | Go module `github.com/apexstudio3/apexstudio3`, binaries `apex`/`apexstudio3` | GPL-3.0 | Go + Bash, terminal CLI/TUI | **Reference only.** We study its *behavior* and reimplement natively in Swift. |

> **Status (2026-10-18):** All three repos are cloned into `_refs/` and fully re-branded
> (0 original brand strings remain). `ApexStudio1Kit` compiles clean. Full app build + the
> 862-test suite need **full Xcode** (CommandLineTools lacks SwiftUI macro plugins + XCTest).

Decisions already made (confirmed):
1. **License strategy:** reimplement Apex Studio_3's (Mole's) CLI features natively in Swift — no GPL-3.0 code copied in. CleanR stays permissively licensed.
2. **Base codebase:** Apex Studio_1 (MacSai) — BSD-3-Clause, modular Swift package, 862-test suite.
3. **This document** comes before any code.

---

## 1. Why this shape

### Why Apex Studio_1 as the base, not Apex Studio_2
- Already split into a shared library (`ApexStudio1Kit`) separate from the app (`ApexStudio1`) and a separate menu-bar process (`ApexStudio1Menu`) — exactly the shape a bigger app needs.
- Larger existing test suite (862 XCTest cases) covering the dangerous surface (`SafetyGuard`, `CleaningEngine`).
- `GRDB.swift` (SQLite) already wired in for persistence — useful for history/logs, which Apex Studio_2 doesn't have a DB layer for.
- BSD-3-Clause and MIT are both permissive; license-wise either base would work. The deciding factor was architecture + test coverage.

### Why not copy Apex Studio_3's code
Apex Studio_3 is GPL-3.0. GPL is **viral by combination, not by proximity**: the moment any GPL source is compiled into or statically linked with CleanR, the *entire resulting binary* must be distributed under GPL-3.0 — including all the Apex Studio_1- and Apex Studio_2-derived code. That forecloses:
- Ever relicensing CleanR, or parts of it, under something else later.
- Any future closed/commercial distribution of any component.

Apex Studio_3's own README asks forks to rename and credit it rather than absorb it, and its maintainer's project doc is explicit that it stays a narrow CLI on purpose — the paid GUI is a *separate* proprietary app that simply shells out to the CLI, never shares source. That's the precedent: **study Apex Studio_3's command behavior, reimplement the logic natively.** Where we want literal CLI parity (see §5), CleanR ships its own `cleanr` binary built from scratch in Swift, not a wrapped/bundled copy of `apexstudio3`.

**Action item:** add a `NOTICE.md` crediting Apex Studio_2 (MIT), Apex Studio_1 (BSD-3-Clause, as the base — its LICENSE file carries forward), and Apex Studio_3 (GPL-3.0, "inspired the design of the following features, no code shared"), the same courtesy Apex Studio_1 already extended to its own upstream projects in its README.

---

## 2. Consolidated feature matrix

All three apps are "CleanMyMac alternatives" with heavy overlap. This table dedupes them into what CleanR actually ships, and where each capability comes from.

### Already in Apex Studio_1 (keep as-is, base unchanged)
| Module | Notes |
|---|---|
| Smart Scan | One-click cleanup+protection+performance run |
| System Junk (16+ categories) | Includes Universal Binary thinning via `lipo` |
| Mail Attachments | Apple Mail, Outlook, Spark |
| Trash Bins | All locations incl. external drives |
| Malware Removal | Signature-based, 3 depths — **no equivalent in Apex Studio_2 or _3** |
| Privacy (browser history/cookies) | Safari/Chrome/Firefox — **no equivalent elsewhere** |
| Saved Wi-Fi | **No equivalent elsewhere** |
| Permissions Overview (TCC) | **No equivalent elsewhere** |
| Optimization (login items) | |
| Maintenance (system tasks) | Free RAM, rebuild LaunchServices, reindex Spotlight, flush DNS, thin TM snapshots |
| Uninstaller + Reset to Defaults | Pattern-matching across 17+ Library subdirs |
| Extensions review | Pref panes, plug-ins, Safari extensions — **no equivalent elsewhere** |
| Updater (Sparkle appcast reader) | |
| Space Lens (treemap) | |
| Large & Old Files | |
| Duplicates + Consolidate (APFS clone) | More advanced than Apex Studio_2's duplicate finder |
| Shredder (secure erase) | **No equivalent elsewhere** |
| Menu-bar widget | Live stats, recommendations, connected devices — **no equivalent elsewhere** |

### Port in from Apex Studio_2 (new modules, built Apex Studio_1-style, MIT notice kept)
| Feature | Source file(s) in Apex Studio_2 | CleanR treatment |
|---|---|---|
| **Similar Photos** (perceptual hash + color + aspect ratio comparison) | `Services/SimilarPhotoFinder.swift` | New `Modules/SimilarPhotos/`. Genuinely unique — neither Apex Studio_1 nor _3 has it. |
| **Scheduled Auto-Clean** | `Services/SchedulerService.swift` | New `Modules/Scheduler/`. Apex Studio_1 has no background scheduling today. |
| **Finder "Uninstall with CleanR" service** | Apex Studio_2's `NSServices`/Info.plist registration | Add a Services menu item wired to Apex Studio_1's Uninstaller module. |
| **AI app cache cleanup** (Ollama, LM Studio) | Part of Apex Studio_2's `ScanEngine`/Locations DB | Fold into Apex Studio_1's `SystemJunk` category list as new entries. |
| **App Updates via Homebrew cask** | `Services/ApplicationUpdater.swift` | New `Modules/Updater/HomebrewUpdates.swift`, sits alongside Apex Studio_1's existing Sparkle-based Updater (they check different update channels — complementary, not duplicate). |
| **10-level heuristic app-file matching engine** (`AppPathFinder`, 120+ Locations DB, 25 per-app Conditions) | `Logic/Scanning/` | Worth diffing against Apex Studio_1's own Uninstaller matcher feature-by-feature during Phase 2 — whichever is more thorough wins, or merge the location databases. |

Not ported (true duplicates, Apex Studio_1's version is equal-or-better): Apex Studio_2's Protection/Performance panel (Apex Studio_1's Permissions+Maintenance covers it), Apex Studio_2's Duplicate Finder (Apex Studio_1's is more advanced), Apex Studio_2's Space Explorer (Apex Studio_1's Space Lens treemap is more advanced), Apex Studio_2's own CLI (`cli/` dir — superseded by §5 below).

### Reimplement from Apex Studio_3 (native Swift, new `cleanr` CLI + TUI, no Go/Bash reused)
| Apex Studio_3 feature | CleanR treatment |
|---|---|
| Live terminal status dashboard (CPU/GPU/mem/disk/network, health score) | New Swift CLI target using Mach APIs — Apex Studio_1's `ApexStudio1Kit/SystemStats` already pulls most of these numbers for the menu-bar widget; reuse that layer instead of writing new system-stats code |
| `purge` (node_modules/target/.build/dist discovery) | New module, same safety rules (skip recently-active, protect git-tracked/keypair dirs) studied from Apex Studio_3's docs, implemented fresh |
| Installer-file finder (DMG/PKG/ISO/XIP) | New module, logic modeled on Apex Studio_3's discovery locations list |
| JSON/NDJSON scripting output | CleanR CLI emits its own JSON schema — not Apex Studio_3's — documented independently |
| Touch ID sudo config, shell completion, Raycast/Alfred launchers | Nice-to-have, later phase |

**Net effect:** CleanR ends up with a GUI app (Apex Studio_1's shape) **and** a companion CLI (closer to Apex Studio_2's existing `cli/` + Apex Studio_3's command surface, but built from scratch), rather than one app for each origin project.

---

## 3. Target architecture

```
CleanR/
├── Sources/
│   ├── CleanR/              (from Apex Studio_1's ApexStudio1) — main SwiftUI app, all feature modules
│   │   ├── Modules/
│   │   │   ├── SystemJunk/ MailAttachments/ TrashBins/        (from Apex Studio_1)
│   │   │   ├── Malware/ Privacy/ WiFi/ AppPermissions/        (from Apex Studio_1)
│   │   │   ├── Optimization/ Maintenance/                     (from Apex Studio_1)
│   │   │   ├── Uninstaller/ Extensions/ Updater/               (from Apex Studio_1 + Apex Studio_2's Homebrew updater)
│   │   │   ├── SpaceLens/ LargeOldFiles/ Duplicates/ Shredder/ (from Apex Studio_1)
│   │   │   ├── SimilarPhotos/         ← NEW, ported from Apex Studio_2
│   │   │   ├── Scheduler/             ← NEW, ported from Apex Studio_2
│   │   │   ├── Purge/                 ← NEW, reimplemented from Apex Studio_3
│   │   │   └── InstallerFinder/       ← NEW, reimplemented from Apex Studio_3
│   │   ├── Services/ ViewModels/ Views/ App/
│   ├── CleanRKit/           (from Apex Studio_1's ApexStudio1Kit) — shared models, SystemStats, Categories, Cleaner core
│   ├── CleanRMenu/          (from Apex Studio_1's ApexStudio1Menu) — menu-bar widget process
│   └── CleanRCLI/           ← NEW executable target, terminal interface
│       (status dashboard, clean/uninstall/purge/analyze commands, JSON output,
│        built on CleanRKit so GUI and CLI share one scanning/cleaning engine)
├── Tests/
│   ├── CleanRTests/ CleanRKitTests/     (Apex Studio_1's existing 862 tests, renamed)
│   └── CleanRCLITests/                  ← NEW
├── Package.swift
├── LICENSE                 (BSD-3-Clause, carried from Apex Studio_1)
└── NOTICE.md               ← NEW: MIT notice for ported Apex Studio_2 code,
                               GPL-3.0 acknowledgment for Apex Studio_3's design inspiration
```

Key principle: **CleanRKit becomes the single shared engine** for both the GUI app and the new CLI, the same way Apex Studio_1 already shares `ApexStudio1Kit` between `ApexStudio1` and `ApexStudio1Menu`. This avoids rebuilding scanning/cleaning logic twice, which is what would happen if the CLI were left as a thin wrapper.

### A build-system wrinkle to resolve in Phase 0
- Apex Studio_1 builds as **pure SwiftPM** (`swift build`, `swift test`), no `.xcodeproj` committed.
- Apex Studio_2 builds via **XcodeGen** generating an `.xcodeproj`, with Sparkle as a dependency and a signing/entitlements setup for Full Disk Access + Services menu registration.
- Full Disk Access, the Finder Services menu item, a LaunchAgent for the menu-bar process, and (if needed) a privileged helper all require real app bundle configuration (Info.plist, entitlements) that's easier to manage with a generated Xcode project than raw SwiftPM executables.
- **Recommendation:** adopt XcodeGen for CleanR (borrowing Apex Studio_2's `project.yml` as a starting point), with SwiftPM still used for the internal library targets (`CleanRKit` etc.) as local packages. This gets both: Apex Studio_2's proven app-bundle/entitlements setup, and Apex Studio_1's modular package structure.

### A detail worth re-verifying before Phase 2
Apex Studio_1's README architecture diagram describes a helper **XPC privileged helper (LaunchDaemon for root ops)**. The actual source only shows `SMAppService`/XPC used for **login-item management** (`LaunchAtLoginManager`, `MenuBarLauncher`) and a `PrivilegedShellRunner.swift` for admin-escalated shell commands — there's no separate XPC helper target in `Package.swift`. Treat the README's helper diagram as aspirational/outdated until confirmed; Apex Studio_2's admin escalation (`NSAppleScript`-based, in `CleaningEngine`) may be the closer model to follow for root-owned deletions.

---

## 4. Naming & branding

**CleanR** is the final app name — distinct from the three re-branded sources (avoids any trademark confusion) and doesn't reuse their icons, wordmarks, or taglines. The sources keep their numbered Apex Studio identities internally for provenance:

- **Apex Studio_1** (base) — code `ApexStudio1*`, bundle `com.apexstudio1.*`, display "Apex Studio_1"
- **Apex Studio_2** (donor) — code `ApexStudio2*`, bundle `com.apexstudio2.app`, display "Apex Studio_2"
- **Apex Studio_3** (CLI reference) — Go module `apexstudio3`, binaries `apex`/`apexstudio3`

When Apex Studio_1 is forked into the CleanR root, its targets are renamed `ApexStudio1*` → `CleanR*` (app `CleanR`, engine `CleanRKit`, menu `CleanRMenu`), and a new `CleanRCLI` target is added.

Still open:
- Bundle ID (e.g. `com.cleanr.app`) and Apple Developer Team for signing/notarization — all three source apps are notarized; CleanR will need its own identity, it can't reuse Apex Studio_1's or Apex Studio_2's.
- App icon — must be original, not a derivative of any of the three.
- Whether the CLI binary is called `cleanr` or something else (Apex Studio_3's binary is `apex`/`apexstudio3`, Apex Studio_2's is `apexstudio2` — pick something that doesn't collide if someone has both installed).

---

## 5. Phased roadmap

**Phase 0 — Fork & rebrand (mechanical work)**
- [x] Clone all three repos into `_refs/` and re-brand to Apex Studio_1/2/3 (0 original brand strings remain).
- [x] Fix pre-existing `TestSupport` target so it's a proper `.testTarget` (original failed `swift build` under Swift 6.4 CommandLineTools).
- [ ] Fork Apex Studio_1 into the CleanR root, rename targets `ApexStudio1*` → `CleanR*`, update `Package.swift`, bundle IDs, Info.plist.
- [ ] Add XcodeGen project config (adapted from Apex Studio_2's `project.yml`).
- [ ] Write `NOTICE.md` with all three projects' attributions.
- [ ] Get a clean `swift build` + `swift test` passing under the new name before touching features (requires full Xcode: `sudo xcodebuild -license accept`).

**Phase 1 — Dedupe pass**
- Diff Apex Studio_2's uninstaller matching engine (`AppPathFinder`, Locations DB, Conditions) against Apex Studio_1's Uninstaller module feature-by-feature. Merge whichever location/condition data is more complete into one engine.
- Decide: keep Apex Studio_1's Duplicate Finder (it's more advanced) and drop Apex Studio_2's version outright.

**Phase 2 — Port Apex Studio_2's unique modules**
- `SimilarPhotos`, `Scheduler`, Homebrew-based `Updater`, AI-tool cache categories, Finder Services integration. Each ported as its own `Modules/X/` directory with its own tests, following Apex Studio_1's existing module pattern.

**Phase 3 — Reimplement Apex Studio_3's CLI surface**
- Stand up `CleanRCLI` executable target on top of `CleanRKit`.
- Implement `status` (reusing `CleanRKit/SystemStats`), `clean`, `uninstall`, `purge`, `installer` commands, each calling the same engine the GUI uses.
- Write CleanR's own safety rules doc (protected paths, dry-run behavior, confirmation prompts) — informed by reading Apex Studio_3's `SECURITY_DESIGN.md` and safety rules for *ideas*, written fresh.

**Phase 4 — Polish & release**
- Full test pass (target: keep Apex Studio_1's 862 tests green plus new coverage for every ported/new module).
- Code signing, notarization under CleanR's own identity.
- README, NOTICE, first release.

---