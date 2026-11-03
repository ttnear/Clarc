import Foundation

/// Evaluates tool calls against the `permissions` rules the user has already configured for
/// Claude Code (`~/.claude/settings.json`, `<project>/.claude/settings.json` and
/// `<project>/.claude/settings.local.json`).
///
/// Clarc's PreToolUse hook runs before the CLI evaluates those rules, so without this the user's
/// existing allow-list is never consulted and every Bash/MCP call raises a modal.
///
/// The matcher is deliberately conservative: it only ever answers "yes, auto-approve" when every
/// part of the call is clearly covered by an allow rule and nothing matches a deny/ask rule.
/// Anything it does not understand falls through to the normal approval modal.
struct ClaudeSettingsPermissions: Sendable {

    // MARK: - Rule

    struct Rule: Sendable, Equatable {
        /// Tool name or pattern, e.g. `Bash`, `mcp__sheets__get_values`, `mcp__sheets__set_value*`.
        nonisolated let tool: String
        /// The text inside the parentheses of `Tool(specifier)`, if any.
        nonisolated let specifier: String?

        nonisolated init(tool: String, specifier: String?) {
            self.tool = tool
            self.specifier = specifier
        }

        /// Parses `Tool` or `Tool(specifier)`.
        nonisolated init?(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") {
                let tool = String(trimmed[..<open])
                guard !tool.isEmpty else { return nil }
                let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
                self.init(tool: tool, specifier: String(inner))
            } else {
                self.init(tool: trimmed, specifier: nil)
            }
        }
    }

    // MARK: - Properties

    nonisolated let allow: [Rule]
    nonisolated let deny: [Rule]
    nonisolated let ask: [Rule]

    nonisolated init(allow: [Rule] = [], deny: [Rule] = [], ask: [Rule] = []) {
        self.allow = allow
        self.deny = deny
        self.ask = ask
    }

    // MARK: - Loading

    /// Merges the rules from the user's and the project's Claude Code settings files.
    /// Missing or malformed files are ignored.
    nonisolated static func load(
        projectPath: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ClaudeSettingsPermissions {
        var files = [homeDirectory.appendingPathComponent(".claude/settings.json")]
        if let projectPath, !projectPath.isEmpty {
            let project = URL(fileURLWithPath: projectPath, isDirectory: true)
            files.append(project.appendingPathComponent(".claude/settings.json"))
            files.append(project.appendingPathComponent(".claude/settings.local.json"))
        }

        var allow: [Rule] = []
        var deny: [Rule] = []
        var ask: [Rule] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let permissions = root["permissions"] as? [String: Any] else { continue }
            allow += rules(in: permissions["allow"])
            deny += rules(in: permissions["deny"])
            ask += rules(in: permissions["ask"])
        }
        return ClaudeSettingsPermissions(allow: allow, deny: deny, ask: ask)
    }

    private nonisolated static func rules(in value: Any?) -> [Rule] {
        (value as? [Any])?.compactMap { ($0 as? String).flatMap(Rule.init) } ?? []
    }

    // MARK: - Evaluation

    /// True when the call is fully covered by allow rules and not touched by any deny/ask rule.
    /// - Parameter command: the `command` input of a Bash call (ignored for other tools).
    /// - Parameter isSafeSegment: an extra check for one Bash segment (e.g. a built-in read-only
    ///   whitelist), so a compound command can mix segments covered by rules with segments the
    ///   check approves. It never overrides a deny/ask match.
    nonisolated func autoApproves(
        toolName: String,
        command: String?,
        isSafeSegment: (String) -> Bool = { _ in false }
    ) -> Bool {
        if toolName == "Bash" {
            guard let command, let segments = Self.parseSegments(command), !segments.isEmpty else { return false }
            for segment in segments where matches(deny, bashSegment: segment) || matches(ask, bashSegment: segment) {
                return false
            }
            return segments.allSatisfy { matches(allow, bashSegment: $0) || isSafeSegment($0) }
        }

        // Specifier rules (`Edit(path)`, `WebFetch(domain:…)`) are not evaluated here, so a deny/ask
        // rule for the tool of any shape blocks auto-approval, while only a bare allow rule grants it.
        if (deny + ask).contains(where: { Self.toolMatches($0.tool, toolName) }) { return false }
        return allow.contains { $0.specifier == nil && Self.toolMatches($0.tool, toolName) }
    }

    private nonisolated func matches(_ rules: [Rule], bashSegment segment: String) -> Bool {
        rules.contains { rule in
            guard rule.tool == "Bash" else { return false }
            guard let specifier = rule.specifier else { return true }
            return Self.bashPatternMatches(specifier, segment)
        }
    }

    /// `mcp__server` covers every tool of that server; `*` is a wildcard anywhere in the name.
    private nonisolated static func toolMatches(_ ruleTool: String, _ toolName: String) -> Bool {
        if ruleTool == toolName { return true }
        if ruleTool.contains("*") { return wildcardMatch(ruleTool, toolName) }
        if ruleTool.hasPrefix("mcp__"), !ruleTool.dropFirst("mcp__".count).contains("__") {
            return toolName.hasPrefix(ruleTool + "__")
        }
        return false
    }

    private nonisolated static func bashPatternMatches(_ pattern: String, _ segment: String) -> Bool {
        // Legacy prefix syntax: `Bash(maestro:*)`.
        if pattern.hasSuffix(":*") {
            let prefix = String(pattern.dropLast(2))
            return segment == prefix || segment.hasPrefix(prefix + " ")
        }
        return wildcardMatch(pattern, segment)
    }

    /// Glob matching where `*` matches any run of characters (including none and spaces).
    nonisolated static func wildcardMatch(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern)
        let t = Array(text)
        var pi = 0, ti = 0
        var starIndex: Int?
        var matchIndex = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "*" {
                starIndex = pi
                matchIndex = ti
                pi += 1
            } else if pi < p.count, p[pi] == t[ti] {
                pi += 1
                ti += 1
            } else if let star = starIndex {
                pi = star + 1
                matchIndex += 1
                ti = matchIndex
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    // MARK: - Bash command parsing

    private nonisolated static let harmlessRedirects: [[Character]] = [
        Array("2>&1"), Array("2>/dev/null"), Array(">/dev/null"),
    ]

    /// Splits a command on unquoted `;`, `&&`, `||`, `|` and newlines.
    ///
    /// Returns nil when the command contains anything that cannot be judged from its text alone:
    /// command or process substitution, backgrounding, unterminated quotes, or output redirected
    /// anywhere other than `/dev/null` / `2>&1`.
    nonisolated static func parseSegments(_ command: String) -> [String]? {
        let chars = Array(command)
        var segments: [String] = []
        // `text` is what gets matched against rules; `skeleton` is the same characters with quoted
        // or escaped content blanked out, so syntax checks never trip on text inside quotes.
        var text: [Character] = []
        var skeleton: [Character] = []
        var quote: Character?
        var escaped = false

        func flush() -> Bool {
            for token in harmlessRedirects {
                while let at = indexOf(token, in: skeleton) {
                    skeleton.removeSubrange(at..<at + token.count)
                    text.removeSubrange(at..<at + token.count)
                }
            }
            stripScratchRedirects(text: &text, skeleton: &skeleton)
            if skeleton.contains(">") { return false }
            let segment = String(text).trimmingCharacters(in: .whitespaces)
            let blanked = String(skeleton).trimmingCharacters(in: .whitespaces)
            if !segment.isEmpty, let kept = scaffoldingStripped(segment, skeleton: blanked) { segments.append(kept) }
            text = []
            skeleton = []
            return true
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            defer { i += 1 }

            if escaped {
                text.append(c); skeleton.append("_"); escaped = false
                continue
            }
            if quote == "'" {
                text.append(c); skeleton.append("_")
                if c == "'" { quote = nil }
                continue
            }
            if c == "\\" {
                text.append(c); skeleton.append("_"); escaped = true
                continue
            }
            if c == "`" || (c == "$" && next == "(") { return nil }
            if quote == "\"" {
                text.append(c); skeleton.append("_")
                if c == "\"" { quote = nil }
                continue
            }

            switch c {
            case "'", "\"":
                quote = c
                text.append(c); skeleton.append("_")
            case "<", ">":
                if next == "(" { return nil }
                text.append(c); skeleton.append(c)
            case ";", "\n":
                if !flush() { return nil }
            case "|":
                if next == "|" { i += 1 }
                if !flush() { return nil }
            case "&":
                if next == "&" {
                    i += 1
                    if !flush() { return nil }
                } else if skeleton.last == ">" {
                    text.append(c); skeleton.append(c)   // the `&` of `2>&1`
                } else {
                    return nil                           // backgrounding
                }
            default:
                text.append(c); skeleton.append(c)
            }
        }
        if quote != nil || escaped { return nil }
        return flush() ? segments : nil
    }

    private nonisolated static let scratchPrefixes: [[Character]] = [Array("/tmp/"), Array("/private/tmp/")]
    private nonisolated static let scratchPathCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/")

    /// Removes `>` / `>>` / `N>` redirects whose target is an unquoted literal path under `/tmp`
    /// (no `..`, no variables or globs), so scratch output files don't block auto-approval.
    private nonisolated static func stripScratchRedirects(text: inout [Character], skeleton: inout [Character]) {
        var i = 0
        while i < skeleton.count {
            guard skeleton[i] == ">" else { i += 1; continue }
            var start = i
            if start > 0, skeleton[start - 1].isNumber, start == 1 || skeleton[start - 2] == " " { start -= 1 }
            var j = i + 1
            if j < skeleton.count, skeleton[j] == ">" { j += 1 }
            while j < skeleton.count, skeleton[j] == " " { j += 1 }
            var k = j
            // Scan `text`, not `skeleton`: the skeleton blanks quoted content to `_`, which would pass this check.
            while k < text.count, scratchPathCharacters.contains(text[k]) { k += 1 }
            let target = Array(text[j..<k])
            // The target must end at whitespace or the end of the segment, so `/tmp/a$X` or `/tmp/a*` never qualify.
            let endsCleanly = k == skeleton.count || skeleton[k] == " "
            let isScratch = endsCleanly
                && scratchPrefixes.contains { target.starts(with: $0) && target.count > $0.count }
                && !String(target).contains("..")
            if isScratch {
                skeleton.removeSubrange(start..<k)
                text.removeSubrange(start..<k)
                i = start
            } else {
                i += 1
            }
        }
    }

    private nonisolated static let loopWordCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/@%+=:,~")

    /// Handles the scaffolding of `for NAME in WORDS; do CMD; done`: the header and `done` are
    /// dropped (nil) and the `do ` prefix is stripped, leaving CMD to be matched on its own.
    /// A header whose words are not plain (variables, globs, substitution) is left as-is, so no
    /// rule will cover it. `while` / `until` are not handled and stay unmatched.
    private nonisolated static func scaffoldingStripped(_ segment: String, skeleton: String) -> String? {
        if segment == "done" || segment == "do" { return nil }
        if segment.hasPrefix("do ") {
            let rest = segment.dropFirst(3).trimmingCharacters(in: .whitespaces)
            let restSkeleton = skeleton.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : scaffoldingStripped(rest, skeleton: restSkeleton)
        }
        if isHarmlessAssignment(segment, skeleton: skeleton) { return nil }
        if segment.hasPrefix("for ") {
            let words = segment.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if words.count >= 4, words[2] == "in",
               let first = words[1].first, first.isLetter || first == "_",
               words[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
               words[3...].allSatisfy({ word in !word.isEmpty && word.allSatisfy { loopWordCharacters.contains($0) } }) {
                return nil
            }
        }
        return segment
    }

    /// Variables that change how later commands are resolved or loaded; never treated as harmless.
    private nonisolated static let sensitiveVariables: Set<String> = ["PATH", "IFS", "BASH_ENV", "ENV", "SHELLOPTS", "PS4", "PROMPT_COMMAND"]

    /// A bare `NAME=value` segment: one word, no expansion of any kind. `NAME=value cmd` (an env
    /// prefix for cmd) has an unquoted space and is not bare, so it still goes through rule matching.
    private nonisolated static func isHarmlessAssignment(_ segment: String, skeleton: String) -> Bool {
        guard let eq = skeleton.firstIndex(of: "=") else { return false }
        let name = skeleton[..<eq]
        guard let first = name.first, first.isLetter || first == "_",
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              !sensitiveVariables.contains(String(name)),
              !name.hasPrefix("LD_"), !name.hasPrefix("DYLD_") else { return false }
        let value = skeleton[skeleton.index(after: eq)...]
        return !value.contains(where: \.isWhitespace) && !segment.contains("$") && !value.contains("<") && !value.contains(">")
    }

    private nonisolated static func indexOf(_ needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<start + needle.count]) == needle {
            return start
        }
        return nil
    }
}
