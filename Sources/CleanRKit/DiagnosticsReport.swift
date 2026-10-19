import Foundation

/// Builds the user-exported diagnostics text. Everything here is pure and
/// local: the report is written only where the user chooses in a save
/// panel, and home-directory paths are redacted to `~` so a report can be
/// attached to a bug report without publishing the user's account name
/// or folder layout. No network is involved, ever.
public enum DiagnosticsReport {

    /// Replace every occurrence of the home path (and its URL-encoded
    /// form) with `~`. Fails closed: an empty home redacts nothing rather
    /// than mangling the text.
    public static func redact(_ text: String, home: String) -> String {
        guard home.count > 1 else { return text }
        var result = text.replacingOccurrences(of: home, with: "~")
        if let encoded = home.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), encoded != home {
            result = result.replacingOccurrences(of: encoded, with: "~")
        }
        return result
    }

    /// Last `maxLines` lines of a log, oldest dropped first.
    public static func tail(_ log: String, maxLines: Int = 200) -> String {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return log }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    public static func make(
        appVersion: String,
        osVersion: String,
        architecture: String,
        appearance: String,
        language: String,
        fullDiskAccess: Bool,
        logText: String,
        home: String,
        generatedAt: Date = Date()
    ) -> String {
        let header = """
        CleanR Diagnostics
        ==================
        Generated: \(generatedAt.formatted(date: .abbreviated, time: .standard))
        App: CleanR \(appVersion)
        macOS: \(osVersion)
        Architecture: \(architecture)
        Appearance: \(appearance)
        Language: \(language)
        Full Disk Access: \(fullDiskAccess ? "granted" : "not granted")

        Recent operations log (last 200 lines, paths redacted):
        """
        return redact(header + "\n" + tail(logText), home: home)
    }
}
