import SwiftUI
import AppKit
import CleanRKit

/// Drives the automatic update check and publishes a pending update for the UI.
/// All decisions live in `UpdateScheduler` (pure, unit-tested); this type is
/// glue: read prefs, call the checker, persist the last-check date, publish.
/// Uses async APIs only (no @MainActor completion closures, per the macOS 26
/// off-main SIGTRAP).
@MainActor
@Observable
final class UpdateCoordinator {
    struct PendingUpdate: Identifiable, Equatable {
        let version: String
        let action: UpdateAction
        var id: String { version }
    }

    /// Non-nil when a newer, non-skipped version was found this session.
    var pendingUpdate: PendingUpdate?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let autoCheck = "automaticUpdateChecks"
        static let lastCheck = "lastUpdateCheckDate"
        static let skipped = "skippedUpdateVersion"
    }

    /// Default ON: absent key reads as enabled.
    private var automaticChecksEnabled: Bool {
        defaults.object(forKey: Key.autoCheck) == nil ? true : defaults.bool(forKey: Key.autoCheck)
    }

    private var lastCheck: Date? {
        let t = defaults.double(forKey: Key.lastCheck)
        return t == 0 ? nil : Date(timeIntervalSinceReferenceDate: t)
    }

    /// Run a check if automatic checks are on and one is due. Safe to call on
    /// launch and on app-activation; the persisted last-check date throttles it
    /// to once per `UpdateScheduler.checkInterval`, and one popup per session.
    func runCheckIfDue() async {
        guard automaticChecksEnabled, pendingUpdate == nil else { return }
        guard UpdateScheduler.isCheckDue(now: Date(), lastCheck: lastCheck) else { return }

        let result = await UpdateChecker.check()
        // Stamp the time even on failure so a flaky network can't tight-loop.
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: Key.lastCheck)

        guard UpdateScheduler.shouldPrompt(
            result: result,
            skippedVersion: defaults.string(forKey: Key.skipped)
        ), case .updateAvailable(let version, let url) = result else { return }

        let action = UpdateScheduler.updateAction(
            isHomebrew: UpdateChecker.isHomebrewInstall(),
            releaseURL: url,
            brewCommand: "brew upgrade --cask cleanr"
        )
        pendingUpdate = PendingUpdate(version: version, action: action)
    }

    /// "Skip this version": never prompt for it again.
    func skip(_ version: String) {
        defaults.set(version, forKey: Key.skipped)
        pendingUpdate = nil
    }

    /// "Later": dismiss for now; reappears on the next due check.
    func dismiss() {
        pendingUpdate = nil
    }

    /// Run the popup's primary action (copy brew command, or open the release).
    func performPrimaryAction() {
        switch pendingUpdate?.action {
        case .brewCommand(let cmd):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
        case .openRelease(let url):
            NSWorkspace.shared.open(url)
        case nil:
            break
        }
        pendingUpdate = nil
    }
}
