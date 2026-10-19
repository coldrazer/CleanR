import AppKit
import SwiftUI
import CleanRKit

struct BrowserExtensionsView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var scan = BrowserExtensionScan(records: [], safariListed: true)
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var pending: BrowserExtensionRecord?
    @State private var message: String?
    private let client = BrowserExtensionsClient()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("浏览器扩展", "Browser Extensions", "Расширения браузеров"))
                        .font(.system(size: 20, weight: .semibold))
                    Text(BrowserExtensionsStrings.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading || isWorking)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if !isLoading && !scan.safariListed {
                Label(BrowserExtensionsStrings.safariUnavailable, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView().controlSize(.large)
                        Text(BrowserExtensionsStrings.reading)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if scan.records.isEmpty {
                    VStack {
                        Spacer()
                        Text(BrowserExtensionsStrings.empty)
                            .foregroundStyle(.primary.opacity(0.4))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(scan.records) { ext in
                        row(ext)
                    }
                    .listStyle(.inset)
                }
            }
            .cleanRPanel(removeBackgroundColors: removeBackgroundColors)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .task { await reload() }
        .respondsToModuleShortcuts(onScan: { Task { await reload() } }, canScan: !isLoading && !isWorking)
        .alert(
            BrowserExtensionsStrings.confirmTitle(for: pending),
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            presenting: pending
        ) { ext in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { pending = nil }
            Button(actionLabel(for: ext), role: ext.origin == .user ? .destructive : nil) {
                let target = ext
                pending = nil
                Task { await remove(target) }
            }
        } message: { ext in
            Text(BrowserExtensionsStrings.confirmMessage(for: ext))
        }
        .alert(
            L10n.tr("浏览器扩展", "Browser Extensions", "Расширения браузеров"),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button(L10n.tr("好", "OK"), role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func row(_ ext: BrowserExtensionRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ext.name)
                        .font(.system(size: 13, weight: .medium))
                    if ext.isSuspicious {
                        tag(BrowserExtensionsStrings.suspicious, color: .red)
                            .help(BrowserExtensionsStrings.suspiciousHelp)
                    }
                    switch ext.origin {
                    case .policy: tag(BrowserExtensionsStrings.policyTag, color: .orange)
                    case .component: tag(BrowserExtensionsStrings.builtInTag, color: .gray)
                    case .user, .safariApp: EmptyView()
                    }
                }
                Text(detail(for: ext))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionLabel(for: ext)) {
                pending = ext
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    private func detail(for ext: BrowserExtensionRecord) -> String {
        let date = ext.updatedAt?.formatted(date: .abbreviated, time: .omitted)
            ?? BrowserExtensionsStrings.unknownDate
        var parts = [ext.browser.label]
        if !ext.profile.isEmpty { parts.append(ext.profile) }
        parts.append(date)
        return parts.joined(separator: " · ")
    }

    private func actionLabel(for ext: BrowserExtensionRecord) -> String {
        switch ext.origin {
        case .safariApp: L10n.tr("在设置中打开", "Open in Settings", "Открыть в настройках")
        case .policy, .component: BrowserExtensionsStrings.details
        case .user: L10n.tr("移除", "Remove", "Удалить")
        }
    }

    private func reload() async {
        isLoading = true
        scan = await client.list()
        isLoading = false
    }

    private func remove(_ record: BrowserExtensionRecord) async {
        isWorking = true
        let outcome = await client.applyRemoval(record)
        message = BrowserExtensionsStrings.message(for: outcome)
        if outcome == .trashed { scan = await client.list() }
        isWorking = false
    }
}

/// Every user-facing string of the Browser Extensions screen. `{browser}`
/// and `{url}` are filled after lookup so the translation tables stay keyed
/// by plain strings.
enum BrowserExtensionsStrings {
    static var subtitle: String {
        L10n.tr(
            "Chrome、Brave、Edge、Arc、Firefox 和 Safari 的扩展。名称与已知广告软件家族相符的会标为可疑。",
            "Extensions from Chrome, Brave, Edge, Arc, Firefox, and Safari. Names that match known adware families are marked Suspicious.",
            "Расширения Chrome, Brave, Edge, Arc, Firefox и Safari. Названия, совпадающие с известными семействами рекламного ПО, помечаются как подозрительные."
        )
    }

    static var reading: String {
        L10n.tr("正在读取扩展…", "Reading extensions…", "Чтение расширений…")
    }

    static var empty: String {
        L10n.tr(
            "在 Chrome、Brave、Edge、Arc、Firefox 或 Safari 中未找到扩展",
            "No extensions found in Chrome, Brave, Edge, Arc, Firefox, or Safari",
            "Расширения в Chrome, Brave, Edge, Arc, Firefox и Safari не найдены"
        )
    }

    static var safariUnavailable: String {
        L10n.tr(
            "无法读取 Safari 扩展列表。请在 Safari 设置 > 扩展中查看。",
            "Couldn't read the list of Safari extensions. Check Safari Settings > Extensions instead.",
            "Не удалось прочитать список расширений Safari. Проверьте их в Safari: Настройки > Расширения."
        )
    }

    static var suspicious: String { L10n.tr("可疑", "Suspicious", "Подозрительное") }

    static var suspiciousHelp: String {
        L10n.tr(
            "名称与已知广告软件家族相符。这只是提示，并非确认。",
            "The name matches a known adware family. This is a hint, not a confirmed detection.",
            "Название совпадает с известным семейством рекламного ПО. Это подсказка, а не подтверждённое обнаружение."
        )
    }

    static var policyTag: String { L10n.tr("由策略安装", "Installed by policy", "Установлено политикой") }
    static var builtInTag: String { L10n.tr("内置", "Built in", "Встроенное") }
    static var unknownDate: String { L10n.tr("未知日期", "Unknown date", "Дата неизвестна") }
    static var details: String { L10n.tr("详情", "Details", "Подробнее") }

    static func confirmTitle(for record: BrowserExtensionRecord?) -> String {
        guard let record, record.origin == .user else {
            return L10n.tr("关于此扩展", "About this extension", "Об этом расширении")
        }
        return L10n.tr("移除扩展？", "Remove extension?", "Удалить расширение?")
    }

    static func confirmMessage(for record: BrowserExtensionRecord) -> String {
        switch record.origin {
        case .safariApp:
            return L10n.tr(
                "Safari 扩展随 App 一起安装，由 macOS 管理，因此此列表只读。将改为打开“设置”。",
                "Safari extensions come with apps and are managed by macOS, so this list is read-only. Settings will open instead.",
                "Расширения Safari устанавливаются вместе с приложениями и управляются macOS, поэтому список только для чтения. Вместо этого откроются Настройки."
            )
        case .policy:
            return fill(policyText, record.browser)
        case .component:
            return fill(builtInText, record.browser)
        case .user:
            return fill(L10n.tr(
                "如果 {browser} 已关闭，扩展文件夹会移到废纸篓。如果它正在运行，则不会删除任何内容，并会告诉你在哪里移除。如果你开启了 {browser} 同步，它可能会重新安装此扩展。",
                "If {browser} is closed, the extension folder moves to the Trash. If it is open, nothing is deleted and you'll see where to remove it. If you use {browser} sync, it may reinstall the extension.",
                "Если {browser} закрыт, папка расширения будет перемещена в Корзину. Если он открыт, ничего не удаляется, и вы увидите, где удалить расширение. Если включена синхронизация {browser}, расширение может установиться снова."
            ), record.browser)
        }
    }

    static func message(for outcome: BrowserExtensionsClient.RemovalOutcome) -> String? {
        switch outcome {
        case .openedSafariSettings:
            return nil
        case .trashed:
            return L10n.tr("已将扩展移到废纸篓。", "The extension was moved to the Trash.", "Расширение перемещено в Корзину.")
        case .removeInBrowser(let browser):
            return removeInBrowserText(browser)
        case .managedByPolicy(let browser):
            return fill(policyText, browser)
        case .builtIn(let browser):
            return fill(builtInText, browser)
        case .refused:
            return L10n.tr(
                "CleanR 无法确认此扩展的文件夹可以安全移除，因此未删除任何内容。",
                "CleanR couldn't confirm this extension's folder is safe to remove, so nothing was deleted.",
                "CleanR не смог подтвердить, что папку расширения безопасно удалить, поэтому ничего не удалено."
            )
        case .failed(let error):
            return L10n.tr("无法移到废纸篓：", "Couldn't move it to the Trash: ", "Не удалось переместить в Корзину: ") + error
        }
    }

    static func removeInBrowserText(_ browser: BrowserKind) -> String {
        switch browser {
        case .chrome:
            return L10n.tr(
                "Chrome 正在运行，因此未删除任何内容。请在 Chrome 中通过“窗口 > 扩展程序”移除此扩展。",
                "Chrome is open, so nothing was deleted. Remove the extension in Chrome from Window > Extensions.",
                "Chrome открыт, поэтому ничего не удалено. Удалите расширение в Chrome через меню «Окно > Расширения»."
            )
        case .firefox:
            return L10n.tr(
                "Firefox 正在运行，因此未删除任何内容。请在 Firefox 中通过“工具 > 附加组件和主题”移除此扩展。",
                "Firefox is open, so nothing was deleted. Remove the extension in Firefox from Tools > Add-ons and Themes.",
                "Firefox открыт, поэтому ничего не удалено. Удалите расширение в Firefox через меню «Инструменты > Дополнения и темы»."
            )
        case .brave, .edge, .arc, .safari:
            let url: String
            switch browser {
            case .brave: url = "brave://extensions"
            case .edge: url = "edge://extensions"
            default: url = "arc://extensions"
            }
            return fill(L10n.tr(
                "{browser} 正在运行，因此未删除任何内容。请在 {browser} 的地址栏中打开 {url} 来移除此扩展。",
                "{browser} is open, so nothing was deleted. Remove the extension in {browser} by opening {url} in the address bar.",
                "{browser} открыт, поэтому ничего не удалено. Удалите расширение в {browser}, открыв {url} в адресной строке."
            ), browser).replacingOccurrences(of: "{url}", with: url)
        }
    }

    static var policyText: String {
        L10n.tr(
            "此扩展由管理策略安装，删除文件夹后 {browser} 会重新安装它。如果你不认识它，请在系统设置中搜索“描述文件”或“设备管理”，并移除你不认识的描述文件。",
            "This extension was installed by a management policy, so {browser} would reinstall it. If you don't recognize it, search System Settings for Profiles or Device Management and remove any profile you don't recognize.",
            "Это расширение установлено политикой управления, поэтому {browser} установит его снова. Если вы его не узнаёте, найдите в Системных настройках раздел «Профили» или «Управление устройством» и удалите незнакомый профиль."
        )
    }

    static var builtInText: String {
        L10n.tr(
            "此扩展内置于 {browser}，无法移除。",
            "This extension is built into {browser} and can't be removed.",
            "Это расширение встроено в {browser} и не может быть удалено."
        )
    }

    static func fill(_ text: String, _ browser: BrowserKind) -> String {
        text.replacingOccurrences(of: "{browser}", with: browser.label)
    }
}
