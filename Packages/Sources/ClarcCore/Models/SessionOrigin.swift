import Foundation

/// Where the session's message content lives on disk.
public enum SessionOrigin: String, Codable, Sendable {
    /// Legacy Clarc-owned JSON at `~/Library/Application Support/Clarc/sessions/{projectId}/{sid}.json`.
    /// Read-only going forward; will not appear in the CLI's `~/.claude/projects/...` directory.
    case legacyClarc

    /// Backed by Claude Code CLI's `~/.claude/projects/{enc(cwd)}/{sid}.jsonl`.
    /// Source of truth is the CLI; Clarc keeps Clarc-only metadata in a sidecar.
    case cliBacked
}
