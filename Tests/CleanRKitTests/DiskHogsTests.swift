import XCTest
@testable import CleanRKit

final class DiskHogsTests: AppLanguageTestCase {
    // MARK: - docker system df

    func testParsesDockerSystemDFTable() {
        let text = """
        TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
        Images          12        5         4.2GB     1.8GB (42%)
        Containers      8         2         120MB     80MB (66%)
        Local Volumes   6         1         2.1GB     1.5GB (71%)
        Build Cache     40        0         3.4GB     3.4GB
        """
        let rows = DockerSystemDFParser.parse(text)
        XCTAssertEqual(rows.map(\.category), [.images, .containers, .volumes, .buildCache])
        XCTAssertEqual(rows[0].size, "4.2GB")
        XCTAssertEqual(rows[0].reclaimable, "1.8GB (42%)")
        XCTAssertEqual(rows[2].size, "2.1GB")
        XCTAssertEqual(rows[3].reclaimable, "3.4GB")
    }

    func testParsesDockerSystemDFJSONLines() {
        // Real output from Docker 28.4 with `--format '{{json .}}'`.
        let text = """
        {"Active":"36","Reclaimable":"9.954GB (36%)","Size":"27.12GB","TotalCount":"53","Type":"Images"}
        {"Active":"47","Reclaimable":"614.1kB (0%)","Size":"89.94MB","TotalCount":"50","Type":"Containers"}
        {"Active":"14","Reclaimable":"10.15kB (0%)","Size":"3.025GB","TotalCount":"15","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"9.581MB","Size":"9.581MB","TotalCount":"30","Type":"Build Cache"}
        """
        let rows = DockerSystemDFParser.parse(text)
        XCTAssertEqual(rows.map(\.category), [.images, .containers, .volumes, .buildCache])
        XCTAssertEqual(rows.map(\.size), ["27.12GB", "89.94MB", "3.025GB", "9.581MB"])
        XCTAssertEqual(DockerSystemDFParser.arguments, ["system", "df", "--format", "{{json .}}"])
    }

    func testDockerDFIgnoresGarbage() {
        XCTAssertTrue(DockerSystemDFParser.parse("").isEmpty)
        XCTAssertTrue(DockerSystemDFParser.parse("Cannot connect to the Docker daemon at unix:///var/run/docker.sock.").isEmpty)
        XCTAssertTrue(DockerSystemDFParser.parse("json\njson\n").isEmpty)
    }

    // MARK: - Docker prune safety

    func testVolumesAreNeverPrunable() {
        XCTAssertFalse(DockerDiskCategory.volumes.isPrunable)
        XCTAssertEqual(DockerPrune.arguments(for: [.volumes]), [])
        let all = DockerPrune.arguments(for: Set(DockerDiskCategory.allCases))
        XCTAssertFalse(all.contains { $0.contains("volume") })
    }

    func testDockerPruneArgumentArraysAreExactAndStartUnselected() {
        XCTAssertTrue(DockerPrune.defaultSelection.isEmpty)
        XCTAssertTrue(DockerPrune.arguments(for: []).isEmpty)
        XCTAssertEqual(DockerPrune.arguments(for: Set(DockerDiskCategory.allCases)), [
            ["image", "prune", "-f"],
            ["container", "prune", "-f"],
            ["builder", "prune", "-f"],
        ])
        XCTAssertEqual(DockerPrune.commands(for: [.containers]).map(\.category), [.containers])
        // No `-a` / `--all`: image and builder prune stay limited to dangling data.
        for args in DockerPrune.arguments(for: Set(DockerDiskCategory.allCases)) {
            XCTAssertFalse(args.contains("-a"))
            XCTAssertFalse(args.contains("--all"))
        }
    }

    // MARK: - simctl devices

    func testParsesOnlyUnavailableNonBootedDevices() {
        let data = Data("""
        {"devices":{
          "com.apple.CoreSimulator.SimRuntime.iOS-17-5":[
            {"udid":"6F1B9F7E-5D0E-4D3A-9C55-6B0E1F0C0A01","name":"iPhone 15","isAvailable":true,"state":"Shutdown"},
            {"udid":"6F1B9F7E-5D0E-4D3A-9C55-6B0E1F0C0A02","name":"iPhone 14","isAvailable":false,"state":"Shutdown"},
            {"udid":"6F1B9F7E-5D0E-4D3A-9C55-6B0E1F0C0A03","name":"Booted","isAvailable":false,"state":"Booted"},
            {"udid":"all","name":"Hostile","isAvailable":false}
          ]
        }}
        """.utf8)
        let devices = SimulatorInventory.parseDevices(data)
        XCTAssertEqual(devices.map(\.name), ["iPhone 14"])
        XCTAssertEqual(devices.first?.runtimeDisplayName, "iOS 17.5")
    }

    // MARK: - simctl runtimes

    private func runtimeJSON(_ entries: [(uuid: String, runtime: String?, platform: String?, version: String, deletable: Bool)]) -> Data {
        let body = entries.map { entry -> String in
            var fields = ["\"identifier\":\"\(entry.uuid)\"", "\"version\":\"\(entry.version)\"",
                          "\"deletable\":\(entry.deletable)", "\"sizeBytes\":7229898592"]
            if let runtime = entry.runtime { fields.append("\"runtimeIdentifier\":\"\(runtime)\"") }
            if let platform = entry.platform { fields.append("\"platformIdentifier\":\"\(platform)\"") }
            return "\"\(entry.uuid)\":{\(fields.joined(separator: ","))}"
        }
        return Data("{\(body.joined(separator: ","))}".utf8)
    }

    private let ios18 = "11111111-1111-1111-1111-111111111111"
    private let ios17 = "22222222-2222-2222-2222-222222222222"
    private let watch11 = "33333333-3333-3333-3333-333333333333"
    private let watch10 = "44444444-4444-4444-4444-444444444444"

    func testNewestRuntimePerPlatformIsNeverOffered() {
        let data = runtimeJSON([
            (ios18, "com.apple.CoreSimulator.SimRuntime.iOS-18-0", nil, "18.0", true),
            (ios17, "com.apple.CoreSimulator.SimRuntime.iOS-17-5", nil, "17.5", true),
            (watch11, "com.apple.CoreSimulator.SimRuntime.watchOS-11-0", nil, "11.0", true),
        ])
        let runtimes = SimulatorInventory.parseRuntimes(data)
        XCTAssertEqual(runtimes.map(\.identifier), [ios17])
        XCTAssertEqual(runtimes.first?.name, "iOS 17.5")
        XCTAssertEqual(runtimes.first?.sizeBytes, 7_229_898_592)
        XCTAssertEqual(
            SimulatorInventory.deleteRuntimeArguments(identifier: ios17),
            ["runtime", "delete", ios17]
        )
    }

    func testNewestCountsNonDeletableRuntimesAndSkipsThem() {
        // A bundled iOS 18 runtime can't be deleted but still makes 17.5 "older".
        let data = runtimeJSON([
            (ios18, "com.apple.CoreSimulator.SimRuntime.iOS-18-0", nil, "18.0", false),
            (ios17, "com.apple.CoreSimulator.SimRuntime.iOS-17-5", nil, "17.5", true),
            (watch10, "com.apple.CoreSimulator.SimRuntime.watchOS-10-0", nil, "10.0", false),
        ])
        XCTAssertEqual(SimulatorInventory.parseRuntimes(data).map(\.identifier), [ios17])
    }

    func testPlatformComesFromPlatformIdentifierWhenRuntimeIdentifierIsMissing() {
        // Without a platform, the newest watchOS must not look older than iOS 18.
        let data = runtimeJSON([
            (ios18, nil, "com.apple.platform.iphonesimulator", "18.0", true),
            (ios17, nil, "com.apple.platform.iphonesimulator", "17.5", true),
            (watch11, nil, "com.apple.platform.watchsimulator", "11.0", true),
            (watch10, nil, nil, "10.0", true),
        ])
        let runtimes = SimulatorInventory.parseRuntimes(data)
        XCTAssertEqual(runtimes.map(\.identifier), [ios17], "unknown platform and newest per platform are skipped")
        XCTAssertEqual(runtimes.first?.platform, "iOS")
    }

    func testRuntimeParserRejectsGarbage() {
        XCTAssertTrue(SimulatorInventory.parseRuntimes(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(SimulatorInventory.parseRuntimes(Data("not json".utf8)).isEmpty)
    }

    // MARK: - Identifier safety and simctl location

    func testDeleteCommandsRefuseNonUUIDIdentifiers() {
        let udid = "6F1B9F7E-5D0E-4D3A-9C55-6B0E1F0C0A02"
        XCTAssertEqual(SimulatorInventory.deleteArguments(deviceUDID: udid), ["delete", udid])
        for hostile in ["all", "unavailable", "--notUsedSinceDays", "-d", "", "com.apple.CoreSimulator.SimRuntime.iOS-17-5"] {
            XCTAssertNil(SimulatorInventory.deleteArguments(deviceUDID: hostile), hostile)
            XCTAssertNil(SimulatorInventory.deleteRuntimeArguments(identifier: hostile), hostile)
        }
        XCTAssertTrue(SimulatorInventory.defaultSelection.isEmpty)
    }

    func testSimctlPathUsesTheDeveloperDirectoryNeverTheShim() {
        let xcode = "/Applications/Xcode.app/Contents/Developer\n"
        XCTAssertEqual(
            SimulatorInventory.simctlPath(developerDirectory: xcode) { $0 == "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl" },
            "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"
        )
        // Command Line Tools only: no simctl, so nothing runs.
        XCTAssertNil(SimulatorInventory.simctlPath(developerDirectory: "/Library/Developer/CommandLineTools") { _ in false })
        XCTAssertNil(SimulatorInventory.simctlPath(developerDirectory: "xcode-select: error: unable to get active developer directory") { _ in true })
    }

    // MARK: - Status lines

    func testStatusLinesReportEachOutcome() {
        AppLanguage.current = .en
        XCTAssertEqual(DiskHogsText.statusLine(name: "Images", outcome: .exited(status: 0, stdout: Data(), stderr: Data()), success: "Pruned"),
                       "Images: Pruned")
        XCTAssertEqual(DiskHogsText.statusLine(name: "Images", outcome: .exited(status: 1, stdout: Data(), stderr: Data("Error response from daemon: busy\nmore".utf8)), success: "Pruned"),
                       "Images: Failed (Error response from daemon: busy)")
        XCTAssertEqual(DiskHogsText.statusLine(name: "iOS 17.5", outcome: .timedOut, success: "Deleted"),
                       "iOS 17.5: Timed out and was stopped")
        XCTAssertEqual(DiskHogsText.statusLine(name: "iOS 17.5", outcome: .cancelled, success: "Deleted"),
                       "iOS 17.5: Stopped")
    }
}
