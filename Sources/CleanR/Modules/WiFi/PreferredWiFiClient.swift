import Foundation
import CleanRKit

/// Lists and forgets preferred Wi-Fi networks. Process / osascript are
/// injected so tests never touch the live `networksetup`.
struct PreferredWiFiClient: Sendable {
    typealias CommandResult = (stdout: String, stderr: String, status: Int32)

    var run: @Sendable (String, [String]) async -> CommandResult
    var runAdminShell: @Sendable (String) async -> CommandResult

    static func live() -> PreferredWiFiClient {
        PreferredWiFiClient(
            run: { command, args in await Self.runProcess(command: command, arguments: args) },
            runAdminShell: { shell in
                let escaped = shell
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let script = "do shell script \"\(escaped)\" with administrator privileges"
                return await Self.runProcess(command: "/usr/bin/osascript", arguments: ["-e", script])
            }
        )
    }

    func listNetworks() async -> Result<[PreferredWiFiNetwork], PreferredWiFiClientError> {
        let hw = await run(PreferredWiFiCommands.networksetup, PreferredWiFiCommands.listHardwarePortsArguments)
        guard hw.status == 0 else {
            return .failure(.commandFailed(hw.stderr.isEmpty ? hw.stdout : hw.stderr))
        }
        let devices = PreferredWiFiParser.wifiDevices(from: hw.stdout)
        guard !devices.isEmpty else { return .failure(.noWiFiHardware) }

        var all: [PreferredWiFiNetwork] = []
        for device in devices {
            guard let args = PreferredWiFiCommands.listPreferredArguments(device: device) else { continue }
            let listed = await run(PreferredWiFiCommands.networksetup, args)
            if listed.status == 0 {
                all.append(contentsOf: PreferredWiFiParser.preferredNetworks(from: listed.stdout, device: device))
            }
        }
        return .success(all)
    }

    func forget(_ networks: [PreferredWiFiNetwork]) async -> Result<Void, PreferredWiFiClientError> {
        guard !networks.isEmpty else { return .success(()) }
        guard let shell = PreferredWiFiCommands.removeBatchShellCommand(networks: networks) else {
            return .failure(.invalidDevice)
        }
        let result = await runAdminShell(shell)
        if result.status == 0 { return .success(()) }
        let raw = result.stderr.isEmpty ? result.stdout : result.stderr
        if raw.contains("User canceled") || raw.contains("-128") {
            return .failure(.adminCancelled)
        }
        return .failure(.commandFailed(MaintenanceShell.humanReadableError(raw)))
    }

    private static func runProcess(command: String, arguments: [String]) async -> CommandResult {
        // Drain concurrently: `networksetup -listpreferredwirelessnetworks` can
        // outgrow the pipe buffer on a machine with many saved networks, and the
        // previous wait-then-read order hung the actor forever when it did.
        let outcome = await Task.detached { () -> Result<(status: Int32, stdout: Data, stderr: Data), Error> in
            Result { try BoundedProcess.runSynchronously(command, arguments) }
        }.value

        switch outcome {
        case .success(let result):
            return (
                String(decoding: result.stdout, as: UTF8.self),
                String(decoding: result.stderr, as: UTF8.self),
                result.status
            )
        case .failure(let error):
            return ("", error.localizedDescription, -1)
        }
    }
}

enum PreferredWiFiClientError: Error, Equatable {
    case noWiFiHardware
    case invalidDevice
    case adminCancelled
    case commandFailed(String)

    var localizedMessage: String {
        switch self {
        case .noWiFiHardware:
            L10n.tr("未找到 Wi-Fi 硬件。", "No Wi-Fi hardware found.", "Адаптер Wi-Fi не найден.")
        case .invalidDevice:
            L10n.tr("无线接口名称无效，已中止操作。", "The Wi-Fi interface name was invalid, so the action was cancelled.", "Недопустимое имя интерфейса Wi-Fi — операция отменена.")
        case .adminCancelled:
            L10n.tr("已取消——未授予管理员权限。", "Cancelled — administrator access was not granted.", "Отменено: не предоставлены права администратора.")
        case .commandFailed(let message):
            message.isEmpty
                ? L10n.tr("无法更新已保存的 Wi-Fi 网络。", "Couldn't update saved Wi-Fi networks.", "Не удалось обновить сохранённые сети Wi-Fi.")
                : message
        }
    }
}
