import CoreServices
import Foundation
import os

/// Watches one or more directories for filesystem changes using FSEventStream
/// with `kFSEventStreamCreateFlagFileEvents`. Push-based: the kernel notifies
/// us when files inside the watched root are created, modified, deleted, or
/// extended (including in-place appends to existing jsonl). FSEventStream's
/// own `latency` window coalesces bursts before the caller's `onChange` fires.
public actor DirectoryWatcher {

    /// Heap-allocated bridge between the C-style FSEventStream callback and
    /// the actor. Retained via `Unmanaged.passRetained` for the duration the
    /// stream is alive — that retain is what the `info` pointer aliases. The
    /// `weak watcher` ref is read on the FSEvents dispatch queue; weak loads
    /// are atomic so `@unchecked Sendable` is safe.
    private final class StreamContext: @unchecked Sendable {
        weak var watcher: DirectoryWatcher?
        let url: URL
        init(watcher: DirectoryWatcher, url: URL) {
            self.watcher = watcher
            self.url = url
        }
    }

    private struct Entry {
        let stream: FSEventStreamRef
        let info: UnsafeMutableRawPointer
        let onChange: @Sendable () -> Void
    }

    private var entries: [URL: Entry] = [:]
    private let queue = DispatchQueue(label: "com.claudework.DirectoryWatcher", qos: .utility)
    private let logger = Logger(subsystem: "com.claudework", category: "DirectoryWatcher")
    /// FSEventStream coalesces events arriving within this window into a single
    /// callback. 1s gives the CLI room to flush a multi-line append in one go
    /// and removes the need for an additional debounce on our side.
    private static let latencySeconds: CFTimeInterval = 1.0

    public init() {}

    /// Begin watching `url`. Re-registering the same URL is a no-op; replacing
    /// the handler requires `unwatch` first. Returns silently if the directory
    /// does not exist (caller can retry later).
    public func watch(url: URL, onChange: @Sendable @escaping () -> Void) {
        let key = url.standardizedFileURL
        if entries[key] != nil { return }

        guard FileManager.default.fileExists(atPath: key.path) else {
            logger.debug("Watch skipped (no such directory) for \(key.path, privacy: .public)")
            return
        }

        let context = StreamContext(watcher: self, url: key)
        let info = Unmanaged.passRetained(context).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, infoPtr, numEvents, _, eventFlags, _ in
            guard let infoPtr else { return }
            let ctx = Unmanaged<StreamContext>.fromOpaque(infoPtr).takeUnretainedValue()
            guard let watcher = ctx.watcher else { return }

            var rootChanged = false
            for i in 0..<numEvents {
                if eventFlags[i] & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
                    rootChanged = true
                    break
                }
            }

            let url = ctx.url
            Task { await watcher.handleEvent(url: url, rootChanged: rootChanged) }
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &streamContext,
            [key.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latencySeconds,
            flags
        ) else {
            Unmanaged<StreamContext>.fromOpaque(info).release()
            logger.error("FSEventStreamCreate failed for \(key.path, privacy: .public)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)

        entries[key] = Entry(stream: stream, info: info, onChange: onChange)
        logger.debug("Watching \(key.path, privacy: .public)")
    }

    public func unwatch(url: URL) {
        let key = url.standardizedFileURL
        guard let entry = entries.removeValue(forKey: key) else { return }
        FSEventStreamStop(entry.stream)
        FSEventStreamInvalidate(entry.stream)
        FSEventStreamRelease(entry.stream)
        Unmanaged<StreamContext>.fromOpaque(entry.info).release()
    }

    public func unwatchAll() {
        for key in Array(entries.keys) {
            unwatch(url: key)
        }
    }

    private func handleEvent(url: URL, rootChanged: Bool) {
        guard let onChange = entries[url]?.onChange else { return }

        // Watched directory itself was deleted or renamed: tear down and notify
        // once so the caller can re-resolve and re-register.
        if rootChanged {
            unwatch(url: url)
        }
        onChange()
    }
}
