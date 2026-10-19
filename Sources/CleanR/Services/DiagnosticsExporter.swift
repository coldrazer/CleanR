import AppKit
import Foundation
import CleanRKit

/// User-initiated diagnostics export: gathers version/permission facts
/// plus the recent operations log, redacts home paths, and writes the
/// text only to the file the user picks in the save panel. This is the
/// no-telemetry answer to "please attach diagnostics" — nothing is sent
/// anywhere automatically.
@MainActor
public enum DiagnosticsExporter {
    public static func export() {
        let report = DiagnosticsReport.make(
            appVersion: MCConstants.appVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            appearance: AppearanceManager.storedMode.label,
            language: AppLanguage.current.rawValue,
            fullDiskAccess: PermissionManager.shared.hasFullDiskAccess(),
            logText: CleanLogManager.readLogFile(),
            home: NSHomeDirectory()
        )

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CleanR-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.title = L10n.tr("导出诊断信息", "Export Diagnostics", "Экспорт диагностики")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
