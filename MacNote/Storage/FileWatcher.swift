import Foundation
import CoreServices
import os

/// FSEvents-based directory watcher. Coalesces rapid change events and delivers
/// them on the main queue via the `onChange` closure.
final class FileWatcher {

    // MARK: - State

    private var streamRef: FSEventStreamRef?
    /// Called on the main queue with the list of changed URLs.
    var onChange: (([URL]) -> Void)?

    private let logger = Logger(subsystem: "com.macnote", category: "FileWatcher")

    // MARK: - Start

    func start(watching directory: URL) {
        stop() // Ensure any previous stream is torn down first.

        let paths = [directory.path] as CFArray
        // passRetained increments self's refcount; the release callback balances it on stream teardown.
        // On create failure we must balance manually — so capture the unmanaged ref first.
        let retainedSelf = Unmanaged.passRetained(self)
        var ctx = FSEventStreamContext(
            version: 0,
            info: retainedSelf.toOpaque(),
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<FileWatcher>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes   |
            kFSEventStreamCreateFlagFileEvents   |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileWatcherCallback,
            &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25, // 250 ms latency — coalesces burst saves
            flags
        ) else {
            retainedSelf.release()  // balance passRetained; no stream will call the release callback
            logger.error("Failed to create FSEventStream for \(directory.path)")
            return
        }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        logger.debug("FSEventStream started for \(directory.path)")
    }

    // MARK: - Stop

    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
        logger.debug("FSEventStream stopped")
    }

    // MARK: - Deinit

    deinit { stop() }
}

// MARK: - C callback (free function, must be outside class)

private func fileWatcherCallback(
    _ stream: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

    // eventPaths is a CFArray of CFString paths when kFSEventStreamCreateFlagUseCFTypes is set.
    let pathsCF = unsafeBitCast(eventPaths, to: CFArray.self)
    let count = CFArrayGetCount(pathsCF)
    var urls: [URL] = []
    for i in 0..<count {
        let rawPath = CFArrayGetValueAtIndex(pathsCF, i)
        let pathStr = unsafeBitCast(rawPath, to: CFString.self) as String
        urls.append(URL(fileURLWithPath: pathStr))
    }

    // Already on main queue (we called FSEventStreamSetDispatchQueue with .main).
    watcher.onChange?(urls)
}
