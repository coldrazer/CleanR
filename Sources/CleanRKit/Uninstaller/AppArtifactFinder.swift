//
//  AppArtifactFinder.swift
//  CleanRKit
//
//  Heuristic file-discovery engine that locates all filesystem artifacts
//  belonging to a given macOS application. Ported from Apex Studio_2's
//  AppPathFinder (MIT) and merged with Apex Studio_1's word-boundary filename
//  matcher (BSD) for deletion safety: name tokens must match as whole words,
//  while bundle-id tokens keep normalized substring matching.
//

import Foundation

public final class AppArtifactFinder: @unchecked Sendable {

    public enum Sensitivity: Sendable {
        case strict    // Exact bundle ID + exact name match only
        case enhanced  // + partial matching, bundle components, stripped version
        case deep      // + company name, entitlements, team ID
    }

    // MARK: - Properties

    private let app: AppInfo
    private let locations: UninstallerLocations
    private let sensitivity: Sensitivity
    private var collectionSet: Set<URL> = []
    private let collectionQueue = DispatchQueue(label: "com.cleanr.pathfinder.collection")

    // Pre-computed identifiers (computed once in init, used in the hot loop).
    private let normalizedBundleID: String
    private let bundleLastTwo: String
    private let baseBundleID: String?
    private let namePatterns: Set<String>
    private let companyName: String?
    private let normalizedTeamID: String?
    private let normalizedEntitlements: [String]

    // MARK: - Initialization

    public init(
        app: AppInfo,
        entitlements: [String]? = nil,
        teamIdentifier: String? = nil,
        sensitivity: Sensitivity = .enhanced
    ) {
        self.app = app
        self.locations = UninstallerLocations()
        self.sensitivity = sensitivity

        self.normalizedBundleID = app.bundleIdentifier.normalizedForMatching()
        self.bundleLastTwo = app.bundleIdentifier.bundleLastTwoComponents
        self.baseBundleID = app.bundleIdentifier.baseBundleIdentifier?.normalizedForMatching()

        self.namePatterns = Self.makeNamePatterns(for: app)

        self.companyName = app.bundleIdentifier.bundleCompanyName
        self.normalizedTeamID = teamIdentifier?.normalizedForMatching()
        self.normalizedEntitlements = (entitlements ?? []).compactMap { e in
            let n = e.normalizedForMatching()
            return n.isEmpty ? nil : n
        }
    }

    /// Name tokens matched as whole words against the raw filename. Includes
    /// the display name, the .app directory name, letters-only form, and
    /// version-stripped form. Short/generic tokens are dropped.
    private static func makeNamePatterns(for app: AppInfo) -> Set<String> {
        var patterns = Set<String>()
        let dirName = app.path.deletingPathExtension().lastPathComponent

        func add(_ s: String) {
            let t = s.lowercased()
            if t.count >= 3 && t != "app" { patterns.insert(t) }
        }

        add(app.name)
        add(dirName)
        add(app.name.lettersOnly)
        add(dirName.lettersOnly)
        add(app.name.strippingTrailingVersion())
        add(dirName.strippingTrailingVersion())

        return patterns
    }

    // MARK: - Public API

    /// Find all files related to this app synchronously.
    public func findPaths() -> Set<URL> {
        collectionSet.insert(app.path)

        for location in locations.appSearch.paths {
            let isLibRoot = isLibraryDirectory(location)
            let maxDepth = isLibRoot ? 2 : 1
            processLocation(location, currentDepth: 0, maxDepth: maxDepth, isLibraryRootSearch: isLibRoot)
        }

        collectionSet.formUnion(discoverContainers())
        applyConditions()

        return filterSubpaths(collectionSet)
    }

    // MARK: - Location Processing

    private func processLocation(_ location: String, currentDepth: Int, maxDepth: Int, isLibraryRootSearch: Bool) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: location) else { return }

        var localResults: [URL] = []
        var subdirs: [URL] = []

        for item in contents {
            let itemURL = URL(fileURLWithPath: location).appendingPathComponent(item)
            let normalizedName: String
            if itemURL.hasDirectoryPath || itemURL.pathExtension.isEmpty {
                normalizedName = item.normalizedForMatching()
            } else {
                normalizedName = (item as NSString).deletingPathExtension.normalizedForMatching()
            }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { continue }

            if shouldSkipItem(normalizedName, at: itemURL) { continue }

            if matchesApp(normalizedName: normalizedName, rawName: item) {
                let itemToAdd: URL
                if isLibraryRootSearch && currentDepth == 2 {
                    let parent = itemURL.deletingLastPathComponent()
                    let parentName = parent.lastPathComponent
                    itemToAdd = UninstallerLocations.standardLibrarySubdirectories.contains(parentName)
                        ? itemURL : parent
                } else {
                    itemToAdd = itemURL
                }
                localResults.append(itemToAdd)
            }

            if isDir.boolValue && currentDepth < maxDepth {
                if isLibraryRootSearch && currentDepth == 0 {
                    if !skipDeepSearch.contains(itemURL.lastPathComponent) {
                        subdirs.append(itemURL)
                    }
                } else {
                    subdirs.append(itemURL)
                }
            }
        }

        collectionQueue.sync { collectionSet.formUnion(localResults) }

        for subdir in subdirs {
            processLocation(subdir.path, currentDepth: currentDepth + 1, maxDepth: maxDepth, isLibraryRootSearch: isLibraryRootSearch)
        }
    }

    // MARK: - Matching Engine

    /// Anchored check for whether the app's bundle ID belongs to the family
    /// identified by `conditionBundleID` (exact, ".child", or "parent.").
    private func bundleIDMatchesCondition(_ conditionBundleID: String) -> Bool {
        guard !conditionBundleID.isEmpty else { return false }
        if normalizedBundleID == conditionBundleID { return true }
        if normalizedBundleID.hasPrefix(conditionBundleID + ".") { return true }
        if normalizedBundleID.hasSuffix("." + conditionBundleID) { return true }
        return false
    }

    /// Multi-level heuristic matcher. Bundle-id tokens use normalized substring
    /// matching; name tokens use whole-word matching against the raw filename
    /// (Apex Studio_1's precision) to avoid substring false positives.
    private func matchesApp(normalizedName: String, rawName: String) -> Bool {
        // Per-app condition overrides take priority.
        for condition in appConditions {
            guard bundleIDMatchesCondition(condition.bundleID) else { continue }
            if condition.excludeTerms.contains(where: { normalizedName.contains($0) }) { return false }
            if condition.includeTerms.contains(where: { normalizedName.contains($0) }) { return true }
        }

        // Entitlement-based matching.
        for entitlement in normalizedEntitlements {
            let match = sensitivity == .strict
                ? normalizedName == entitlement
                : normalizedName.contains(entitlement)
            if match { return true }
        }

        // Bundle-id levels (normalized substring).
        if normalizedBundleID.count >= 5 && normalizedName.contains(normalizedBundleID) { return true }

        // Name levels (whole-word against the raw filename).
        if namePatterns.contains(where: { containsWord($0, in: rawName) }) { return true }

        if sensitivity != .strict {
            if bundleLastTwo.count >= 5, normalizedName.contains(bundleLastTwo) { return true }
            if let base = baseBundleID, base.count >= 5, normalizedName.contains(base) { return true }
        }

        if sensitivity == .deep {
            if let company = companyName, company.count >= 5, containsWord(company, in: rawName) { return true }
            if let teamID = normalizedTeamID, teamID.count >= 5, containsWord(teamID, in: rawName) { return true }
        }

        return false
    }

    // MARK: - Word-boundary matching (from Apex Studio_1)

    /// Whole-word, case-insensitive match: both ends of the occurrence must sit
    /// on a word boundary (edge, separator, camel-case step, or letter/digit step).
    private func containsWord(_ pattern: String, in fileName: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        var searchStart = fileName.startIndex
        while let range = fileName.range(of: pattern, options: .caseInsensitive,
                                         range: searchStart..<fileName.endIndex) {
            if isBoundary(in: fileName, at: range.lowerBound)
                && isBoundary(in: fileName, at: range.upperBound) {
                return true
            }
            searchStart = fileName.index(after: range.lowerBound)
        }
        return false
    }

    private func isBoundary(in string: String, at index: String.Index) -> Bool {
        guard index > string.startIndex, index < string.endIndex else { return true }
        let before = string[string.index(before: index)]
        let after = string[index]
        func isWordCharacter(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        guard isWordCharacter(before), isWordCharacter(after) else { return true }
        if before.isLowercase && after.isUppercase { return true }
        return before.isNumber != after.isNumber
    }

    // MARK: - Skip Logic

    private func shouldSkipItem(_ normalizedName: String, at url: URL) -> Bool {
        if collectionQueue.sync(execute: { collectionSet.contains(url) }) { return true }

        for skip in skipConditions {
            for path in skip.skipPaths {
                if url.path.hasPrefix(path) { return true }
            }
            if skip.skipPrefixes.contains(where: { normalizedName.hasPrefix($0) }) {
                if !skip.allowPrefixes.contains(where: { normalizedName.hasPrefix($0) }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Container Discovery

    /// Discovers sandboxed app containers by UUID (metadata plist) and by name.
    private func discoverContainers() -> [URL] {
        var containers: [URL] = []
        guard let containersPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Containers") else { return containers }
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: containersPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return containers }

        for dir in dirs {
            let dirName = dir.lastPathComponent
            if dirName.count == 36 && dirName.contains("-") {
                let metaPlist = dir.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
                if let meta = NSDictionary(contentsOf: metaPlist),
                   let bundleID = meta["MCMMetadataIdentifier"] as? String,
                   bundleID == app.bundleIdentifier {
                    containers.append(dir)
                }
            }
            if normalizedBundleID.count >= 5, dirName.normalizedForMatching() == normalizedBundleID {
                containers.append(dir)
            }
        }
        return containers
    }

    // MARK: - Condition Application

    private func applyConditions() {
        for condition in appConditions {
            guard bundleIDMatchesCondition(condition.bundleID) else { continue }
            if let paths = condition.forceIncludePaths {
                for path in paths where FileManager.default.fileExists(atPath: path.path) {
                    collectionSet.insert(path)
                }
            }
            if let paths = condition.forceExcludePaths {
                for path in paths { collectionSet.remove(path) }
            }
        }
    }

    // MARK: - Helpers

    private func isLibraryDirectory(_ location: String) -> Bool {
        location == "\(MCConstants.home.path)/Library" || location == "/Library"
    }

    /// Removes child paths when a parent is already present; drops lone Trash results.
    private func filterSubpaths(_ urls: Set<URL>) -> Set<URL> {
        let sorted = urls.map { $0.standardizedFileURL }.sorted { $0.path < $1.path }
        var filtered: [URL] = []
        for url in sorted {
            filtered.removeAll { $0.path.hasPrefix(url.path + "/") }
            if !filtered.contains(where: { url.path.hasPrefix($0.path + "/") }) {
                filtered.append(url)
            }
        }
        if filtered.count == 1, let first = filtered.first, first.path.contains(".Trash") {
            return []
        }
        return Set(filtered)
    }
}
