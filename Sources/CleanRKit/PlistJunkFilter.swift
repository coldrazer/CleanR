import Foundation

/// Pure, system-independent filter for deciding whether a preferences plist
/// is genuinely junk and safe to surface for deletion.
///
/// **Safety contract:** This function must never flag legitimate Apple system
/// preferences or third-party preferences whose owning app simply isn't
/// currently registered with Launch Services. False positives here cause real
/// data loss / system instability (e.g., deleting `com.apple.loginwindow.plist`
/// can break login on next boot).
public enum PlistJunkFilter {

    /// Returns `true` if the plist at `url` should be flagged as broken/junk.
    ///
    /// - Parameter url: The full URL of the `.plist` file under inspection.
    /// - Parameter loadData: Closure that loads the file's bytes. Injected so
    ///   tests can supply synthetic data without disk I/O.
    /// - Parameter appExistsForBundleID: Closure that returns true if any
    ///   installed app uses the given bundle identifier. Kept in the signature
    ///   for future opt-in modes (currently unused — see below).
    public static func isLikelyBroken(
        at url: URL,
        loadData: (URL) -> Data?,
        appExistsForBundleID: (String) -> Bool
    ) -> Bool {
        guard url.pathExtension == "plist" else { return false }

        // SAFETY: Never touch Apple-owned preference domains.
        let name = url.deletingPathExtension().lastPathComponent
        if isAppleSystemDomain(name) { return false }

        // SAFETY: Only flag plists that are PROVABLY corrupt — fail to parse.
        //
        // The `appExistsForBundleID` parameter is intentionally unused here.
        // Any future "orphan detection" mode must be opt-in, never auto-select,
        // and skip Apple domains.
        _ = appExistsForBundleID

        guard let data = loadData(url) else {
            // Couldn't read the file — don't blindly flag.
            return false
        }

        do {
            _ = try PropertyListSerialization.propertyList(from: data, format: nil)
            return false
        } catch {
            return true
        }
    }

    /// Returns true if the bundle identifier belongs to an Apple-owned system
    /// or framework domain that we must never touch.
    public static func isAppleSystemDomain(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        return lower.hasPrefix("com.apple.")
            || lower.hasPrefix("group.com.apple.")
    }
}
