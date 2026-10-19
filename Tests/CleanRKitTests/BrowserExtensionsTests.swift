import XCTest
@testable import CleanRKit

final class BrowserExtensionsTests: XCTestCase {
    private let chromeID = "abcdefghijklmnopabcdefghijklmnop"
    private let chromePath = "/Users/me/Library/Application Support/Google/Chrome/Default/Extensions/abcdefghijklmnopabcdefghijklmnop"

    private func record(
        browser: BrowserKind = .chrome,
        profile: String = "Default",
        identifier: String? = nil,
        path: String? = nil,
        origin: BrowserExtensionOrigin = .user
    ) -> BrowserExtensionRecord {
        BrowserExtensionRecord(
            browser: browser, profile: profile, identifier: identifier ?? chromeID, name: "A",
            updatedAt: nil, path: path ?? chromePath, origin: origin, isSuspicious: false
        )
    }

    // MARK: - Chromium manifest

    func testParsesChromeFamilyManifest() throws {
        let json = #"{"name":"Nice Tab","version":"1.2.0","manifest_version":3}"#.data(using: .utf8)!
        let record = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json, extensionID: chromeID, browser: .chrome, profile: "Default",
            path: chromePath, updatedAt: Date(timeIntervalSince1970: 50)
        ))
        XCTAssertEqual(record.name, "Nice Tab")
        XCTAssertEqual(record.browser, .chrome)
        XCTAssertEqual(record.profile, "Default")
        XCTAssertEqual(record.updatedAt, Date(timeIntervalSince1970: 50))
        XCTAssertFalse(record.isSuspicious)
    }

    func testRejectsInvalidChromiumIDs() {
        let json = #"{"name":"X"}"#.data(using: .utf8)!
        for bad in ["Temp", "abc", "ABCDEFGHIJKLMNOPABCDEFGHIJKLMNOP", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", "..", "abcdefghijklmnopabcdefghijklmnopa"] {
            XCTAssertNil(BrowserExtensionManifest.chromeFamily(
                json: json, extensionID: bad, browser: .chrome, profile: "Default", path: "/x", updatedAt: nil
            ), bad)
        }
        XCTAssertTrue(ChromiumExtensionID.isValid("ghbmnnjooekpmoecnnnilnnbdlolhkhi"))
    }

    func testLocalizedNameTriesDefaultLocaleFirst() throws {
        let json = #"{"name":"__MSG_extName__","default_locale":"fr"}"#.data(using: .utf8)!
        let record = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json, extensionID: chromeID, browser: .brave, profile: "Default", path: "/ext", updatedAt: nil,
            messages: { locale in
                switch locale {
                case "fr": #"{"extName":{"message":"Nom Français"}}"#.data(using: .utf8)
                case "en": #"{"extName":{"message":"English Name"}}"#.data(using: .utf8)
                default: nil
                }
            }
        ))
        XCTAssertEqual(record.name, "Nom Français")
    }

    func testLocalizedNameFallsBackToEnglishThenFolderID() throws {
        let json = #"{"name":"__MSG_extName__","default_locale":"de"}"#.data(using: .utf8)!
        let english = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json, extensionID: chromeID, browser: .chrome, profile: "Default", path: "/ext", updatedAt: nil,
            messages: { $0 == "en" ? #"{"extName":{"message":"English Name"}}"#.data(using: .utf8) : nil }
        ))
        XCTAssertEqual(english.name, "English Name")

        let none = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json, extensionID: chromeID, browser: .chrome, profile: "Default", path: "/ext", updatedAt: nil
        ))
        XCTAssertEqual(none.name, chromeID, "never show a raw __MSG_ placeholder")
    }

    func testChromeMessageKeysAreCaseInsensitive() throws {
        // Real Google Docs Offline: manifest says __MSG_extName__, file says "extname".
        let json = #"{"name":"__MSG_extName__","default_locale":"en_US"}"#.data(using: .utf8)!
        let record = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json, extensionID: "ghbmnnjooekpmoecnnnilnnbdlolhkhi", browser: .chrome,
            profile: "Default", path: "/ext", updatedAt: nil,
            messages: { _ in #"{"extname":{"message":"Google Docs Offline"}}"#.data(using: .utf8) }
        ))
        XCTAssertEqual(record.name, "Google Docs Offline")
    }

    func testVersionFoldersSortNumerically() {
        XCTAssertEqual(ChromiumVersionFolder.newest(["1.9.0_0", "1.10.0_0", "1.2.3_0"]), "1.10.0_0")
        XCTAssertEqual(ChromiumVersionFolder.newest(["2.0_0", "10.0_0"]), "10.0_0")
        XCTAssertEqual(ChromiumVersionFolder.newest(["1.0_0", "1.0_1"]), "1.0_1")
        XCTAssertNil(ChromiumVersionFolder.newest([]))
    }

    func testSameExtensionInTwoProfilesHasDistinctIDs() {
        let a = record(profile: "Default")
        let b = record(profile: "Profile 1", path: chromePath.replacingOccurrences(of: "/Default/", with: "/Profile 1/"))
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Policy and component detection

    func testReadsLocationsFromPreferences() {
        let json = """
        {"extensions":{"settings":{
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":{"location":1},
          "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb":{"location":7},
          "cccccccccccccccccccccccccccccccc":{"location":5},
          "dddddddddddddddddddddddddddddddd":{"no":"location"}
        }}}
        """.data(using: .utf8)!
        let locations = ChromiumPreferences.locations(fromPreferencesJSON: json)
        XCTAssertEqual(locations["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"], 1)
        XCTAssertEqual(locations["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"], 7)
        XCTAssertNil(locations["dddddddddddddddddddddddddddddddd"])
        XCTAssertTrue(ChromiumPreferences.locations(fromPreferencesJSON: Data("garbage".utf8)).isEmpty)
    }

    func testOriginFromLocationAndForcelist() {
        XCTAssertEqual(ChromiumPreferences.origin(for: chromeID, location: 1, forcedIDs: []), .user)
        XCTAssertEqual(ChromiumPreferences.origin(for: chromeID, location: nil, forcedIDs: []), .user)
        XCTAssertEqual(ChromiumPreferences.origin(for: chromeID, location: 7, forcedIDs: []), .policy)
        XCTAssertEqual(ChromiumPreferences.origin(for: chromeID, location: 9, forcedIDs: []), .policy)
        XCTAssertEqual(ChromiumPreferences.origin(for: chromeID, location: 5, forcedIDs: []), .component)
        XCTAssertEqual(ChromiumPreferences.origin(for: chromeID, location: 10, forcedIDs: []), .component)
        XCTAssertEqual(ChromiumPreferences.origin(for: chromeID, location: 1, forcedIDs: [chromeID]), .policy)
    }

    func testParsesForcelistPolicy() {
        let plist: [String: Any] = ["ExtensionInstallForcelist": [
            "\(chromeID);https://clients2.google.com/service/update2/crx",
            "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
        ]]
        XCTAssertEqual(
            ChromiumPreferences.forcedIDs(fromPolicyPlist: plist),
            [chromeID, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
        )
        XCTAssertTrue(ChromiumPreferences.forcedIDs(fromPolicyPlist: [:]).isEmpty)
    }

    // MARK: - Suspicion

    func testFlagsKnownBadIDsAndAdwareNames() throws {
        let json = #"{"name":"Search Helper","manifest_version":3}"#.data(using: .utf8)!
        let byID = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json, extensionID: chromeID, browser: .edge, profile: "Default", path: "/ext",
            updatedAt: nil, knownBadIDs: [chromeID]
        ))
        XCTAssertTrue(byID.isSuspicious)

        let clean = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: json, extensionID: chromeID, browser: .edge, profile: "Default", path: "/ext", updatedAt: nil
        ))
        XCTAssertFalse(clean.isSuspicious)

        let byName = try XCTUnwrap(BrowserExtensionManifest.chromeFamily(
            json: #"{"name":"SearchBaron Tools"}"#.data(using: .utf8)!,
            extensionID: chromeID, browser: .chrome, profile: "Default", path: "/ext", updatedAt: nil
        ))
        XCTAssertTrue(byName.isSuspicious)
    }

    func testShippedBadIDListHasNoPlaceholders() {
        XCTAssertTrue(MaliciousExtensionIDs.known.allSatisfy(ChromiumExtensionID.isValid))
    }

    // MARK: - Firefox

    func testParsesFirefoxExtensionsJSON() throws {
        let json = """
        {"addons":[
          {"id":"uBlock0@raymondhill.net","type":"extension","defaultLocale":{"name":"uBlock Origin"},"installDate":1700000000000,"location":"app-profile","path":"/p/abcd.default-release/extensions/uBlock0@raymondhill.net.xpi"},
          {"id":"langpack","type":"locale","defaultLocale":{"name":"English"},"installDate":1,"location":"app-profile","path":"/p/abcd.default-release/extensions/langpack.xpi"}
        ]}
        """.data(using: .utf8)!
        let records = BrowserExtensionManifest.firefox(json: json, profilePath: "/p/abcd.default-release")
        XCTAssertEqual(records.map(\.name), ["uBlock Origin"])
        XCTAssertEqual(records[0].browser, .firefox)
        XCTAssertEqual(records[0].profile, "abcd.default-release")
        XCTAssertEqual(records[0].updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testFirefoxSkipsBuiltinSystemAndTemporaryAddons() {
        let json = """
        {"addons":[
          {"id":"webcompat@mozilla.org","type":"extension","location":"app-system-defaults","path":"/Applications/Firefox.app/Contents/Resources/browser/features/webcompat@mozilla.org.xpi"},
          {"id":"builtin@mozilla.org","type":"extension","location":"app-builtin","path":null},
          {"id":"dev@me","type":"extension","location":"app-temporary","path":"/Users/me/Code/my-addon"},
          {"id":"evil@x","type":"extension","location":"app-profile","path":"/profile/extensions/../../Users/me/Documents"},
          {"id":"elsewhere@x","type":"extension","location":"app-profile","path":"/Users/me/Code/unpacked"},
          {"id":"ok@x","type":"extension","location":"app-profile","path":"/profile/extensions/ok@x.xpi"}
        ]}
        """.data(using: .utf8)!
        let records = BrowserExtensionManifest.firefox(json: json, profilePath: "/profile")
        XCTAssertEqual(records.map(\.identifier), ["ok@x"])
    }

    func testFirefoxNamesAreCheckedForAdware() {
        let json = #"{"addons":[{"id":"x@y","type":"extension","defaultLocale":{"name":"Pirrit Search"},"location":"app-profile","path":"/profile/extensions/x@y.xpi"}]}"#
            .data(using: .utf8)!
        XCTAssertEqual(BrowserExtensionManifest.firefox(json: json, profilePath: "/profile").first?.isSuspicious, true)
    }

    // MARK: - Safari

    func testSafariUsesThirdPartyAppExtensionsOnly() {
        func item(_ name: String, _ bundleID: String, _ path: String, apple: Bool = false, kind: ManagedExtensionKind = .safariExtension) -> ManagedExtension {
            ManagedExtension(
                kind: kind, name: name, bundleIdentifier: bundleID, path: URL(filePath: path),
                hostAppPath: nil, domain: .user, isApple: apple, election: .enabled, safariPointIdentifier: nil
            )
        }
        let records = BrowserExtensionManifest.safari([
            item("1Blocker", "com.example.blocker", "/Applications/1Blocker.app/Contents/PlugIns/Blocker.appex"),
            item("Apple Thing", "com.apple.x", "/Applications/Safari.app/Contents/PlugIns/X.appex", apple: true),
            item("Legacy", "com.example.legacy", "/Users/me/Library/Safari/Extensions/Legacy.safariextz"),
            item("Pane", "com.example.pane", "/Library/PreferencePanes/P.prefPane", kind: .preferencePane),
        ])
        XCTAssertEqual(records.map(\.name), ["1Blocker"])
        XCTAssertEqual(records[0].origin, .safariApp)
        XCTAssertEqual(BrowserExtensionRemoval.plan(record: records[0], browserIsRunning: false), .safariSettings)
    }

    // MARK: - Removal plan

    func testRemovalPlan() {
        XCTAssertEqual(BrowserExtensionRemoval.plan(record: record(), browserIsRunning: true), .removeInBrowser(.chrome))
        XCTAssertEqual(BrowserExtensionRemoval.plan(record: record(), browserIsRunning: false), .deleteFolder(chromePath))
        XCTAssertEqual(BrowserExtensionRemoval.plan(record: record(origin: .policy), browserIsRunning: false), .managedByPolicy(.chrome))
        XCTAssertEqual(BrowserExtensionRemoval.plan(record: record(origin: .component), browserIsRunning: false), .builtIn(.chrome))
    }

    func testRemovalRefusesPathsOutsideTheProfileExtensionsFolder() {
        let unsafe = [
            "/Users/me/Library/Application Support/Google/Chrome/Default/Extensions",
            "/Users/me/Library/Application Support/Google/Chrome/Default",
            "/Users/me/Library/Application Support/Google/Chrome/Profile 1/Extensions/\(chromeID)",
            "/Users/me/Library/Application Support/Google/Chrome/Default/Extensions/\(chromeID)/1.0_0",
            "/Users/me/Library/Application Support/Google/Chrome/Default/Extensions/../../../../Documents",
            "/Users/me/Documents/\(chromeID)",
        ]
        for path in unsafe {
            XCTAssertEqual(BrowserExtensionRemoval.plan(record: record(path: path), browserIsRunning: false), .refuse, path)
        }
        let firefox = record(browser: .firefox, profile: "abcd.default", identifier: "ok@x", path: "/p/abcd.default/extensions/ok@x.xpi")
        XCTAssertEqual(BrowserExtensionRemoval.plan(record: firefox, browserIsRunning: false), .deleteFolder("/p/abcd.default/extensions/ok@x.xpi"))
        let firefoxOutside = record(browser: .firefox, profile: "abcd.default", identifier: "ok@x", path: "/Applications/Firefox.app/Contents/Resources/browser/features/ok@x.xpi")
        XCTAssertEqual(BrowserExtensionRemoval.plan(record: firefoxOutside, browserIsRunning: false), .refuse)
    }

    func testFirefoxBundleIDsCoverEveryChannel() {
        XCTAssertTrue(BrowserKind.firefox.bundleIdentifiers.isSuperset(of: [
            "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        ]))
    }

    // MARK: - Profile locks

    func testChromiumSingletonLockSymlinkMeansRunning() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(BrowserProfileLock.chromiumUserDataIsLocked(dir))
        // Chrome's link target ("host-pid") never exists; lstat must still see it.
        try FileManager.default.createSymbolicLink(
            atPath: dir.appending(path: "SingletonLock").path(percentEncoded: false),
            withDestinationPath: "myhost-12345"
        )
        XCTAssertTrue(BrowserProfileLock.chromiumUserDataIsLocked(dir))
    }

    func testFirefoxParentlockFileAloneDoesNotMeanRunning() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(BrowserProfileLock.firefoxProfileIsLocked(dir))
        FileManager.default.createFile(atPath: dir.appending(path: ".parentlock").path(percentEncoded: false), contents: Data())
        XCTAssertFalse(BrowserProfileLock.firefoxProfileIsLocked(dir))
    }

    func testFirefoxHeldParentlockMeansRunning() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/python3"), "needs python3 to hold a lock")
        let dir = FileManager.default.temporaryDirectory.appending(path: "bx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lock = dir.appending(path: ".parentlock").path(percentEncoded: false)
        FileManager.default.createFile(atPath: lock, contents: Data())

        // Another process holds a POSIX write lock, as Firefox does.
        let holder = Process()
        holder.executableURL = URL(filePath: "/usr/bin/python3")
        holder.arguments = ["-I", "-c", """
        import fcntl, sys, time
        f = open(sys.argv[1], 'r+')
        fcntl.lockf(f, fcntl.LOCK_EX)
        print('locked', flush=True)
        time.sleep(30)
        """, lock]
        let out = Pipe()
        holder.standardOutput = out
        try holder.run()
        defer { holder.terminate() }
        _ = out.fileHandleForReading.availableData   // wait for "locked"
        XCTAssertTrue(BrowserProfileLock.firefoxProfileIsLocked(dir))
    }
}
