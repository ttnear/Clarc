import Foundation
import os

/// Sidecar persistence for the Clarc-only fields that don't live in the CLI's
/// jsonl: title, isPinned, model, effort, permissionMode. One file per session
/// id at `~/Library/Application Support/Clarc/session-meta/{sid}.json`.
public actor SessionMetaStore {

    public struct Meta: Codable, Sendable {
        public var title: String?
        public var isPinned: Bool
        public var model: String?
        public var effort: String?
        public var permissionMode: PermissionMode?
        public var updatedAt: Date?

        public init(
            title: String? = nil,
            isPinned: Bool = false,
            model: String? = nil,
            effort: String? = nil,
            permissionMode: PermissionMode? = nil,
            updatedAt: Date? = nil
        ) {
            self.title = title
            self.isPinned = isPinned
            self.model = model
            self.effort = effort
            self.permissionMode = permissionMode
            self.updatedAt = updatedAt
        }
    }

    private let baseURL: URL
    private let logger = Logger(subsystem: "com.claudework", category: "SessionMetaStore")

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.baseURL = appSupport.appendingPathComponent("Clarc/session-meta", isDirectory: true)
    }

    public func load(sessionId: String) -> Meta {
        let url = fileURL(for: sessionId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return Meta()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Meta.self, from: data)) ?? Meta()
    }

    public func save(sessionId: String, meta: Meta) {
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
        return result
    }

    private func fileURL(for sessionId: String) -> URL {
        baseURL.appendingPathComponent("\(sessionId).json")
    }
}
