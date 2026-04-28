import Foundation
import ClarcCore
import os

actor PersistenceService {

    private let baseURL: URL
    private let metaStore: SessionMetaStore
    private let cliStore: CLISessionStore
    private let logger = Logger(subsystem: "com.claudework", category: "PersistenceService")

    init(metaStore: SessionMetaStore, cliStore: CLISessionStore) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.baseURL = appSupport.appendingPathComponent("Clarc")
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

    func saveSession(_ session: ChatSession) async throws {
        switch session.origin {
        case .cliBacked:
            // CLI owns the message log (jsonl). We only persist the Clarc-only
            // sidecar — title/pin/model/effort/permissionMode.
            await metaStore.save(
                sessionId: session.id,
                meta: SessionMetaStore.Meta(
                    title: session.title,
                    isPinned: session.isPinned,
                    model: session.model,
                    effort: session.effort,
                    permissionMode: session.permissionMode,
                    updatedAt: session.updatedAt
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

    func deleteSession(projectId: UUID, sessionId: String, origin: SessionOrigin) async throws {
        switch origin {
        case .cliBacked:
            // Don't delete the CLI's jsonl — the user may still want it from
            // the terminal. Just clear our sidecar.
            await metaStore.delete(sessionId: sessionId)
        case .legacyClarc:
            let url = baseURL
                .appendingPathComponent("sessions")
                .appendingPathComponent(projectId.uuidString)
                .appendingPathComponent("\(sessionId).json")
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
                logger.debug("Deleted legacy session \(sessionId, privacy: .public)")
            }
        }
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
    nonisolated func loadLegacySessionSync(projectId: UUID, sessionId: String) -> ChatSession? {
        let url = baseURL
            .appendingPathComponent("sessions")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("\(sessionId).json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
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
