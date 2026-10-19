import Foundation
import CleanRKit

public final class FSEventMonitor: @unchecked Sendable {
    public struct FSChange: Sendable {
        public let path: String
        public let flags: FSEventStreamEventFlags
        public let eventID: UInt64

        public var isCreated: Bool { flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 }
        public var isRemoved: Bool { flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 }
        public var isModified: Bool { flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 }
        public var isRenamed: Bool { flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 }
        public var isDirectory: Bool { flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 }
        public var mustRescanDir: Bool { flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
    }

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.cleanr.fsevents")
    var changeHandler: (([FSChange]) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public var currentEventID: UInt64 {
        FSEventsGetCurrentEventId()
    }

    // MARK: - Start monitoring (live)

    public func startMonitoring(paths: [String], since: UInt64 = FSEventStreamEventId(kFSEventStreamEventIdSinceNow), handler: @escaping ([FSChange]) -> Void) {
        stop()
        changeHandler = handler

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let cfPaths = paths as CFArray

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventCallback,
            &context,
            cfPaths,
            since,
            0.5, // latency: coalesce events within 500ms
            UInt32(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    // MARK: - Get changes since event ID (for incremental scanning)

    public func getChangesSince(eventID: UInt64, paths: [String]) -> [FSChange] {
        let semaphore = DispatchSemaphore(value: 0)

        var context = FSEventStreamContext()
        let box = ChangesBox()
        context.info = Unmanaged.passUnretained(box).toOpaque()

        let cfPaths = paths as CFArray

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            historicalCallback,
            &context,
            cfPaths,
            eventID,
            0,
            UInt32(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes
            )
        ) else { return [] }
        box.stream = stream

        let historyQueue = DispatchQueue(label: "com.cleanr.fshistory")
        FSEventStreamSetDispatchQueue(stream, historyQueue)
        FSEventStreamStart(stream)

        // Give it a moment to replay events then stop. The stream travels
        // through `box` rather than being captured directly:
        // `FSEventStreamRef` is a non-Sendable opaque pointer and the closing
        // over a mutable `collected` var would be a genuine data race against
        // the callback still appending on this queue.
        historyQueue.asyncAfter(deadline: .now() + 1.0) {
            if let stream = box.stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                box.stream = nil
            }
            semaphore.signal()
        }

        semaphore.wait()
        return box.changes
    }

    // MARK: - Compute invalidated paths

    public func invalidatedPaths(changes: [FSChange]) -> Set<String> {
        var paths = Set<String>()
        for change in changes {
            if change.mustRescanDir {
                paths.insert(change.path)
            } else if change.isCreated || change.isRemoved || change.isModified || change.isRenamed {
                // Invalidate the parent directory
                let url = URL(filePath: change.path)
                paths.insert(url.deletingLastPathComponent().path(percentEncoded: false))
            }
        }
        return paths
    }

    // MARK: - Stop

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
}

// Box to collect changes from the historical callback, and to carry the
// stream reference into the closing block without capturing a non-Sendable
// opaque pointer. Only ever touched on the stream's own serial queue.
private final class ChangesBox: @unchecked Sendable {
    var changes: [FSEventMonitor.FSChange] = []
    var stream: FSEventStreamRef?
}

// Live monitoring callback
private func fsEventCallback(
    stream: ConstFSEventStreamRef,
    clientInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIDs: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let monitor = Unmanaged<FSEventMonitor>.fromOpaque(clientInfo).takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

    var changes: [FSEventMonitor.FSChange] = []
    for i in 0..<numEvents {
        changes.append(FSEventMonitor.FSChange(
            path: paths[i],
            flags: eventFlags[i],
            eventID: eventIDs[i]
        ))
    }

    monitor.changeHandler?(changes)
}

// Historical replay callback
private func historicalCallback(
    stream: ConstFSEventStreamRef,
    clientInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIDs: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let box = Unmanaged<ChangesBox>.fromOpaque(clientInfo).takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

    for i in 0..<numEvents {
        box.changes.append(FSEventMonitor.FSChange(
            path: paths[i],
            flags: eventFlags[i],
            eventID: eventIDs[i]
        ))
    }
}
