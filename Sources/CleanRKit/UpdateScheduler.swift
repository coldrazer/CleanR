import Foundation

/// The action the update popup offers, chosen by install source.
public enum UpdateAction: Equatable, Sendable {
    /// Homebrew install: copy this command rather than overwrite the cask.
    case brewCommand(String)
    /// Direct/DMG install: open this release page.
    case openRelease(URL)
}

/// Pure decision logic for the automatic update checker. No I/O, so every rule
/// is deterministic and unit-tested; `UpdateCoordinator` supplies the dates,
/// prefs, and network result.
public enum UpdateScheduler {
    /// Once-a-day cadence, the macOS-standard interval.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Due when we've never checked, or the last check is at least `interval`
    /// old. `now`/`lastCheck` are injected so tests are deterministic.
    public static func isCheckDue(
        now: Date,
        lastCheck: Date?,
        interval: TimeInterval = checkInterval
    ) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Show the popup only for a newer version the user hasn't skipped.
    public static func shouldPrompt(
        result: UpdateChecker.CheckResult,
        skippedVersion: String?
    ) -> Bool {
        guard case .updateAvailable(let version, _) = result else { return false }
        return version != skippedVersion
    }

    /// Homebrew installs copy the upgrade command (overwriting the cask in place
    /// would desync brew's receipt); everyone else opens the release page.
    public static func updateAction(
        isHomebrew: Bool,
        releaseURL: URL,
        brewCommand: String
    ) -> UpdateAction {
        isHomebrew ? .brewCommand(brewCommand) : .openRelease(releaseURL)
    }
}
