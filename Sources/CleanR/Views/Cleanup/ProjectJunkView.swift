import AppKit
import SwiftUI
import CleanRKit
import UniformTypeIdentifiers

struct ProjectJunkView: View {
    @Environment(AppState.self) private var appState
    /// The folder being scanned. Cleared on reset, so every new scan starts
    /// by asking which folder to look in.
    @State private var rootURL: URL?
    /// Whether `rootURL` holds an open security-scoped access to balance.
    @State private var isAccessingRoot = false
    @State private var rootRefused = false
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?
    @State private var scanTask: Task<Void, Never>?
    /// Bumped by every scan and reset; a scan only publishes its results if
    /// the generation it started with is still current.
    @State private var scanGeneration = 0
    @State private var showPicker = false

    private let scanner = ProjectJunkScanner()

    private static var findingPhase: String {
        L10n.tr("正在查找项目…", "Finding projects…", "Поиск проектов…")
    }

    private static var measuringPhase: String {
        L10n.tr("正在计算文件夹大小…", "Measuring folders…", "Подсчёт размера папок…")
    }

    private var subtitle: String {
        if let rootURL {
            let noAutoSelect = L10n.tr("不会自动勾选。", "Nothing is auto-selected.", "Ничего не выбирается заранее.")
            return "\(rootURL.path(percentEncoded: false)) · \(noAutoSelect)"
        }
        return L10n.tr(
            "选择项目文件夹（例如 ~/Code），查找 node_modules、venv、target、build 等可重建目录。",
            "Choose a projects folder (e.g. ~/Code) to find regenerable folders like node_modules, venvs, target, and build.",
            "Выберите папку с проектами (например ~/Code), чтобы найти восстанавливаемые каталоги вроде node_modules, venv, target и build."
        )
    }

    private var emptyMessage: String {
        if rootRefused {
            return L10n.tr(
                "请选择你的项目文件夹，而不是系统文件夹或资源库。",
                "Choose your projects folder, not a system folder or Library.",
                "Выберите папку с проектами, а не системную папку или Библиотеку."
            )
        }
        return L10n.tr("未找到项目垃圾", "No project junk found", "Мусор проектов не найден")
    }

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("项目垃圾", "Project Junk", "Мусор проектов"),
            subtitle: subtitle,
            theme: .cleanup,
            emptyMessage: emptyMessage,
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: { showPicker = true },
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset
        )
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                runScan(root: url)
            }
        }
        .onDisappear {
            // A scan cut short has nothing to show: drop it and its folder
            // access. Finished results stay until Done or a new scan.
            if isScanning { reset() }
        }
    }

    private func runScan(root: URL) {
        cancelScan()
        releaseRoot()
        rootURL = root
        isAccessingRoot = root.startAccessingSecurityScopedResource()
        rootRefused = !ProjectJunkScanner.isAllowedRoot(root)
        results = []
        selectedItems = []
        completion = nil
        scanComplete = false
        if rootRefused {
            scanComplete = true
            return
        }

        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        scanProgress = 0.05
        scanPhase = Self.findingPhase
        let scanner = scanner
        scanTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                scanner.scan(root: root) { fraction in
                    Task { @MainActor in
                        guard generation == scanGeneration else { return }
                        scanProgress = max(scanProgress, fraction)
                        scanPhase = Self.measuringPhase
                    }
                }
            }
            let items = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            // A reset or a newer scan made this one stale: drop its results.
            guard !Task.isCancelled, generation == scanGeneration else { return }
            results = scanner.asScanResults(items)
            selectedItems = []
            scanProgress = 1
            isScanning = false
            scanComplete = true
        }
    }

    private func cancelScan() {
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func releaseRoot() {
        if isAccessingRoot, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
        }
        isAccessingRoot = false
    }

    private func clean() {
        let preCleanSelectedCount = selectedItems.count
        cleaning = CleaningEngine.Progress(
            totalItems: preCleanSelectedCount,
            processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0
        )
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selectedItems,
                engine: appState.cleaningEngine,
                onProgress: { progress in
                    Task { @MainActor in cleaning = progress }
                }
            )
            cleaning = nil
            completion = CleanSummary(
                selectedCount: preCleanSelectedCount,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorMessages: result.errors.map(\.error)
            )
        }
    }

    private func reset() {
        cancelScan()
        releaseRoot()
        rootURL = nil
        rootRefused = false
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil
        scanProgress = 0
        scanComplete = false
    }
}
