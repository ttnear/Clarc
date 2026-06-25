import Foundation
import os

/// Sidecar persistence for the Clarc-only fields that don't live in the CLI's
/// jsonl: title, isPinned, model, effort, permissionMode. One file per session
/// id at `~/Library/Application Support/Clarc/session-meta/{sid}.json`.
public actor SessionMetaStore {

    public struct Meta: Codable, Sendable {
        public var title: String?
        public var isPinned: Bool
        public var isCompleted: Bool
        public var model: String?
        public var effort: String?
        public var permissionMode: PermissionMode?
        public var updatedAt: Date?

        public init(
            title: String? = nil,
            isPinned: Bool = false,
            isCompleted: Bool = false,
            model: String? = nil,
            effort: String? = nil,
            permissionMode: PermissionMode? = nil,
            updatedAt: Date? = nil
        ) {
            self.title = title
            self.isPinned = isPinned
            self.isCompleted = isCompleted
            self.model = model
            self.effort = effort
            self.permissionMode = permissionMode
            self.updatedAt = updatedAt
        }

        private enum CodingKeys: String, CodingKey {
            case title, isPinned, isCompleted, model, effort, permissionMode, updatedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
            isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
            model = try container.decodeIfPresent(String.self, forKey: .model)
            effort = try container.decodeIfPresent(String.self, forKey: .effort)
            permissionMode = try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode)
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }

    private let baseURL: URL
    private let logger = Logger(subsystem: "com.claudework", category: "SessionMetaStore")

    /// In-memory cache. The sidecar directory is owned exclusively by Clarc
    /// (CLI doesn't touch it), so the cache is authoritative once populated.
    private var cache: [String: Meta] = [:]

    public init() {
        self.baseURL = AppSupport.bundleScopedURL.appendingPathComponent("session-meta", isDirectory: true)
    }

    public func load(sessionId: String) -> Meta {
        if let cached = cache[sessionId] { return cached }
        let url = fileURL(for: sessionId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            let empty = Meta()
            cache[sessionId] = empty
            return empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = (try? decoder.decode(Meta.self, from: data)) ?? Meta()
        cache[sessionId] = meta
        return meta
    }

    public func save(sessionId: String, meta: Meta) {
        cache[sessionId] = meta
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !(fm.fileExists(atPath: baseURL.path, isDirectory: &isDir) && isDir.boolValue) {
            try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
        let url = fileURL(for: sessionId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(meta)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save session meta \(sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public func delete(sessionId: String) {
        cache.removeValue(forKey: sessionId)
        let url = fileURL(for: sessionId)
        try? FileManager.default.removeItem(at: url)
    }

    public func loadAll() -> [String: Meta] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [String: Meta] = [:]
        for file in files where file.pathExtension == "json" {
            let sid = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file),
               let meta = try? decoder.decode(Meta.self, from: data) {
                result[sid] = meta
            }
        }
        cache.merge(result) { _, new in new }
        return result
    }

    private func fileURL(for sessionId: String) -> URL {
        baseURL.appendingPathComponent("\(sessionId).json")
    }
}
