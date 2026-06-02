import Foundation

/// Per-turn roll-up summary for a completed assistant turn.
///
/// A "phase" in Codex TUI semantics is one complete assistant turn
/// (from the user message that triggered it, to the `result` event that
/// closed it). When the turn finishes, AppState builds one of these
/// and pushes it through `ChatBridge.phaseSummaries`. The UI uses
/// the summary to render a collapsible card per turn; expanding the
/// card reveals the underlying ChatMessages for that turn (thinking
/// blocks, tool calls, final text response).
///
/// This is intentionally a presentation cache — the source of truth
/// for "what happened in this turn" is the underlying ChatMessage
/// array. The summary is re-derived on demand whenever a turn
/// finalizes and is cleared on session switch.
public struct PhaseSummary: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Index of this turn within the session (0-based). Used to render
    /// "Phase 1", "Phase 2", ... in the collapsed card.
    public let phaseIndex: Int
    /// Wall-clock instant the turn started (when the first delta of
    /// this turn arrived).
    public let startedAt: Date
    /// Wall-clock instant the turn ended (the result event).
    public let endedAt: Date
    /// Human-readable duration in seconds, pre-formatted by
    /// `DurationFormatting` for display.
    public let durationSeconds: Double

    /// Per-tool call snapshot, in invocation order. Captures name, a
    /// short input summary (file path / command head), and the result
    /// status (succeeded / failed / unverified).
    public let toolInvocations: [ToolInvocation]

    /// Number of tool calls in this turn whose result has not yet been
    /// seen by the time the turn closed (e.g. a stray Bash whose result
    /// was suppressed). Drives the "verification status" sub-section
    /// of the collapsed card.
    public let unverifiedCommandCount: Int

    /// Total count of tool invocations that completed with `isError == true`.
    public let failedInvocationCount: Int

    /// True when every tool call in this turn completed without error
    /// AND no commands are unverified. Drives the green "ready for
    /// review" badge in the collapsed card.
    public let readyForReview: Bool

    /// One-line human-readable summary of the most relevant changes made
    /// during this turn, derived from the tool inputs (e.g. "Edited
    /// Clarc/Info.plist, 8 lines changed"). Empty when the turn made
    /// no file-changing tool calls.
    public let changeSummary: String

    /// Suggestion for the next user action, extracted from the final
    /// text block of the turn via a regex on common "next step"
    /// phrasings (English: "next", "建议", "下一步", "建议尝试", "you
    /// can now", etc.). Empty when no match is found.
    public let suggestedNext: String

    /// IDs of the ChatMessages that belong to this turn. Used by the
    /// UI to map the summary back to the underlying messages when the
    /// user expands the card.
    public let messageIDs: [UUID]

    public init(
        id: UUID = UUID(),
        phaseIndex: Int,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double,
        toolInvocations: [ToolInvocation] = [],
        unverifiedCommandCount: Int = 0,
        failedInvocationCount: Int = 0,
        readyForReview: Bool = true,
        changeSummary: String = "",
        suggestedNext: String = "",
        messageIDs: [UUID] = []
    ) {
        self.id = id
        self.phaseIndex = phaseIndex
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.toolInvocations = toolInvocations
        self.unverifiedCommandCount = unverifiedCommandCount
        self.failedInvocationCount = failedInvocationCount
        self.readyForReview = readyForReview
        self.changeSummary = changeSummary
        self.suggestedNext = suggestedNext
        self.messageIDs = messageIDs
    }
}

extension PhaseSummary {
    /// Snapshot of a single tool call made during the turn. Captures
    /// just enough to render a "what tools were used" sub-section
    /// without re-walking the original ChatMessage each time.
    public struct ToolInvocation: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            case succeeded
            case failed
            case unverified
        }

        public let name: String
        /// Short input summary: file path for Edit/Write/Read, the
        /// first ~80 chars of the command for Bash, the URL for
        /// WebFetch, etc. Falls back to "(no input)" when extraction
        /// fails.
        public let inputSummary: String
        public let status: Status

        public init(name: String, inputSummary: String, status: Status) {
            self.name = name
            self.inputSummary = inputSummary
            self.status = status
        }
    }

    /// Extract a "next step" suggestion from the final text block of
    /// an assistant turn. Returns an empty string when no match is
    /// found, in which case the UI omits the sub-section.
    ///
    /// Heuristic regex set — covers both English and Mandarin so
    /// the same logic works regardless of the assistant's language.
    public static func extractSuggestedNext(from text: String) -> String {
        // Anchored patterns: "Next, ...", "建议 ...", "下一步 ...",
        // "you can now ...", "you should now ...". Each pattern tries
        // to capture the rest of the line / paragraph up to a
        // sentence boundary.
        let patterns: [String] = [
            #"(?im)\bNext[,:\s]+([^\n.!?]{1,160}[.!?])"#,
            #"(?im)\bYou (?:can|should|may|now)\s+(?:now\s+)?([^\n.!?]{1,160}[.!?])"#,
            #"(?im)建议[：:,，\s]+([^\n。!?]{1,160}[。.!?)])"#,
            #"(?im)下一步[：:,，\s]+([^\n。!?]{1,160}[。!?)])"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range),
                   match.numberOfRanges >= 2,
                   let captured = Range(match.range(at: 1), in: text) {
                    let value = text[captured].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return ""
    }

    /// Build a one-line "change summary" from a turn's tool
    /// invocations, focused on file-modifying tools (Edit / Write /
    /// MultiEdit). Returns an empty string when the turn made no
    /// such calls.
    public static func summarizeChanges(from invocations: [ToolInvocation]) -> String {
        let editingNames: Set<String> = ["Edit", "Write", "MultiEdit", "multi_edit", "NotebookEdit"]
        let edits = invocations.filter { editingNames.contains($0.name) }
        guard !edits.isEmpty else { return "" }
        let fileNames = edits
            .map { $0.inputSummary.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "(no input)" }
            .prefix(3)
            .map { ($0 as NSString).lastPathComponent }
        if fileNames.isEmpty {
            return "Edited \(edits.count) file\(edits.count == 1 ? "" : "s")"
        }
        return "Edited \(fileNames.joined(separator: ", "))"
    }
}
