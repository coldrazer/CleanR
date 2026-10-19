import AppKit
import SwiftUI
import CleanRKit

struct UnusedAppsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var horizon: UnusedAppHorizon = .sixMonths
    @State private var records: [UnusedAppRecord] = []
    @State private var isLoading = true
    @State private var loadGeneration = 0

    private var apps: [UnusedAppRecord] { UnusedApps.unused(from: records, horizon: horizon) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("未使用的应用", "Unused Apps", "Неиспользуемые приложения"))
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.tr(
                        "按上次打开时间列出应用，并按占用空间排序。一键转到卸载器。",
                        "Apps you have not opened recently, sorted by how much space they use. One click hands them to the Uninstaller.",
                        "Приложения, которые давно не открывали, отсортированные по занятому месту. Одним нажатием можно перейти к удалению."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                Picker(L10n.tr("时间", "Horizon", "Период"), selection: $horizon) {
                    ForEach(UnusedAppHorizon.allCases) { h in
                        Text(h.label).tag(h)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button {
                    Task { await reload() }
                } label: {
                    Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView().controlSize(.large)
                        Text(L10n.tr("正在查找未使用的应用…", "Looking for unused apps…", "Поиск неиспользуемых приложений…"))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if UnusedApps.usageDataUnavailable(in: records) {
                    VStack(spacing: 8) {
                        Spacer()
                        Text(L10n.tr("Spotlight 没有应用的使用记录", "Spotlight has no usage history for your apps", "В Spotlight нет истории использования приложений"))
                            .font(.system(size: 13, weight: .medium))
                        Text(L10n.tr(
                            "无法判断哪些应用未被使用。请检查 Spotlight 索引是否已开启。",
                            "CleanR can't tell which apps are unused. Check that Spotlight indexing is turned on.",
                            "Невозможно определить неиспользуемые приложения. Проверьте, что индексация Spotlight включена."
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if apps.isEmpty {
                    VStack {
                        Spacer()
                        Text(L10n.tr("没有符合条件的应用", "No unused apps in this window", "Нет неиспользуемых приложений за этот период"))
                            .foregroundStyle(.primary.opacity(0.4))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(apps) { app in
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .medium))
                                    if app.runsInBackground {
                                        Text(L10n.tr("后台", "Background", "Фоновое"))
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.orange.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(subtitle(for: app))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(FileSizeFormatter.format(app.totalBytes))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Button(L10n.tr("卸载…", "Uninstall…", "Удалить…")) {
                                appState.openUninstaller(forAppPath: app.path)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            }
            .cleanRPanel(removeBackgroundColors: removeBackgroundColors)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .task { await reload() }
        .respondsToModuleShortcuts(onScan: { Task { await reload() } }, canScan: !isLoading)
    }

    private func subtitle(for app: UnusedAppRecord) -> String {
        let last: String
        if let date = app.lastUsed {
            last = date.formatted(date: .abbreviated, time: .omitted)
        } else {
            last = L10n.tr("未知", "Unknown", "Неизвестно")
        }
        let support = FileSizeFormatter.format(app.supportBytes)
        let lastLabel = L10n.tr("上次打开", "Last opened", "Открывалось")
        let supportLabel = L10n.tr("支持文件", "Support files", "Файлы поддержки")
        return "\(lastLabel) \(last) · \(supportLabel) \(support)"
    }

    private func reload() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap {
            $0.bundleURL?.path(percentEncoded: false)
        })
        let listed = await Task.detached {
            await UnusedAppsClient().records(runningAppPaths: running)
        }.value
        // A newer refresh started while this one ran: drop the stale result.
        guard generation == loadGeneration else { return }
        records = listed
        isLoading = false
    }
}
