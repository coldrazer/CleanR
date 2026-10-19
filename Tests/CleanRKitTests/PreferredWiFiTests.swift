import XCTest
@testable import CleanRKit

final class PreferredWiFiTests: XCTestCase {

    private let hardwareFixture = """
        Hardware Port: Ethernet
        Device: en1
        Ethernet Address: 11:22:33:44:55:66

        Hardware Port: Wi-Fi
        Device: en0
        Ethernet Address: aa:bb:cc:dd:ee:ff

        Hardware Port: Thunderbolt Bridge
        Device: bridge0
        Ethernet Address: 00:11:22:33:44:55
        """

    private let preferredFixture = """
        Preferred networks on en0:
        \tHome Network
        \tCafe WiFi
        \t'; rm -rf /
        """

    func testHardwarePortsFindsWiFiDeviceOnly() {
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: hardwareFixture), ["en0"])
    }

    func testHardwarePortsFindsAirPortAndWLAN() {
        let airport = """
            Hardware Port: AirPort
            Device: en2
            Ethernet Address: 00:00:00:00:00:00
            """
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: airport), ["en2"])

        let wlan = """
            Hardware Port: WLAN
            Device: en3
            Ethernet Address: 00:00:00:00:00:00
            """
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: wlan), ["en3"])
    }

    func testHardwarePortsEmptyWhenNoWiFi() {
        let ethernetOnly = """
            Hardware Port: Ethernet
            Device: en1
            Ethernet Address: 11:22:33:44:55:66
            """
        XCTAssertEqual(PreferredWiFiParser.wifiDevices(from: ethernetOnly), [])
    }

    func testPreferredNetworksStripsHeaderAndIndent() {
        let nets = PreferredWiFiParser.preferredNetworks(from: preferredFixture, device: "en0")
        XCTAssertEqual(nets.map(\.ssid), ["Home Network", "Cafe WiFi", "'; rm -rf /"])
        XCTAssertTrue(nets.allSatisfy { $0.device == "en0" })
    }

    func testPreferredNetworksEmptyList() {
        let output = "Preferred networks on en0:\n"
        XCTAssertTrue(PreferredWiFiParser.preferredNetworks(from: output, device: "en0").isEmpty)
    }

    func testPreferredNetworksNotAWiFiInterface() {
        let output = "en1 is not a Wi-Fi interface.\n"
        XCTAssertTrue(PreferredWiFiParser.preferredNetworks(from: output, device: "en1").isEmpty)
    }

    func testValidDevices() {
        XCTAssertTrue(PreferredWiFiCommands.isValidDevice("en0"))
        XCTAssertTrue(PreferredWiFiCommands.isValidDevice("en12"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("en0; reboot"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("en0 en1"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice(""))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("/tmp/x"))
        XCTAssertFalse(PreferredWiFiCommands.isValidDevice("$(whoami)"))
    }

    func testRemoveArgv() {
        XCTAssertEqual(
            PreferredWiFiCommands.removeArguments(device: "en0", ssid: "Cafe WiFi") ?? [],
            ["-removepreferredwirelessnetwork", "en0", "Cafe WiFi"]
        )
    }

    func testRemoveShellQuotesMetacharacters() {
        let line = PreferredWiFiCommands.removeShellCommand(device: "en0", ssid: "'; rm -rf /")
        XCTAssertEqual(
            line,
            "'/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' ''\\''; rm -rf /'"
        )
    }

    func testRemoveShellRejectsIllegalDevice() {
        XCTAssertNil(PreferredWiFiCommands.removeShellCommand(device: "en0; reboot", ssid: "Home"))
    }

    func testBatchJoinsQuotedCommands() {
        let nets = [
            PreferredWiFiNetwork(device: "en0", ssid: "A"),
            PreferredWiFiNetwork(device: "en0", ssid: "B"),
        ]
        let batch = PreferredWiFiCommands.removeBatchShellCommand(networks: nets)
        XCTAssertEqual(
            batch,
            "'/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' 'A' ; '/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' 'B'"
        )
    }

    func testBatchNilIfAnyDeviceIllegal() {
        let nets = [
            PreferredWiFiNetwork(device: "en0", ssid: "A"),
            PreferredWiFiNetwork(device: "en0;x", ssid: "B"),
        ]
        XCTAssertNil(PreferredWiFiCommands.removeBatchShellCommand(networks: nets))
    }

    func testListCommands() {
        XCTAssertEqual(PreferredWiFiCommands.listHardwarePortsArguments, ["-listallhardwareports"])
        XCTAssertEqual(
            PreferredWiFiCommands.listPreferredArguments(device: "en0"),
            ["-listpreferredwirelessnetworks", "en0"]
        )
        XCTAssertNil(PreferredWiFiCommands.listPreferredArguments(device: "en0;x"))
    }

    // MARK: - SSID argument injection

    /// The SSID is the broadcast name of a network the machine once joined, so
    /// an access point operator picks it. `-removepreferredwirelessnetwork` runs
    /// as root, and quoting does not help against a leading dash: it is not
    /// shell syntax, it is an option token that networksetup re-scans
    /// positionally, turning "forget this network" into a different root
    /// operation.
    func testRejectsOptionTokenSSIDs() {
        for ssid in ["-getallpowermanagerstate", "-listallhardwareports", "--help", "-rf", "-"] {
            XCTAssertFalse(PreferredWiFiCommands.isValidSSID(ssid), "\(ssid) must be rejected")
            XCTAssertNil(
                PreferredWiFiCommands.removeArguments(device: "en0", ssid: ssid),
                "\(ssid) must never reach a root argv"
            )
            XCTAssertNil(PreferredWiFiCommands.removeShellCommand(device: "en0", ssid: ssid))
        }
    }

    func testRejectsControlCharactersInSSID() {
        XCTAssertFalse(PreferredWiFiCommands.isValidSSID("Cafe\nWiFi"))
        XCTAssertFalse(PreferredWiFiCommands.isValidSSID("Cafe\tWiFi"))
        XCTAssertFalse(PreferredWiFiCommands.isValidSSID("Cafe\u{0}WiFi"))
        XCTAssertFalse(PreferredWiFiCommands.isValidSSID("Cafe\u{7F}WiFi"))
    }

    func testAcceptsOrdinaryAndUnicodeSSIDs() {
        XCTAssertTrue(PreferredWiFiCommands.isValidSSID("Cafe WiFi"))
        XCTAssertTrue(PreferredWiFiCommands.isValidSSID("Café—Router"))
        XCTAssertTrue(PreferredWiFiCommands.isValidSSID("_wifi.2G"))
        XCTAssertTrue(PreferredWiFiCommands.isValidSSID("'\"; rm -rf /"))
        XCTAssertTrue(PreferredWiFiCommands.isValidSSID(String(repeating: "a", count: 64)))
    }

    func testRejectsEmptyAndOversizeSSIDs() {
        XCTAssertFalse(PreferredWiFiCommands.isValidSSID(""))
        XCTAssertFalse(PreferredWiFiCommands.isValidSSID(String(repeating: "a", count: 65)))
    }

    /// A forged token must not survive parsing either, so it never renders as a
    /// row the user could click.
    func testParserDropsUnremovableNetworkNames() {
        let output = "Preferred Networks:\n\tHome\n\t-getallpowermanagerstate\n\tBad\tName\n"
        let networks = PreferredWiFiParser.preferredNetworks(from: output, device: "en0")
        XCTAssertEqual(networks.map(\.ssid), ["Home"])
    }

    func testRemoveBatchRejectsIfAnySSIDIsAToken() {
        let nets = [
            PreferredWiFiNetwork(device: "en0", ssid: "A"),
            PreferredWiFiNetwork(device: "en0", ssid: "-getallpowermanagerstate"),
        ]
        XCTAssertNil(PreferredWiFiCommands.removeBatchShellCommand(networks: nets))
    }
}
