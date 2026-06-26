import Foundation
import ClarcCore
import os

actor PersistenceService {

    private let baseURL: URL
    private let metaStore: SessionMetaStore
    private let cliStore: CLISessionStore
    private let logger = Logger(subsystem: "com.claudework", category: "PersistenceService")

    init(metaStore: SessionMetaStore, cliStore: CLISessionStore) {
        self.baseURL = AppSupport.bundleScopedURL
        self.metaStore = metaStore
        self.cliStore = cliStore
    }

    // MARK: - Projects

    func saveProjects(_ projects: [Project]) throws {
        let url = baseURL.appendingPathComponent("projects.json")
        try encode(projects, to: url)
    }

    func loadProjects() -> [Project] {
        let url = baseURL.appendingPathComponent("projects.json")
        return decode([Project].self, from: url) ?? []
    }

    // MARK: - Sessions

    func saveSession(_ session: ChatSession, persistTitle: Bool = false) async throws {
        switch session.origin {
        case .cliBacked:
            // CLI owns the message log (jsonl). We only persist the Clarc-only
            // sidecar — title/pin/model/effort/permissionMode.
            //
            // Title rule: the sidecar holds *user-renamed* titles only. Auto
            // saves leave it untouched so the listing falls back to the jsonl
            // first-message sniff, matching what the CLI's --resume shows.
            let titleToWrite: String?
            if persistTitle {
                titleToWrite = session.title
            } else {
                titleToWrite = await metaStore.load(sessionId: session.id).title
            }
            await metaStore.save(
                sessionId: session.id,
                meta: SessionMetaStore.Meta(
                    title: titleToWrite,
                    isPinned: session.isPinned,
                    isCompleted: session.isCompleted,
                    model: session.model,
                    effort: session.effort,
                    permissionMode: session.permissionMode,
                    updatedAt: session.updatedAt,
                    contextPercent: session.contextPercent,
                    totalDurationMs: session.totalDurationMs
                )
            )

        case .legacyClarc:
            let dir = baseURL
                .appendingPathComponent("sessions")
                .appendingPathComponent(session.projectId.uuidString)
            try ensureDirectory(dir)
            let url = dir.appendingPathComponent("\(session.id).json")
            try encode(session, to: url)
        }
    }

    /// Updates only the persisted context-window percentage in the sidecar,
    /// merging into the existing meta. Used when the context value arrives
    /// asynchronously (CLI resume) after the main session save.
    func updateContextPercent(sessionId: String, percent: Double) async {
        var meta = await metaStore.load(sessionId: sessionId)
        meta.contextPercent = percent
        await metaStore.save(sessionId: sessionId, meta: meta)
    }

    /// Lightweight load of legacy session list for a project. CLI-backed
    /// summaries are loaded separately by `CLISessionStore.loadSummaries`.
    func loadLegacySessions(for projectId: UUID) -> [ChatSession.Summary] {
        let dir = baseURL
            .appendingPathComponent("sessions")
            .appendingPathComponent(projectId.uuidString)

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ChatSession.Summary? in
                guard var summary = decode(ChatSession.Summary.self, from: url) else { return nil }
                // Files saved before this change may decode as `.legacyClarc`
                // already (default), but be defensive.
                if summary.origin != .legacyClarc {
                    summary = ChatSession.Summary(
                        id: summary.id, projectId: summary.projectId, title: summary.title,
                        createdAt: summary.createdAt, updatedAt: summary.updatedAt,
                        isPinned: summary.isPinned, model: summary.model,
                        effort: summary.effort, permissionMode: summary.permissionMode,
                        origin: .legacyClarc
                    )
                }
                return summary
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Lightweight load of legacy session summaries across all projects.
    func loadAllLegacySessionSummaries() -> [ChatSession.Summary] {
        let sessionsDir = baseURL.appendingPathComponent("sessions")
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var summaries: [ChatSession.Summary] = []
        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            for file in files where file.pathExtension == "json" {
                if let summary = decode(ChatSession.Summary.self, from: file) {
                    summaries.append(summary)
                }
            }
        }

        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSession(projectId: UUID, sessionId: String, origin: SessionOrigin, cwd: String?) async throws {
        switch origin {
        case .cliBacked:
            await metaStore.delete(sessionId: sessionId)
            if let cwd {
                await cliStore.deleteSession(sid: sessionId, cwd: cwd)
            } else {
                logger.warning("Skipping CLI jsonl delete for \(sessionId, privacy: .public): cwd unavailable")
            }
            // Pre-cli-sync builds wrote a Clarc-side json with the same sid. If
            // it survives, the merge in AppState falls back to it after the
            // jsonl is gone and the entry resurrects on the next reload.
            try removeLegacySessionFile(projectId: projectId, sessionId: sessionId)
        case .legacyClarc:
            try removeLegacySessionFile(projectId: projectId, sessionId: sessionId)
        }
    }

    private func removeLegacySessionFile(projectId: UUID, sessionId: String) throws {
        let url = baseURL
            .appendingPathComponent("sessions")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("\(sessionId).json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
        logger.debug("Deleted legacy session \(sessionId, privacy: .public)")
    }

    /// Loads the full message history. Routes by `origin`:
    /// - `.cliBacked` → CLI jsonl
    /// - `.legacyClarc` → Clarc's per-project json
    func loadFullSession(summary: ChatSession.Summary, cwd: String) async -> ChatSession? {
        switch summary.origin {
        case .cliBacked:
            return await cliStore.loadFullSession(
                sid: summary.id,
                cwd: cwd,
                projectId: summary.projectId
            )
        case .legacyClarc:
            return loadLegacySessionSync(projectId: summary.projectId, sessionId: summary.id)
        }
    }

    /// Synchronous load for legacy json sessions. Kept available for the few
    /// MainActor sites that still call it directly.
    nonisolated func legacySessionURL(projectId: UUID, sessionId: String) -> URL {
        baseURL
            .appendingPathComponent("sessions")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("\(sessionId).json")
    }

    nonisolated func loadLegacySessionSync(projectId: UUID, sessionId: String) -> ChatSession? {
        let url = legacySessionURL(projectId: projectId, sessionId: sessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChatSession.self, from: data)
    }

    // MARK: - GitHub User Cache

    func saveGitHubUser(_ user: GitHubUser) throws {
        let url = baseURL.appendingPathComponent("github_user.json")
        try encode(user, to: url)
    }

    func loadGitHubUser() -> GitHubUser? {
        let url = baseURL.appendingPathComponent("github_user.json")
        return decode(GitHubUser.self, from: url)
    }

    // MARK: - Private Helpers

    private func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)

        logger.debug("Saved \(url.lastPathComponent, privacy: .public)")
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            logger.error(
                "Failed to decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            // Move corrupted file to a backup to preserve data
            let backupURL = url.deletingPathExtension()
                .appendingPathExtension("corrupted-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.moveItem(at: url, to: backupURL)
            logger.warning("Moved corrupted file to \(backupURL.lastPathComponent, privacy: .public)")
            return nil
        }
    }
}
