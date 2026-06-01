import Foundation

/// Evaluates read-only Bash commands against a whitelist.
enum BashSafety {

    private nonisolated static let safeCommands: Set<String> = [
        // info / help
        "cat", "head", "tail", "less", "more", "wc", "file", "stat",
        "ls", "pwd", "echo", "printf", "date", "whoami", "hostname", "uname",
        "which", "whence", "where", "type", "command",
        "man", "help", "info",
        // search
        "find", "grep", "rg", "ag", "ack", "fd", "fzf", "locate",
        // git (subcommands validated separately)
        "git",
        // environment
        "env", "printenv", "set",
        // package managers (subcommands validated separately)
        "npm", "yarn", "pnpm", "bun", "cargo", "pip", "pip3", "go", "rustup",
        "node", "python", "python3", "ruby", "java", "javac",
        // claude CLI (subcommands validated separately)
        "claude",
        // system info
        "df", "du", "free", "top", "htop", "ps", "uptime", "lsof",
        "tree", "realpath", "dirname", "basename",
        // macOS specific
        "sw_vers", "system_profiler", "defaults", "mdls", "mdfind",
        // comparison / text processing
        "diff", "cmp", "comm", "sort", "uniq", "cut", "awk", "sed",
        "jq", "yq", "xargs", "tr",
        // code / archive inspection (read-only)
        "tokei", "cloc", "tar", "unzip", "zip",
        // binary / hash inspection (read-only)
        "xxd", "hexdump", "od", "strings",
        "shasum", "md5sum", "sha256sum", "base64",
        // misc read-only utilities
        "id", "groups", "rev", "time", "cal",
    ]

    private nonisolated static let gitMutatingSubcommands: Set<String> = [
        "push", "commit", "merge", "rebase", "reset", "checkout", "switch",
        "branch", "tag", "stash", "cherry-pick", "revert", "am", "apply",
        "clean", "rm", "mv", "restore", "bisect", "pull", "fetch", "clone",
        "init", "submodule", "worktree", "gc", "prune", "filter-branch",
    ]

    private nonisolated static let claudeMutatingSubcommands: Set<String> = [
        "config", "login", "logout",
    ]

    private nonisolated static let packageMutatingSubcommands: Set<String> = [
        "install", "i", "add", "remove", "uninstall", "publish", "run",
        "exec", "dlx", "npx", "create", "init", "link", "unlink", "pack", "deprecate",
    ]

    /// Regex to split command chaining operators. `||` must be matched before `\|` to avoid splitting into two `|` tokens.
    private nonisolated static let segmentSeparator: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s*(?:;|&&|\|\||\|)\s*"#)
    }()

    private nonisolated static let allowedRedirectTokens = [">/dev/null", "2>/dev/null", "2>&1"]

    nonisolated static func isSafeReadOnly(command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let segments = splitSegments(trimmed)
        guard !segments.isEmpty else { return false }

        for segment in segments {
            if !isSafeSegment(segment) { return false }
        }
        return true
    }

    private nonisolated static func splitSegments(_ input: String) -> [String] {
        let regex = segmentSeparator
        let ns = input as NSString
        var segments: [String] = []
        var lastEnd = 0
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            if m.range.location > lastEnd {
                segments.append(ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd)))
            }
            lastEnd = m.range.location + m.range.length
        }
        if lastEnd < ns.length {
            segments.append(ns.substring(from: lastEnd))
        }
        return segments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private nonisolated static func isSafeSegment(_ segment: String) -> Bool {
        // Block file write redirections. /dev/null and 2>&1 are allowed.
        if segmentHasWriteRedirect(segment) { return false }

        let parts = segment.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let firstRaw = parts.first else { return false }

        // VAR=val cmd pattern: if the first token contains =, use the next token as the actual command.
        let envPrefixed = firstRaw.contains("=")
        let cmdIdx = envPrefixed ? 1 : 0
        guard cmdIdx < parts.count else { return false }
        let cmd = parts[cmdIdx]
        let base = cmd.split(separator: "/").last.map(String.init) ?? cmd

        guard safeCommands.contains(base) else { return false }

        let subIdx = cmdIdx + 1
        let sub: String? = subIdx < parts.count ? parts[subIdx] : nil

        switch base {
        case "git":
            if let s = sub, gitMutatingSubcommands.contains(s) { return false }
        case "claude":
            if let s = sub {
                if claudeMutatingSubcommands.contains(s) { return false }
                if s == "mcp" {
                    let mcpIdx = subIdx + 1
                    let mcpSub = mcpIdx < parts.count ? parts[mcpIdx] : nil
                    if let ms = mcpSub, ms != "list", ms != "get", ms != "--help" { return false }
                }
            }
        case "npm", "yarn", "pnpm", "bun":
            if let s = sub, packageMutatingSubcommands.contains(s) { return false }
        default:
            break
        }

        return true
    }

    private nonisolated static func segmentHasWriteRedirect(_ segment: String) -> Bool {
        guard segment.contains(">") else { return false }
        var stripped = segment
        for token in allowedRedirectTokens {
            stripped = stripped.replacingOccurrences(of: token, with: "")
        }
        return stripped.contains(">")
    }
}
