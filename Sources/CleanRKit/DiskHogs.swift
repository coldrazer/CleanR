import Foundation

public enum DockerDiskCategory: String, Equatable, Sendable, CaseIterable, Identifiable {
    case images
    case containers
    case volumes
    case buildCache

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .images: L10n.tr("镜像", "Images", "Образы")
        case .containers: L10n.tr("容器", "Containers", "Контейнеры")
        case .volumes: L10n.tr("卷", "Volumes", "Тома")
        case .buildCache: L10n.tr("构建缓存", "Build Cache", "Кэш сборки")
        }
    }

    /// Volumes can hold database data (named volumes, and the anonymous
    /// volumes images like postgres declare), and on Docker before 23
    /// `volume prune` removes named volumes too. CleanR only reports them.
    public var isPrunable: Bool { self != .volumes }

    /// What pruning this category actually removes, in plain words. Shown on
    /// the row and repeated in the confirmation.
    public var pruneNote: String {
        switch self {
        case .images:
            L10n.tr(
                "清理只会删除悬空（无标签）镜像，带标签的镜像会保留。",
                "Pruning removes only dangling (untagged) images. Tagged images are kept.",
                "Очистка удаляет только висячие (без тега) образы. Образы с тегами сохраняются."
            )
        case .containers:
            L10n.tr(
                "清理会永久删除所有已停止的容器及其中的数据。正在运行的容器不受影响。",
                "Pruning permanently deletes every stopped container and the data inside it. Running containers are not touched.",
                "Очистка безвозвратно удаляет все остановленные контейнеры и данные внутри них. Работающие контейнеры не затрагиваются."
            )
        case .volumes:
            L10n.tr(
                "卷可能保存着数据库等数据，CleanR 不会清理它们。如需删除，请使用 Docker Desktop 或 Docker 命令行。",
                "Volumes can hold database data, so CleanR leaves them alone. To remove them, use Docker Desktop or the Docker CLI.",
                "Тома могут хранить данные баз данных, поэтому CleanR их не трогает. Чтобы удалить их, используйте Docker Desktop или Docker CLI."
            )
        case .buildCache:
            L10n.tr(
                "清理会删除悬空的构建缓存。下次构建可能会变慢。",
                "Pruning removes dangling build cache. Your next build may be slower.",
                "Очистка удаляет висячий кэш сборки. Следующая сборка может пройти медленнее."
            )
        }
    }
}

public struct DockerDiskRow: Equatable, Sendable, Identifiable {
    public var id: DockerDiskCategory { category }
    public let category: DockerDiskCategory
    public let size: String
    public let reclaimable: String

    public init(category: DockerDiskCategory, size: String, reclaimable: String) {
        self.category = category
        self.size = size
        self.reclaimable = reclaimable
    }
}

public enum DockerSystemDFParser {
    /// Arguments for the probe. A `{{json .}}` template prints one object per
    /// line on every Docker CLI since 1.13; the table layout is less stable.
    public static let arguments = ["system", "df", "--format", "{{json .}}"]

    /// Parses JSON lines from ``arguments``, falling back to the plain table.
    public static func parse(_ text: String) -> [DockerDiskRow] {
        let jsonRows = parseJSONLines(text)
        return jsonRows.isEmpty ? parseTable(text) : jsonRows
    }

    static func parseJSONLines(_ text: String) -> [DockerDiskRow] {
        struct Line: Decodable {
            let type: String
            let size: String
            let reclaimable: String?
            enum CodingKeys: String, CodingKey {
                case type = "Type", size = "Size", reclaimable = "Reclaimable"
            }
        }
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            guard let data = raw.data(using: .utf8),
                  let line = try? JSONDecoder().decode(Line.self, from: data) else { return nil }
            let words = line.type.split(separator: " ").map(String.init)
            guard let first = words.first,
                  let category = category(for: first, second: words.dropFirst().first) else { return nil }
            return DockerDiskRow(category: category, size: line.size, reclaimable: line.reclaimable ?? "")
        }
    }

    static func parseTable(_ text: String) -> [DockerDiskRow] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 5 else { return nil }
            guard let category = category(for: columns[0], second: columns[1]) else {
                return nil
            }
            // TYPE TOTAL ACTIVE SIZE RECLAIMABLE. TYPE is two words for
            // "Local Volumes" and "Build Cache", so SIZE shifts right by one.
            let typeWordCount = category == .volumes || category == .buildCache ? 2 : 1
            guard columns.count >= typeWordCount + 4 else { return nil }
            let size = columns[typeWordCount + 2]
            let reclaimable = columns.dropFirst(typeWordCount + 3).joined(separator: " ")
            return DockerDiskRow(category: category, size: size, reclaimable: reclaimable)
        }
    }

    private static func category(for first: String, second: String?) -> DockerDiskCategory? {
        switch first.lowercased() {
        case "images": return .images
        case "containers": return .containers
        case "local" where second?.lowercased() == "volumes": return .volumes
        case "build" where second?.lowercased() == "cache": return .buildCache
        default: return nil
        }
    }
}

public enum DockerPrune {
    public static let defaultSelection: Set<DockerDiskCategory> = []

    /// One Docker CLI command per selected category, in a fixed order.
    /// Volumes are never pruned, whatever the selection says. No `-a`: image
    /// and builder prune stay limited to dangling data.
    public static func commands(for selection: Set<DockerDiskCategory>) -> [(category: DockerDiskCategory, arguments: [String])] {
        var commands: [(DockerDiskCategory, [String])] = []
        if selection.contains(.images) { commands.append((.images, ["image", "prune", "-f"])) }
        if selection.contains(.containers) { commands.append((.containers, ["container", "prune", "-f"])) }
        if selection.contains(.buildCache) { commands.append((.buildCache, ["builder", "prune", "-f"])) }
        return commands
    }

    public static func arguments(for selection: Set<DockerDiskCategory>) -> [[String]] {
        commands(for: selection).map(\.arguments)
    }
}

public struct SimulatorDevice: Equatable, Sendable, Identifiable {
    public var id: String { udid }
    public let udid: String
    public let name: String
    public let runtime: String

    public init(udid: String, name: String, runtime: String) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-17-5" reads as "iOS 17.5".
    public var runtimeDisplayName: String {
        guard let marker = runtime.range(of: "SimRuntime.") else { return runtime }
        let parts = runtime[marker.upperBound...].split(separator: "-")
        guard let platform = parts.first else { return runtime }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? String(platform) : "\(platform) \(version)"
    }
}

public struct SimulatorRuntime: Equatable, Sendable, Identifiable {
    public var id: String { identifier }
    /// Disk-image identifier from `simctl runtime list -j`; what
    /// `simctl runtime delete` expects.
    public let identifier: String
    public let runtimeIdentifier: String
    public let platform: String
    public let version: String
    public let sizeBytes: Int64?

    public init(identifier: String, runtimeIdentifier: String, platform: String, version: String, sizeBytes: Int64?) {
        self.identifier = identifier
        self.runtimeIdentifier = runtimeIdentifier
        self.platform = platform
        self.version = version
        self.sizeBytes = sizeBytes
    }

    public var name: String { "\(platform) \(version)" }
}

public enum SimulatorInventory {
    public static let defaultSelection: Set<String> = []

    /// Unavailable devices from `simctl list devices -j`. A booted device is
    /// never offered, even if simctl calls it unavailable.
    public static func parseDevices(_ data: Data) -> [SimulatorDevice] {
        struct Payload: Decodable {
            struct Device: Decodable {
                let udid: String
                let name: String
                let isAvailable: Bool
                let state: String?
            }
            let devices: [String: [Device]]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.devices.flatMap { runtime, devices in
            devices.compactMap { device in
                guard !device.isAvailable,
                      device.state?.lowercased() != "booted",
                      isSafeIdentifier(device.udid) else { return nil }
                return SimulatorDevice(udid: device.udid, name: device.name, runtime: runtime)
            }
        }
        .sorted { ($0.runtime, $0.name) < ($1.runtime, $1.name) }
    }

    /// Deletable runtimes from `simctl runtime list -j`, minus the newest
    /// version of each platform. The newest is computed over every runtime
    /// (bundled ones included), and a runtime whose platform or version can't
    /// be read is never offered.
    public static func parseRuntimes(_ data: Data) -> [SimulatorRuntime] {
        struct Entry: Decodable {
            let identifier: String?
            let runtimeIdentifier: String?
            let platformIdentifier: String?
            let version: String?
            let deletable: Bool?
            let sizeBytes: Int64?
        }
        guard let payload = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [] }
        let all: [(entry: Entry, id: String, platform: String?)] = payload.map { key, entry in
            (entry, entry.identifier ?? key, platform(runtimeIdentifier: entry.runtimeIdentifier,
                                                     platformIdentifier: entry.platformIdentifier))
        }
        var newest: [String: String] = [:]
        for item in all {
            guard let platform = item.platform, let version = item.entry.version else { continue }
            if let current = newest[platform], !isVersionLess(current, version) { continue }
            newest[platform] = version
        }
        return all.compactMap { item in
            guard item.entry.deletable == true,
                  let platform = item.platform,
                  let version = item.entry.version,
                  let top = newest[platform],
                  isVersionLess(version, top),
                  isSafeIdentifier(item.id) else { return nil }
            return SimulatorRuntime(
                identifier: item.id,
                runtimeIdentifier: item.entry.runtimeIdentifier ?? "",
                platform: platform,
                version: version,
                sizeBytes: item.entry.sizeBytes
            )
        }
        .sorted { ($0.platform, $0.version) < ($1.platform, $1.version) }
    }

    /// Platform name from "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
    /// or from "com.apple.platform.iphonesimulator" when that is all there is.
    static func platform(runtimeIdentifier: String?, platformIdentifier: String?) -> String? {
        if let runtimeIdentifier, let marker = runtimeIdentifier.range(of: "SimRuntime.") {
            let name = runtimeIdentifier[marker.upperBound...].split(separator: "-").first.map(String.init)
            if let name, !name.isEmpty { return name }
        }
        switch platformIdentifier?.lowercased() {
        case "com.apple.platform.iphonesimulator": return "iOS"
        case "com.apple.platform.watchsimulator": return "watchOS"
        case "com.apple.platform.appletvsimulator": return "tvOS"
        case "com.apple.platform.xrsimulator": return "xrOS"
        default: return nil
        }
    }

    /// simctl identifiers are UUIDs. Anything else (including the `all` and
    /// `unavailable` aliases, or a leading dash) is refused before it can
    /// reach a delete command.
    public static func isSafeIdentifier(_ identifier: String) -> Bool {
        UUID(uuidString: identifier) != nil
    }

    /// Arguments for the real simctl binary (not the xcrun shim).
    public static func deleteArguments(deviceUDID: String) -> [String]? {
        isSafeIdentifier(deviceUDID) ? ["delete", deviceUDID] : nil
    }

    public static func deleteRuntimeArguments(identifier: String) -> [String]? {
        isSafeIdentifier(identifier) ? ["runtime", "delete", identifier] : nil
    }

    /// `<developer dir>/usr/bin/simctl` from `xcode-select -p` output, or nil
    /// for a Command Line Tools-only Mac (which has no simctl).
    public static func simctlPath(developerDirectory: String, isExecutable: (String) -> Bool) -> String? {
        let dir = developerDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dir.hasPrefix("/") else { return nil }
        let path = (dir as NSString).appendingPathComponent("usr/bin/simctl")
        return isExecutable(path) ? path : nil
    }

    static func isVersionLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}
