import Foundation

/// One login item as reported by System Events.
public struct ParsedLoginItem: Equatable, Sendable {
    public let name: String
    public let path: String?
    public let hidden: Bool

    public init(name: String, path: String?, hidden: Bool) {
        self.name = name
        self.path = path
        self.hidden = hidden
    }
}

/// Parses the tab-delimited login-item payload emitted by
/// `OptimizationModule`'s System Events script.
///
/// The previous format was osascript's own text rendering of a record list —
/// `name:X, path:Y, hidden:false` — which the parser split on `", "` and `":"`.
/// That made the payload forgeable: an installed app named
/// `Backup Helper, path:/Applications/Other.app, hidden:false` rendered as
/// extra key/value pairs, so a row appeared labeled `Backup Helper` while the
/// attacker's own item was elsewhere in the list. Toggling that row ran
/// `delete login item "Backup Helper"` and silently disabled a *different*,
/// legitimate app's autostart.
///
/// Records are now positional and self-verifying: a `C\t<count>` header line
/// followed by one `<#idx>\t<name>\t<path>\t<hidden>` line per item. Field
/// counts, the sequential index, and the declared total all have to agree, so
/// a name containing a tab, a newline or `", path:"` desynchronizes the parse
/// and we return `nil` instead of producing plausible-looking rows. Callers
/// must fail closed on `nil` — show no login items rather than attacker-shaped
/// ones.
public enum LoginItemsOutput {
    public static func parse(_ output: String) -> [ParsedLoginItem]? {
        let lines = output
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let header = lines.first, header.hasPrefix("C\t"),
              let declaredCount = Int(header.dropFirst(2).trimmingCharacters(in: .whitespaces)),
              declaredCount >= 0 else {
            return nil
        }

        let recordLines = Array(lines.dropFirst())
        guard recordLines.count == declaredCount else { return nil }

        var items: [ParsedLoginItem] = []
        for (offset, line) in recordLines.enumerated() {
            let fields = line.components(separatedBy: "\t")
            // Exactly four fields, and the index must be the next one in
            // sequence. A smuggled newline shows up either as a wrong field
            // count or as a repeated/skipped index.
            guard fields.count == 4, fields[0] == "#\(offset + 1)" else { return nil }
            let name = fields[1]
            guard !name.isEmpty else { return nil }
            let path = fields[2]
            let hiddenToken = fields[3]
            guard hiddenToken == "true" || hiddenToken == "false" else { return nil }
            items.append(ParsedLoginItem(
                name: name,
                path: path.isEmpty ? nil : path,
                hidden: hiddenToken == "true"
            ))
        }
        return items
    }
}
