# Developer and AI tool junk cleanup

Date: 2026-06-18
Status: Design (approved, ready for plan)

## Problem

Developers accumulate large regenerable caches that CleanR does not currently
clean: package-manager caches (npm, Cargo, Gradle, pip, Homebrew) and the caches
of AI coding tools (Claude, Codex, Antigravity, Cursor). On a real machine these
run to several GB. There is no grouped place to manage them.

Crucially, the biggest folders next to these caches are NOT junk: AI tools keep
session history, memory, and installed extensions right beside their caches, and
Docker keeps its entire image/container/volume store in one disk image. A naive
"clean the tool's folder" would destroy user data.

## Goal

Add a single "Developer Junk" category to the junk scan (and therefore Smart
Scan) that reclaims only genuinely regenerable cache, behind the existing
SafetyGuard and trash-first engine. Handle Docker separately and safely, because
its space cannot be reclaimed by file deletion.

## Non-goals

- No deletion of AI tool history/memory/sessions, installed extensions, app
  settings (`User/`), or Docker's `Docker.raw`. These are user data.
- No `Localizable.strings` migration; new strings use the existing `L10n.tr`.
- No per-tool subgrouping UI beyond what the current grouped-card list provides.

## Approach

### Part A: DeveloperJunkCategory (junk scan)

A new `JunkCategory` with a static `targets` list, added to
`SystemJunkModule.allCategories`. It reuses the existing `TargetedScanner`,
SafetyGuard validation, trash-first deletion, and operation log. Targets that do
not exist on disk simply contribute nothing.

Safe, regenerable targets (cache only):

- npm: `~/.npm/_cacache`
- Cargo: `~/.cargo/registry/cache`, `~/.cargo/registry/src`
- Homebrew: `~/Library/Caches/Homebrew`
- pip: `~/Library/Caches/pip`
- Gradle: `~/.gradle/caches`, `~/.gradle/daemon`, `~/.gradle/wrapper/dists`
- Claude: `~/.claude/cache`, `~/.claude/paste-cache`, `~/.claude/shell-snapshots`
- Codex: `~/.codex/.tmp`, `~/.codex/cache`
- Antigravity: `~/Library/Application Support/Antigravity/Cache`, `Code Cache`,
  `GPUCache`, `CachedData`, `CachedProfilesData`
- Cursor: `~/Library/Application Support/Cursor/Cache`, `Code Cache`, `GPUCache`,
  `CachedData`, `CachedProfilesData`

Hard-excluded user data (must never appear as a target):

- `~/.claude/projects` (memory + session transcripts), `~/.claude/file-history`
- `~/.codex/sessions`, `~/.codex/archived_sessions`
- `~/.antigravity/extensions`, `~/.cursor/extensions`
- The Electron `User/` directory of any tool
- `~/Library/Containers/com.docker.docker/...` and `Docker.raw`

The existing `npmCache` constant points at `~/Library/Caches/npm`, which is not
where npm caches on macOS; it is replaced by `~/.npm/_cacache`. The existing
`cargoRegistry` constant (`~/.cargo/registry`) is narrowed to `cache` and `src`.

### Part B: Docker prune (Maintenance, advanced)

A new `MaintenanceTask` "Reclaim Docker space":

- Runs only if the `docker` CLI is found (e.g. via `/usr/local/bin/docker`,
  `/opt/homebrew/bin/docker`, or `which docker`); otherwise reports "Docker not
  installed" and does nothing.
- Executes `docker system prune` non-interactively (with the force flag), which
  removes unused/dangling images, stopped containers, unused networks, and build
  cache.
- Severity `advanced`, so it routes through the existing confirmation alert. The
  side-effects text states it is irreversible (does not go to the Trash) and that
  it never touches running containers, in-use images, or `Docker.raw`.

This lives in Maintenance rather than the junk scan because it is a tool action,
not a list-files-and-trash operation.

## Safety model

- Part A: the target list is the safety boundary. Every path is a cache subpath
  inside the user's home, validated per-item by SafetyGuard and removed to the
  Trash, with the post-clean log. The exclusion set above is enforced by a unit
  test.
- Part B: gated on the CLI existing, advanced severity with explicit confirmation,
  and scoped to `docker system prune` (which by definition spares in-use data).

## Testing (TDD)

- `DeveloperJunkCategory().targets`: assert it contains the expected safe paths.
- Safety test: assert none of the target paths equals or is contained within any
  excluded user-data path (projects, sessions, archived_sessions, extensions,
  User, Docker). This is the load-bearing test.
- `MaintenanceTask` for Docker: assert it exists, is `.advanced`, has the prune
  command and non-empty side-effects text, and that its CLI-absent path is a
  graceful no-op (testable by injecting a "docker not found" resolver).
- Fold into the existing system-junk-category and maintenance-task test suites.

## Versioning

New feature, minor bump: 1.13.0 -> 1.14.0.

## Risks / open questions

- Cursor's Electron cache path is assumed to follow the VS Code family layout
  under `~/Library/Application Support/Cursor`; verify the exact subdir names
  during implementation and drop any that do not exist.
- `docker system prune` without `--volumes` keeps named volumes; this spec uses
  the default (no `--volumes`) so user data in named volumes is preserved.
