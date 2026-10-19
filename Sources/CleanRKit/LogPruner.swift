import Foundation

/// Pure log-pruning logic. Removes lines from a log buffer whose
/// ISO8601-prefixed timestamp is older than a cutoff. Lines whose
/// prefix doesn't parse as ISO8601 are kept (defensive — we'd rather
/// over-retain than silently drop user data on an unexpected log
/// format).
///
/// CleanLogManager wraps this with the filesystem read/write — the
/// pruning itself is pure so tests don't need a tmp dir.
public enum LogPruner {

    /// Returns `logText` with lines whose ISO8601 timestamp prefix is
    /// strictly older than `cutoff` removed. Other lines are preserved
    /// in their original order.
    public static func pruning(_ logText: String, olderThan cutoff: Date) -> String {
        guard !logText.isEmpty else { return "" }

        // Use Swift's modern Date parser — ISO8601FormatStyle handles
        // the "2026-06-01T07:43:23Z" shape CleaningEngine writes.
        let parser = ISO8601DateFormatter()

        // Split on \n and rebuild, preserving any trailing newline state.
        let endsWithNewline = logText.hasSuffix("\n")
        let lines = logText.split(separator: "\n", omittingEmptySubsequences: false)

        var kept: [Substring] = []
        kept.reserveCapacity(lines.count)
        for line in lines {
            if isOlderThan(line: String(line), cutoff: cutoff, parser: parser) {
                continue
            }
            kept.append(line)
        }

        // If we dropped nothing AND ordering/content is identical, return
        // the input verbatim so caller can detect "no-op" via ==.
        if kept.count == lines.count {
            return logText
        }

        var result = kept.joined(separator: "\n")
        if endsWithNewline, !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    /// True iff the line's leading ISO8601 timestamp parses AND is
    /// older than `cutoff`. Lines without a valid leading timestamp
    /// return false (= keep them).
    private static func isOlderThan(
        line: String, cutoff: Date, parser: ISO8601DateFormatter
    ) -> Bool {
        // Expect "<ISO8601> <body>" — extract everything before the first
        // space and try to parse it.
        guard let spaceIndex = line.firstIndex(of: " ") else { return false }
        let timestampPart = String(line[line.startIndex..<spaceIndex])
        guard let date = parser.date(from: timestampPart) else { return false }
        return date < cutoff
    }
}
