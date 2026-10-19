import Foundation
import AppKit
import CleanRKit

public struct MaintenanceModule: ScanModule {
    public let id = "maintenance"
    public var name: String { L10n.tr("维护", "Maintenance", "Обслуживание") }
    public let category = ModuleCategory.performance

    public init() {}

    public func scan() async -> [ScanResult] { [] }
}

// MARK: - Maintenance Executor
//
// `MaintenanceTask` (the enum + descriptions + system commands) lives in
// CleanRKit. This actor runs those commands: admin ones through in-process
// AppleScript (password cached per process, issue #143), the rest via Process.

public actor MaintenanceExecutor {
    public struct TaskResult: Sendable {
        public let task: MaintenanceTask
        public let success: Bool
        public let output: String
        public let error: String?
    }

    private let privilegedRunner: any PrivilegedShellRunning
    private let commandExists: @Sendable (String) -> Bool

    public init() {
        self.init(
            privilegedRunner: AppleScriptPrivilegedRunner(),
            commandExists: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    init(
        privilegedRunner: any PrivilegedShellRunning,
        commandExists: @escaping @Sendable (String) -> Bool
    ) {
        self.privilegedRunner = privilegedRunner
        self.commandExists = commandExists
    }

    public func execute(_ task: MaintenanceTask) async -> TaskResult {
        if case .speedUpMail = task { return await reindexMail() }
        if case .pruneDocker = task { return await pruneDocker() }

        guard let (command, args) = task.systemCommand else {
            return TaskResult(task: task, success: false, output: "",
                              error: L10n.tr("该任务没有可执行的系统命令", "Task has no system command", "Для этой задачи нет системной команды"))
        }

        // Report a missing system tool instead of running it and surfacing the
        // raw shell error. Apple removed `/usr/sbin/periodic` in macOS 26, so
        // Run Maintenance Scripts failed with
        // `/bin/sh: /usr/sbin/periodic: No such file or directory` (issue #129)
        // — which reads as an app bug rather than a tool the OS dropped. Gating
        // here rather than per-task covers every hard-coded path in
        // `systemCommand`, the same way `pruneDocker` already gates on the
        // Docker CLI. Checked unprivileged, so an admin task fails before the
        // password prompt rather than after it.
        guard task.systemCommandIsAvailable(existing: commandExists) else {
            return TaskResult(
                task: task, success: false, output: "",
                error: L10n.tr("\(command) 在当前 macOS 版本中不可用，无法执行该任务。",
                               "\(command) isn't available on this version of macOS, so this task can't run.",
                               "\(command) недоступно в этой версии macOS, поэтому эту задачу нельзя выполнить."))
        }

        if task.requiresAdmin {
            return await runAdminProcess(task: task, command: command, args: args)
        }
        return await runProcess(task: task, command: command, args: args)
    }

    /// Run a root-requiring command via the standard macOS admin-auth prompt
    /// (`do shell script … with administrator privileges`). Executed
    /// in-process so successive tasks reuse the cached credentials (issue
    /// #143) — spawning `/usr/bin/osascript` each time could not. The
    /// command strings come from the fixed `MaintenanceTask` enum (never
    /// user input).
    private func runAdminProcess(task: MaintenanceTask, command: String, args: [String]) async -> TaskResult {
        let result = await privilegedRunner.run(executable: command, arguments: args)

        if result.success {
            return TaskResult(task: task, success: true, output: result.output, error: nil)
        }

        let err = result.error ?? ""
        if MaintenanceShell.isAuthorizationCancelled(err, errorNumber: result.errorNumber) {
            return TaskResult(task: task, success: false, output: "",
                              error: L10n.tr("已取消——未授予管理员权限。", "Cancelled — administrator access was not granted.", "Отменено: не предоставлены права администратора."))
        }
        // Strip AppleScript's "1:92: execution error: … (1)" wrapper so the
        // user sees the real underlying message (issue #82).
        return TaskResult(task: task, success: false, output: "",
                          error: MaintenanceShell.humanReadableError(err))
    }

    private func runProcess(task: MaintenanceTask, command: String, args: [String]) async -> TaskResult {
        // `BoundedProcess` drains both pipes *while* the command runs. The old
        // shape here called `waitUntilExit()` first, which deadlocks as soon as a
        // maintenance command writes more than the ~64KB pipe buffer —
        // `diskutil verifyVolume` on a large APFS volume, or a verbose
        // `lsregister -kill -r`, both do. Detached so the blocking drain does not
        // park this actor's thread.
        let outcome = await Task.detached { () -> Result<(status: Int32, stdout: Data, stderr: Data), Error> in
            Result { try BoundedProcess.runSynchronously(command, args) }
        }.value

        switch outcome {
        case .success(let result):
            let output = String(decoding: result.stdout, as: UTF8.self)
            let error = String(decoding: result.stderr, as: UTF8.self)
            return TaskResult(
                task: task,
                success: result.status == 0,
                output: output,
                error: error.isEmpty ? nil : error
            )
        case .failure(let error):
            return TaskResult(
                task: task,
                success: false,
                output: "",
                error: error.localizedDescription
            )
        }
    }

    private func reindexMail() async -> TaskResult {
        let mailDataDir = MCConstants.mailData.appending(path: "V10/MailData")
        let envelopeIndex = mailDataDir.appending(path: "Envelope Index")

        let fm = FileManager.default
        guard fm.fileExists(atPath: envelopeIndex.path(percentEncoded: false)) else {
            return TaskResult(
                task: .speedUpMail,
                success: true,
                output: L10n.tr("未找到邮件索引——邮件可能使用了不同的版本目录。", "Mail envelope index not found — Mail may use a different version directory.", "Индекс Почты не найден: возможно, Почта использует другую папку версии."),
                error: nil
            )
        }

        // Mail keeps the Envelope Index open while it runs. It is a SQLite
        // database with -wal/-shm sidecars, so removing it underneath a live
        // Mail leaves the app holding a half-gone database — that is a broken
        // Mail, not a slow one. Refuse until the user quits it.
        let mailIsRunning = await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.mail" }
        }
        guard !mailIsRunning else {
            return TaskResult(
                task: .speedUpMail,
                success: false,
                output: "",
                error: L10n.tr("请先退出邮件应用，再重建索引。", "Quit Mail before rebuilding its index.", "Перед перестроением индекса закройте приложение «Почта».")
            )
        }

        // The sidecars have to move with the main file: an index restored
        // without its -wal (or a leftover -wal restored without its index) is
        // a corrupt pair. Trash, never `removeItem` — if Mail fails to rebuild
        // from the messages on disk, the previous index is the only rollback.
        let indexFamily = ((try? fm.contentsOfDirectory(
            at: mailDataDir, includingPropertiesForKeys: nil
        )) ?? []).filter {
            let name = $0.lastPathComponent
            return name == "Envelope Index"
                || name.hasPrefix("Envelope Index-")
                || name.hasPrefix("Envelope Index.")
        }

        let safety = SafetyGuard()
        var moved: [String] = []
        var failures: [String] = []
        var trashed: [CleaningEngine.TrashedItem] = []
        for file in indexFamily {
            do {
                try safety.validatePath(file)
                let bytes = UInt64(max(0, (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                var inTrash: NSURL?
                try fm.trashItem(at: file, resultingItemURL: &inTrash)
                moved.append(file.lastPathComponent)
                if let trashURL = inTrash as URL? {
                    trashed.append(.init(originalURL: file, trashURL: trashURL, bytes: bytes))
                }
            } catch {
                failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // Trash-first, so it belongs in the one-click Restore list; without this
        // the sessions recorded here are the only way back to the old index.
        CleanHistoryRecorder.record(trashedItems: trashed)

        if failures.isEmpty {
            return TaskResult(
                task: .speedUpMail,
                success: true,
                output: L10n.tr(
                    "邮件索引已移至废纸篓（\(moved.count) 个文件）。邮件将在下次启动时重建。",
                    "Mail envelope index moved to the Trash (\(moved.count) file(s)). Mail will rebuild it on next launch.",
                    "Индекс Почты перемещён в Корзину (\(moved.count) \(L10n.russianPlural(moved.count, one: "файл", few: "файла", many: "файлов"))). Почта перестроит его при следующем запуске."
                ),
                error: nil
            )
        }
        return TaskResult(
            task: .speedUpMail,
            success: false,
            output: "",
            error: failures.joined(separator: "; ")
        )
    }

    /// Reclaim Docker space via `docker system prune -f`. Gated on the Docker
    /// CLI existing (resolved from MaintenanceTask.dockerCandidatePaths); if it
    /// isn't installed we report that instead of failing obscurely. Runs as the
    /// user (the CLI talks to Docker Desktop's daemon), so no admin prompt.
    private func pruneDocker() async -> TaskResult {
        guard let docker = MaintenanceTask.resolveDockerPath(existing: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            return TaskResult(
                task: .pruneDocker, success: false, output: "",
                error: L10n.tr("未找到 Docker 命令行工具。请确认已安装 Docker Desktop。",
                               "Docker CLI not found. Make sure Docker Desktop is installed.",
                "Команда Docker не найдена. Убедитесь, что Docker Desktop установлен."))
        }
        return await runProcess(task: .pruneDocker, command: docker, args: ["system", "prune", "-f"])
    }
}
