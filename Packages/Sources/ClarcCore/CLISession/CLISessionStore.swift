import Foundation
import os

/// Reads CLI-owned session jsonl files under `~/.claude/projects/{enc(cwd)}/`.
/// All disk I/O is done off the main actor; the public API returns Sendable
/// values so callers can hop back to MainActor as needed.
public actor CLISessionStore {

    private let metaStore: SessionMetaStore
    private let logger = Logger(subsystem: "com.claudework", category: "CLISessionStore")

    private static let titleSniffLineLimit = 400
    private static let cwdProbeLineLimit = 5
    private static let cwdIndexTTL: TimeInterval = 60
    private static let lastTimestampTailBytes: Int = 16 * 1024

    /// In-memory map: standardized cwd → CLI projects sub-directory URL. Built
    /// from real jsonl content (not from forward encoding), so it survives the
    /// slash/dot collision in the directory-name encoding.
    private var cwdIndex: [String: URL] = [:]
    private var cwdIndexBuiltAt: Date?

    /// Per-sid cache of jsonl sniff results, keyed by sid and invalidated by
    /// file mtime. Avoids re-reading the first ~400 lines of every jsonl every
    /// time the FS watcher fires (which happens on every assistant turn since
    /// our own CLI subprocess is what's writing).
    private struct SniffCacheEntry {
        let mtime: Date
        let result: SniffResult
    }
    private var sniffCache: [String: SniffCacheEntry] = [:]

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = Self.dateStrategy
        return d
    }()

    /// CLI emits ISO8601 timestamps with fractional seconds (e.g. `2026-04-28T04:55:53.779Z`).
    /// Foundation's `.iso8601` strategy doesn't accept fractional seconds, so we
    /// install a custom strategy that tries with-then-without.
    private static let dateStrategy: JSONDecoder.DateDecodingStrategy = {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = withFractional.date(from: s) { return d }
            if let d = plain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
        }
    }()

    public init(metaStore: SessionMetaStore) {
        self.metaStore = metaStore
    }

    // MARK: - Discovery

    /// Resolve the on-disk projects directory for a Clarc-known cwd. Prefers
    /// the cwd-index (built by reading jsonl content, so it sees through the
    /// lossy slash/dot encoding) and falls back to forward encoding when no
    /// index entry exists yet.
    public func directory(forCwd cwd: String) async -> URL {
        await ensureCwdIndex()
        if let url = cwdIndex[cwd.standardizedCwd()] { return url }
        return CLIProjectsDirectory.directory(forCwd: cwd)
    }

    public func sessionFiles(forCwd cwd: String) async -> [URL] {
        let dir = await directory(forCwd: cwd)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "jsonl" }
            .sorted { (mtime(of: $0) ?? .distantPast) > (mtime(of: $1) ?? .distantPast) }
    }

    private func ensureCwdIndex() async {
        if let builtAt = cwdIndexBuiltAt,
           Date().timeIntervalSince(builtAt) < Self.cwdIndexTTL {
            return
        }
        let projectsRoot = CLIProjectsDirectory.url
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            cwdIndex = [:]
            cwdIndexBuiltAt = Date()
            return
        }

        let candidates = dirs.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        let pairs: [(cwd: String, url: URL)] = await withTaskGroup(of: (String, URL)?.self) { group in
            for dir in candidates {
                group.addTask { [self] in
                    guard let cwd = await self.sniffCwd(in: dir) else { return nil }
                    return (cwd.standardizedCwd(), dir)
                }
            }
            var results: [(String, URL)] = []
            for await pair in group {
                if let pair { results.append(pair) }
            }
            return results
        }

        cwdIndex = Dictionary(pairs.map { ($0.cwd, $0.url) }, uniquingKeysWith: { first, _ in first })
        cwdIndexBuiltAt = Date()
        logger.debug("Built CLI cwd index: \(self.cwdIndex.count, privacy: .public) entries")
    }

    private struct CwdProbe: Decodable { let cwd: String? }

    /// Read the most recently touched jsonl in a directory and pluck out the
    /// `cwd` field. Only the first ~5 valid lines are inspected — user/
    /// assistant/system lines all carry cwd, but the very first line is often
    /// a `file-history-snapshot` that doesn't.
    private func sniffCwd(in directory: URL) async -> String? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }
        let sorted = urls
            .filter { $0.pathExtension == "jsonl" }
            .sorted { (mtime(of: $0) ?? .distantPast) > (mtime(of: $1) ?? .distantPast) }

        for url in sorted {
            var seen = 0
            do {
                for try await rawLine in url.lines {
                    if seen >= Self.cwdProbeLineLimit { break }
                    seen += 1
                    guard !rawLine.isEmpty,
                          let data = rawLine.data(using: .utf8),
                          let probe = try? decoder.decode(CwdProbe.self, from: data),
                          let cwd = probe.cwd, !cwd.isEmpty else { continue }
                    return cwd
                }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Summaries

    /// Fast, sniff-only summary list for a project's CLI sessions. Pass
    /// `metaCache` if you've already loaded the sidecar map for this batch
    /// (avoids N × directory scans when merging summaries across projects).
    public func loadSummaries(
        cwd: String,
        projectId: UUID,
        metaCache: [String: SessionMetaStore.Meta]? = nil
    ) async -> [ChatSession.Summary] {
        let files = await sessionFiles(forCwd: cwd)
        guard !files.isEmpty else { return [] }
        let metaByID: [String: SessionMetaStore.Meta]
        if let metaCache {
            metaByID = metaCache
        } else {
            metaByID = await metaStore.loadAll()
        }

        var summaries: [ChatSession.Summary] = []
        summaries.reserveCapacity(files.count)
        let liveSids = Set(files.map { $0.deletingPathExtension().lastPathComponent })
        sniffCache = sniffCache.filter { liveSids.contains($0.key) }

        for url in files {
            let sid = url.deletingPathExtension().lastPathComponent
            let meta = metaByID[sid] ?? SessionMetaStore.Meta()
            let mtimeDate = mtime(of: url) ?? Date()
            var snippet: SniffResult
            if let cached = sniffCache[sid], cached.mtime == mtimeDate {
                snippet = cached.result
            } else {
                snippet = await sniffSummary(url: url)
                snippet.lastTimestamp = lastTimestamp(in: url)
                sniffCache[sid] = SniffCacheEntry(mtime: mtimeDate, result: snippet)
            }
            let title: String = {
                if let t = meta.title, !t.isEmpty { return t }
                if let t = snippet.latestAITitle, !t.isEmpty { return shortTitle(from: t) }
                if let t = snippet.firstUserText, !t.isEmpty { return shortTitle(from: t) }
                return ChatSession.defaultTitle
            }()
            summaries.append(ChatSession.Summary(
                id: sid,
                projectId: projectId,
                title: title,
                createdAt: snippet.firstTimestamp ?? mtimeDate,
                updatedAt: snippet.lastTimestamp ?? mtimeDate,
                isPinned: meta.isPinned,
                model: meta.model,
                effort: meta.effort,
                permissionMode: meta.permissionMode,
                origin: .cliBacked
            ))
        }
        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Lets a caller pre-load the sidecar map once for a batch of `loadSummaries`
    /// calls (e.g. across all projects on app start).
    public func loadMetaCache() async -> [String: SessionMetaStore.Meta] {
        await metaStore.loadAll()
    }

    private struct SniffResult {
        var firstUserText: String?
        var firstTimestamp: Date?
        var latestAITitle: String?
        var lastTimestamp: Date?
    }

    /// Schema-light decoder for the CLI's `ai-title` jsonl line. Sidesteps
    /// `CLISessionLine` so the renderer doesn't have to grow a case it never
    /// shows. `timestamp` is also decoded here to serve `lastTimestamp(in:)`.
    private struct AITitleLine: Decodable {
        let type: String?
        let aiTitle: String?
        let timestamp: Date?
    }

    private func sniffSummary(url: URL) async -> SniffResult {
        var result = SniffResult()
        var seen = 0
        do {
            for try await rawLine in url.lines {
                if seen >= Self.titleSniffLineLimit { break }
                seen += 1
                guard !rawLine.isEmpty, let data = rawLine.data(using: .utf8) else { continue }

                // ai-title sniff: cheap substring guard avoids paying the JSON
                // decode cost on every line. Multiple ai-title lines may appear
                // as the CLI rewrites the title — keep the most recent.
                if rawLine.contains("\"type\":\"ai-title\""),
                   let title = try? decoder.decode(AITitleLine.self, from: data).aiTitle,
                   !title.isEmpty {
                    result.latestAITitle = title
                    continue
                }

                guard let decoded = try? decoder.decode(CLISessionLine.self, from: data) else { continue }

                switch decoded {
                case .user(let user):
                    if result.firstTimestamp == nil { result.firstTimestamp = user.timestamp }
                    if user.isMeta || user.isSidechain { continue }
                    if result.firstUserText == nil,
                       let text = firstHumanText(from: user.message.content) {
                        result.firstUserText = text
                    }
                case .assistant(let assistant):
                    if result.firstTimestamp == nil { result.firstTimestamp = assistant.timestamp }
                case .skip:
                    continue
                }
            }
        } catch {
            logger.debug("sniffSummary error for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return result
    }

    private func firstHumanText(from content: UserContent) -> String? {
        switch content {
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if CLIMetaEnvelope.isEnvelope(trimmed) { return nil }
            return trimmed
        case .parts(let parts):
            for part in parts {
                if case .text(let t) = part, !t.isEmpty { return t }
            }
            return nil
        }
    }

    /// Read the last ~16KB of a jsonl and return the largest `timestamp` field
    /// found. Survives Clarc-side rewrites (PickerExposer, LegacyMigrator) that
    /// would otherwise bump file mtime to "now". Returns nil for files whose
    /// tail contains no timestamped lines (e.g. only metadata) — caller falls
    /// back to mtime.
    private func lastTimestamp(in url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let endOffset: UInt64
        do {
            endOffset = try handle.seekToEnd()
        } catch {
            return nil
        }
        guard endOffset > 0 else { return nil }
        let window = UInt64(Self.lastTimestampTailBytes)
        let startOffset = endOffset > window ? endOffset - window : 0
        do {
            try handle.seek(toOffset: startOffset)
        } catch {
            return nil
        }
        guard let data = try? handle.readToEnd(),
              var text = String(data: data, encoding: .utf8) else { return nil }
        if startOffset > 0, let nl = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: nl)...])
        }
        var maxDate: Date?
        for sub in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard sub.contains("\"timestamp\":\"") else { continue }
            let lineData = Data(sub.utf8)
            guard let ts = (try? decoder.decode(AITitleLine.self, from: lineData))?.timestamp
            else { continue }
            maxDate = maxDate.map { max($0, ts) } ?? ts
        }
        return maxDate
    }

    private func shortTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
        return String(firstLine.prefix(80))
    }

    // MARK: - Full session load

    /// Stream-parse the full jsonl into a `ChatSession`. Memory footprint is
    /// roughly proportional to rendered content (thinking blocks dropped at
    /// decode time). `projectId` is supplied by the caller because the session
    /// jsonl itself doesn't carry the Clarc project UUID.
    public func loadFullSession(
        sid: String,
        cwd: String,
        projectId: UUID
    ) async -> ChatSession? {
        let url = await jsonlURL(sid: sid, cwd: cwd)

        var lines: [CLISessionLine] = []
        var firstTimestamp: Date?
        var latestAITitle: String?

        // Bulk-read the jsonl in one shot. The earlier `for try await rawLine
        // in url.lines` walked the file via AsyncBytes which produced a
        // userland byte-by-byte pipeline — fine for streaming consumption,
        // but ~order-of-magnitude slower than mmap+split for a finished
        // session that fits in memory. The session-switch click waits on this
        // call, so the difference is the gap between "messages appear
        // instantly" and "messages appear noticeably late".
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            logger.debug("loadFullSession read error for \(sid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // Tolerate an in-flight final write (jsonl is append-only) — the trailing
        // partial line fails JSON decode and is silently skipped, satisfying S1.
        let content = String(data: data, encoding: .utf8) ?? ""
        for sub in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let rawLine = String(sub)
            guard let lineData = rawLine.data(using: .utf8) else { continue }

            if rawLine.contains("\"type\":\"ai-title\""),
               let title = try? decoder.decode(AITitleLine.self, from: lineData).aiTitle,
               !title.isEmpty {
                latestAITitle = title
                continue
            }

            guard let decoded = try? decoder.decode(CLISessionLine.self, from: lineData) else { continue }
            if firstTimestamp == nil {
                switch decoded {
                case .user(let u): firstTimestamp = u.timestamp
                case .assistant(let a): firstTimestamp = a.timestamp
                case .skip: break
                }
            }
            lines.append(decoded)
        }
        guard !lines.isEmpty else { return nil }

        let messages = CLILineToBlocksMapper.map(lines: lines)
        let mtimeDate = mtime(of: url) ?? Date()
        let meta = await metaStore.load(sessionId: sid)

        let title: String = {
            if let t = meta.title, !t.isEmpty { return t }
            if let t = latestAITitle, !t.isEmpty { return shortTitle(from: t) }
            if let firstUser = messages.first(where: { $0.role == .user })?.content,
               !firstUser.isEmpty {
                return shortTitle(from: firstUser)
            }
            return "New Session"
        }()

        return ChatSession(
            id: sid,
            projectId: projectId,
            title: title,
            messages: messages,
            createdAt: firstTimestamp ?? mtimeDate,
            updatedAt: mtimeDate,
            isPinned: meta.isPinned,
            model: meta.model,
            effort: meta.effort,
            permissionMode: meta.permissionMode,
            origin: .cliBacked
        )
    }

    // MARK: - Picker exposure

    /// Rewrite the session's jsonl so it appears in the `claude --resume` picker.
    /// Delegates to ``PickerExposer``; uses the cwd index for accurate URL resolution.
    public func exposeToPicker(sid: String, cwd: String) async {
        await PickerExposer.normalize(jsonlAt: await jsonlURL(sid: sid, cwd: cwd))
    }

    // MARK: - Deletion

    /// Remove the CLI-owned jsonl for a session.
    public func deleteSession(sid: String, cwd: String) async {
        let url = await jsonlURL(sid: sid, cwd: cwd)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
            logger.debug("Deleted CLI session jsonl \(sid, privacy: .public)")
        } catch {
            logger.error("Failed to delete CLI session jsonl \(sid, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func jsonlURL(sid: String, cwd: String) async -> URL {
        await directory(forCwd: cwd).appendingPathComponent("\(sid).jsonl")
    }

    // MARK: - External activity detection (S2)

    /// True if the session's jsonl was modified within the given window — a
    /// loose proxy for "another claude process is writing to it right now".
    /// nonisolated for fast `send()`-time checks. Forward-encoding only; the
    /// cwd index is reachable but would require an actor hop, and this is a
    /// best-effort warning anyway.
    public nonisolated func detectExternalActivity(
        sid: String,
        cwd: String,
        withinSeconds window: TimeInterval
    ) -> Bool {
        let url = CLIProjectsDirectory.directory(forCwd: cwd)
            .appendingPathComponent("\(sid).jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(mtime) < window
    }

    // MARK: - Helpers

    private nonisolated func mtime(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

/// Common envelope detection for CLI-internal text wrapped in `<...>` tags
/// (system reminders, slash-command echoes, local-command caveats, background
/// task notifications, custom slash-command expansions). Used by both jsonl
/// summary sniffing and full mapping.
public enum CLIMetaEnvelope {
    public static func isEnvelope(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("<local-command-caveat>")
            || trimmed.hasPrefix("<local-command-stdout>")
            || trimmed.hasPrefix("<command-name>")
            || trimmed.hasPrefix("<command-message>")
            || trimmed.hasPrefix("<command-args>")
            || trimmed.hasPrefix("<system-reminder>")
            || trimmed.hasPrefix("<task-notification>") {
            return true
        }
        // Custom slash-command expansions: CLI wraps a user-defined command's
        // template in <{name}-command>...</{name}-command> when the user runs
        // it. The tag name varies per command, so pattern-match on the suffix.
        if trimmed.hasPrefix("<"),
           let endIdx = trimmed.firstIndex(of: ">") {
            let tag = trimmed[trimmed.index(after: trimmed.startIndex)..<endIdx]
            if !tag.contains(" ") && tag.hasSuffix("-command") {
                return true
            }
        }
        return false
    }
}
