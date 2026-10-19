import Foundation
import CleanRKit

/// Pure uninstall decision logic, kept out of the view so it's testable.
///
/// Security review found the view trashed the app bundle with a raw
/// `try? FileManager.default.trashItem(...)` that skipped SafetyGuard, never
/// re-checked protected apps (only the UI hid the button), and swallowed
/// errors. This routes the bundle through the same validated, logged,
/// trash-first CleaningEngine as its leftover files, and refuses protected
/// apps outright.
enum AppUninstaller {
    /// The leftovers that may be pre-checked in the UI when an app is opened in
    /// the uninstaller.
    ///
    /// Anything under a user content root (`~/Documents`, `~/Desktop`, iCloud
    /// Drive, …) stays unchecked. Those matches come from filename heuristics —
    /// Chrome's `includeTerms: ["google", "chrome"]` substring-matches a
    /// personal `~/Documents/Google Docs notes.md` — and pre-checking them means
    /// one click on "Uninstall" moves the user's own files to the Trash behind a
    /// generic "associated files" confirmation. The rows are still listed so the
    /// user can opt in deliberately.
    static func defaultSelectedURLs(
        for files: [FileItem],
        safetyGuard: SafetyGuard = SafetyGuard()
    ) -> Set<URL> {
        Set(files.filter { !safetyGuard.isUserContentPath($0.url) }.map(\.url))
    }

    /// Build the clean plan for uninstalling `app`: the bundle itself plus the
    /// user-selected leftovers, all to be run through `CleaningEngine`.
    ///
    /// Returns `nil` for a protected system app, which must never be removed.
    /// `isProtectedApp` is bundle-id based, so `SafetyGuard.validatePath` (which
    /// is path based) cannot catch this; the check has to live here.
    static func plan(
        app: AppInfo,
        associatedFiles: [FileItem],
        selectedFiles: Set<URL>,
        safetyGuard: SafetyGuard = SafetyGuard()
    ) -> (items: [FileItem], selection: Set<URL>)? {
        guard !safetyGuard.isProtectedApp(app.bundleIdentifier) else { return nil }

        let bundleItem = FileItem(
            url: app.path,
            name: app.name,
            size: app.size,
            allocatedSize: app.size,
            isDirectory: true
        )
        let items = [bundleItem] + associatedFiles
        // The bundle is always removed; leftovers follow the user's selection.
        let selection = selectedFiles.union([app.path])
        return (items, selection)
    }
}
