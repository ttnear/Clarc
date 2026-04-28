import Foundation

/// Maps a working-directory absolute path to the directory name Claude Code CLI
/// uses under `~/.claude/projects/`. The CLI replaces both `/` and `.` with `-`,
/// so the encoding is lossy in one direction. When precise project matching is
/// needed, callers should also consult the `cwd` field embedded in jsonl records
/// (see `CLISessionStore.directory(forCwd:)`).
extension String {
    public func cliProjectDirName() -> String {
        let normalized = (self as NSString).standardizingPath
        var s = normalized
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: ".", with: "-")
        return s
    }

    /// Trailing-slash-stripped, symlink-resolution-skipping standardization, so
    /// "/Users/x/" and "/Users/x" hash to the same key when comparing cwds.
    public func standardizedCwd() -> String {
        var s = (self as NSString).standardizingPath
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

public enum CLIProjectsDirectory {
    /// `~/.claude/projects`. Created lazily by the CLI; may not exist yet.
    public static var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Resolved directory for a given working-directory path. Existence not guaranteed.
    public static func directory(forCwd cwd: String) -> URL {
        url.appendingPathComponent(cwd.cliProjectDirName(), isDirectory: true)
    }
}
