import Foundation

/// A saved preferred Wi-Fi network on one hardware device (issue #50).
public struct PreferredWiFiNetwork: Hashable, Sendable, Identifiable {
    public var id: String { device + "\u{0}" + ssid }
    public let device: String
    public let ssid: String

    public init(device: String, ssid: String) {
        self.device = device
        self.ssid = ssid
    }
}

/// Parses `networksetup` stdout. No Process — fixtures in tests.
public enum PreferredWiFiParser {

    public static func wifiDevices(from hardwarePortsOutput: String) -> [String] {
        let lines = hardwarePortsOutput.split(whereSeparator: \.isNewline).map(String.init)
        var devices: [String] = []
        var pendingWiFi = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("hardware port:") {
                pendingWiFi = isWiFiPort(trimmed)
                continue
            }
            if pendingWiFi, let device = deviceName(from: trimmed) {
                devices.append(device)
                pendingWiFi = false
            }
        }
        return devices
    }

    public static func preferredNetworks(from output: String, device: String) -> [PreferredWiFiNetwork] {
        let lower = output.lowercased()
        if lower.contains("is not a wi-fi interface") || lower.contains("is not a wifi interface") {
            return []
        }
        var networks: [PreferredWiFiNetwork] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            guard line.first == "\t" || line.hasPrefix("    ") else { continue }
            let ssid = line.drop(while: { $0 == "\t" || $0 == " " })
            guard !ssid.isEmpty else { continue }
            // Never list a network that cannot be removed: showing it would
            // promise an action that the root-command builders refuse.
            guard PreferredWiFiCommands.isValidSSID(String(ssid)) else { continue }
            networks.append(PreferredWiFiNetwork(device: device, ssid: String(ssid)))
        }
        return networks
    }

    private static func isWiFiPort(_ hardwarePortLine: String) -> Bool {
        let value = hardwarePortLine
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return value.contains("wi-fi") || value.contains("wifi")
            || value.contains("airport") || value.contains("wlan")
    }

    private static func deviceName(from line: String) -> String? {
        let lower = line.lowercased()
        guard lower.hasPrefix("device:") else { return nil }
        let name = line.split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }
}

/// Argv and quoted-shell builders for `networksetup`. Device names are
/// allowlisted so a parser bug cannot smuggle shell metacharacters.
public enum PreferredWiFiCommands {
    public static let networksetup = "/usr/sbin/networksetup"

    public static let listHardwarePortsArguments = ["-listallhardwareports"]

    public static func isValidDevice(_ device: String) -> Bool {
        guard !device.isEmpty, device.count <= 16 else { return false }
        let scalars = device.unicodeScalars
        guard let first = scalars.first, CharacterSet.letters.contains(first) else { return false }
        return scalars.dropFirst().allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    /// An SSID is text chosen by whoever operates the access point, so it is
    /// attacker-controlled: it arrives from the output of
    /// `-listpreferredwirelessnetworks`, i.e. the broadcast name of a network
    /// the machine once joined.
    ///
    /// Shell metacharacters are already neutralized because every builder
    /// re-quotes through `MaintenanceShell.quote`. A leading dash is not,
    /// because it is not shell syntax — it only changes how the tool parses its
    /// own arguments, and `-removepreferredwirelessnetwork` is run as ROOT.
    /// `networksetup` re-scans option tokens positionally, so a network named
    /// `-getallpowermanagerstate` makes the elevated command perform a different
    /// operation than the one the user clicked.
    public static func isValidSSID(_ ssid: String) -> Bool {
        guard !ssid.isEmpty, ssid.count <= 64 else { return false }
        guard !ssid.hasPrefix("-") else { return false }
        // 802.11 names cannot contain control characters; rejecting them keeps a
        // crafted name from injecting extra arguments or forging log lines.
        return !ssid.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    public static func listPreferredArguments(device: String) -> [String]? {
        guard isValidDevice(device) else { return nil }
        return ["-listpreferredwirelessnetworks", device]
    }

    public static func removeArguments(device: String, ssid: String) -> [String]? {
        guard isValidDevice(device), isValidSSID(ssid) else { return nil }
        return ["-removepreferredwirelessnetwork", device, ssid]
    }

    public static func removeShellCommand(device: String, ssid: String) -> String? {
        guard let args = removeArguments(device: device, ssid: ssid) else { return nil }
        return MaintenanceShell.commandLine(networksetup, args)
    }

    public static func removeBatchShellCommand(networks: [PreferredWiFiNetwork]) -> String? {
        guard !networks.isEmpty else { return nil }
        var parts: [String] = []
        parts.reserveCapacity(networks.count)
        for net in networks {
            guard let part = removeShellCommand(device: net.device, ssid: net.ssid) else { return nil }
            parts.append(part)
        }
        return parts.joined(separator: " ; ")
    }
}
