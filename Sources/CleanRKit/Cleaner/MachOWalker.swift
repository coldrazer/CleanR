import Foundation

/// Walks a `.app` bundle's `Contents/` and returns the URLs of every
/// fat (universal) Mach-O file inside. Used as the input to
/// `ThinAppBundleOperation` so that frameworks, XPC services, helper apps,
/// and embedded plug-ins all get thinned — not just `Contents/MacOS/<exec>`.
///
/// Key invariants:
/// - Symlinks are skipped. Frameworks contain `Versions/Current → Versions/A`
///   chains; following them would re-process the same file under two URLs.
/// - Hard links are deduplicated by inode + device. If two URLs point at the
///   same on-disk object, the walker returns only the first one it saw.
/// - Fat-Mach-O detection is via magic-byte read (4 bytes), not by spawning
///   `lipo -info` per file. A typical app has thousands of `Contents/` files;
///   per-file lipo would be hundreds of ms vs. the magic-byte check at <1ms.
public enum MachOWalker {

    public static func fatBinaries(in bundleURL: URL) -> [URL] {
        let contents = bundleURL.appending(path: "Contents")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: contents,
            includingPropertiesForKeys: [
                .isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey,
                .fileSizeKey,
            ],
            options: []
        ) else { return [] }

        var seen: Set<InodeKey> = []
        var results: [URL] = []

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [
                .isSymbolicLinkKey, .isRegularFileKey,
            ]) else { continue }

            // Skip symlinks — frameworks use Versions/Current → Versions/A.
            if values.isSymbolicLink == true { continue }
            // Only consider regular files; directories aren't binaries.
            guard values.isRegularFile == true else { continue }

            // Dedupe by (device, inode). Hard links to the same file would
            // otherwise get thinned twice (second attempt would no-op or fail).
            guard let key = InodeKey(url: url) else { continue }
            if !seen.insert(key).inserted { continue }

            guard isFatMachO(url: url) else { continue }
            results.append(url)
        }

        return results
    }

    /// True if the file's first 4 bytes are one of the fat Mach-O magic
    /// constants. Cheap — opens the file, reads 4 bytes, closes.
    static func isFatMachO(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4
        else { return false }

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        // FAT_MAGIC = 0xCAFEBABE        (big-endian fat 32)
        // FAT_CIGAM = 0xBEBAFECA        (little-endian fat 32)
        // FAT_MAGIC_64 = 0xCAFEBABF     (big-endian fat 64)
        // FAT_CIGAM_64 = 0xBFBAFECA     (little-endian fat 64)
        return magic == 0xCAFE_BABE ||
               magic == 0xBEBA_FECA ||
               magic == 0xCAFE_BABF ||
               magic == 0xBFBA_FECA
    }
}

/// (device, inode) tuple for hard-link detection.
struct InodeKey: Hashable {
    let device: dev_t
    let inode: ino_t

    init?(url: URL) {
        var st = stat()
        let path = url.path(percentEncoded: false)
        guard lstat(path, &st) == 0 else { return nil }
        self.device = st.st_dev
        self.inode = st.st_ino
    }
}
