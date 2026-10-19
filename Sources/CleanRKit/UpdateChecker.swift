import Foundation

/// Manual "Check for updates" against the GitHub Releases API.
///
/// Pure logic (semver compare, JSON parsing, Homebrew detection) is static
/// and unit-tested with fixtures; `check(...)` is the only networked entry
/// point. It runs at launch and on every activation, throttled by
/// `UpdateScheduler.isCheckDue`, in addition to the Settings button.
public enum UpdateChecker {
    public enum CheckResult: Equatable, Sendable {
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(message: String)
    }

    /// Subset of the GitHub "latest release" payload we use.
    private struct LatestRelease: Decodable {
        let tag_name: String
        let html_url: String
    }

    /// Hosts we are willing to read a version from.
    public static let allowedEndpointHosts: Set<String> = ["api.github.com", "formulae.brew.sh"]

    /// True when a response really came from one of our endpoints — checked
    /// both on the request we made and on any redirect hop we allowed through.
    public static func isExpectedEndpoint(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return allowedEndpointHosts.contains(host)
    }

    /// The release URL from the API payload is handed straight to
    /// `NSWorkspace.open` when the user clicks the update popup, so it has to
    /// be a page on GitHub over which we have no control at all otherwise:
    /// another host, or a `file:`/`javascript:` scheme, is a malformed
    /// response rather than an update.
    public static func isSafeReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "github.com"
    }

    /// Parse the latest-release JSON into (version without "v" prefix,
    /// release page URL). Returns nil for malformed payloads.
    public static func parseLatestRelease(_ data: Data) -> (version: String, url: URL)? {
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
              let url = URL(string: release.html_url),
              isSafeReleaseURL(url) else { return nil }
        var version = release.tag_name
        if version.hasPrefix("v") { version.removeFirst() }
        guard !version.isEmpty, versionComponents(version).isNumeric else { return nil }
        return (version, url)
    }

    /// A version is a dotted run of decimal components, optionally followed by
    /// a pre-release marker ("1.2.0-rc.1").
    public struct VersionCore: Sendable, Equatable {
        public let components: [Int]
        public let isNumeric: Bool
        public let hasPrereleaseSuffix: Bool
    }

    public static func versionComponents(_ version: String) -> VersionCore {
        let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty else { return VersionCore(components: [], isNumeric: false, hasPrereleaseSuffix: false) }
        var numbers: [Int] = []
        for (index, piece) in pieces.enumerated() {
            let digits = piece.prefix(while: \.isNumber)
            let rest = piece.dropFirst(digits.count)
            guard !digits.isEmpty,
                  rest.isEmpty || (index == pieces.count - 1 && (rest.first == "-" || rest.first == "+"))
            else {
                return VersionCore(components: numbers, isNumeric: false, hasPrereleaseSuffix: false)
            }
            numbers.append(Int(digits) ?? 0)
        }
        let prerelease = pieces.last.map { $0.contains("-") || $0.contains("+") } ?? false
        return VersionCore(components: numbers, isNumeric: true, hasPrereleaseSuffix: prerelease)
    }

    /// Numeric component comparison: "1.10.0" is newer than "1.9.0".
    /// Missing components pad as 0; a tag that isn't numeric can never be
    /// newer, and a pre-release of the version we already have is not an
    /// update either (`1.9.0-rc1` vs `1.9.0` compares equal on components).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = versionComponents(candidate)
        let rhs = versionComponents(current)
        guard lhs.isNumeric else { return false }
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l > r }
        }
        // Same numeric core: only a non-pre-release beats a pre-release.
        if rhs.hasPrereleaseSuffix && !lhs.hasPrereleaseSuffix { return true }
        return false
    }

    /// Select the version that can be compared with
    /// `CFBundleShortVersionString`. Sparkle's short version is the marketing
    /// version; `sparkle:version` is only a fallback when no short version is
    /// available anywhere in the appcast.
    public static func preferredAppcastVersion(
        shortVersion: String?,
        buildVersion: String?
    ) -> String? {
        shortVersion ?? buildVersion
    }

    /// Caskroom locations for Apple Silicon and Intel Homebrew prefixes.
    public static let defaultCaskroomPaths = [
        "/opt/homebrew/Caskroom/cleanr",
        "/usr/local/Caskroom/cleanr",
    ]

    /// True when the app was installed via the Homebrew cask. The Settings
    /// UI then shows `brew upgrade --cask cleanr` instead of a DMG link,
    /// so brew's receipt and the installed app never drift.
    public static func isHomebrewInstall(
        caskroomPaths: [String] = defaultCaskroomPaths,
        fileManager: FileManager = .default
    ) -> Bool {
        caskroomPaths.contains { fileManager.fileExists(atPath: $0) }
    }

    /// Where to look for the latest version, per install source. Homebrew
    /// installs start with the cask API (what `brew upgrade` can deliver);
    /// direct/DMG installs start with the GitHub release (they get the DMG
    /// directly, with no autobump lag).
    public static func updateSourceURL(isHomebrew: Bool) -> URL {
        isHomebrew ? MCConstants.homebrewCaskAPI : MCConstants.latestReleaseAPI
    }

    /// A cask is only listed on formulae.brew.sh once it is merged into
    /// homebrew-core, so a tap-hosted or not-yet-merged cask 404s there. Erroring
    /// out on every launch would train users to ignore the updater, so fall back
    /// to the GitHub release. The Settings UI keeps offering
    /// `brew upgrade --cask cleanr`, which is the correct command for a tap too.
    public static func shouldFallBackToGitHubRelease(isHomebrew: Bool, result: CheckResult) -> Bool {
        guard isHomebrew else { return false }
        if case .failed = result { return true }
        return false
    }

    /// Which payload format a given source returns, so the parse strategy follows
    /// the URL we actually fetched rather than the install type — the Homebrew
    /// fallback path reads GitHub's release JSON.
    public static func isCaskEndpoint(_ url: URL) -> Bool {
        url.host?.lowercased() == "formulae.brew.sh"
    }

    /// Parse the `version` from Homebrew's cask JSON (formulae.brew.sh).
    /// Returns nil for malformed payloads or `:latest` casks (no comparable
    /// version).
    public static func parseCaskVersion(_ data: Data) -> String? {
        struct Cask: Decodable { let version: String }
        guard let cask = try? JSONDecoder().decode(Cask.self, from: data),
              !cask.version.isEmpty, cask.version != ":latest",
              versionComponents(cask.version).isNumeric else { return nil }
        return cask.version
    }

    /// Check for a newer version and classify the result. Homebrew installs
    /// compare against the cask version so the prompt matches what `brew upgrade`
    /// can install, and fall back to the latest GitHub release when that endpoint
    /// has no record of the cask yet. Everyone else compares against the GitHub
    /// release. Failures are returned as values, never thrown.
    public static func check(
        currentVersion: String = MCConstants.appVersion,
        session: URLSession = .shared,
        isHomebrew: Bool = isHomebrewInstall()
    ) async -> CheckResult {
        let primary = await checkSource(
            updateSourceURL(isHomebrew: isHomebrew),
            currentVersion: currentVersion,
            session: session
        )
        guard shouldFallBackToGitHubRelease(isHomebrew: isHomebrew, result: primary) else {
            return primary
        }
        return await checkSource(
            MCConstants.latestReleaseAPI,
            currentVersion: currentVersion,
            session: session
        )
    }

    private static func checkSource(
        _ sourceURL: URL,
        currentVersion: String,
        session: URLSession
    ) async -> CheckResult {
        guard isExpectedEndpoint(sourceURL) else {
            return .failed(message: L10n.tr("更新源地址无效。", "The update source is not a recognized endpoint.", "Неизвестный источник обновлений."))
        }
        let isCaskSource = isCaskEndpoint(sourceURL)
        var request = URLRequest(url: sourceURL, timeoutInterval: 10)
        request.setValue(
            isCaskSource ? "application/json" : "application/vnd.github+json",
            forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failed(message: L10n.tr(
                    "更新源返回 HTTP \(http.statusCode)。",
                    "The update source returned HTTP \(http.statusCode).",
                    "Источник обновлений вернул HTTP \(http.statusCode)."))
            }
            // `URLSession` follows redirects and this app's Foundation has no
            // per-task redirect hook, so the body may not come from the URL we
            // asked for. Checked here on the response URL, and the payload is
            // then held to its own trust anchors — the release link must be
            // `https://github.com/…` and the version must be numeric — so a
            // foreign body can at worst produce a bogus version string pointing
            // at a GitHub page, never an arbitrary URL.
            guard isExpectedEndpoint(http.url) else {
                return .failed(message: L10n.tr("更新源响应来自未知地址。", "The update response came from an unrecognized host.", "Ответ пришёл с неизвестного адреса."))
            }
            let version: String
            let url: URL
            if isCaskSource {
                guard let caskVersion = parseCaskVersion(data) else {
                    return .failed(message: L10n.tr("Homebrew 返回了无法识别的响应。", "Unexpected response from Homebrew.", "Неожиданный ответ от Homebrew."))
                }
                version = caskVersion
                // Brew installs act via `brew upgrade`, not a download link;
                // the releases page is a sensible fallback URL.
                url = MCConstants.releasesURL
            } else {
                guard let parsed = parseLatestRelease(data) else {
                    return .failed(message: L10n.tr("GitHub 返回了无法识别的响应。", "Unexpected response from GitHub.", "Неожиданный ответ от GitHub."))
                }
                version = parsed.version
                url = parsed.url
            }
            return isNewer(version, than: currentVersion)
                ? .updateAvailable(version: version, url: url)
                : .upToDate
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
