import Foundation
import CryptoKit

/// Converts a stream of decoded jsonl lines into the `[ChatMessage]` shape Clarc
/// renders. Sidechain (subagent) lines and meta caveats are skipped; tool_result
/// user-lines fold back into the matching assistant `ToolCall.result`.
public enum CLILineToBlocksMapper {

    public static func map(lines: [CLISessionLine]) -> [ChatMessage] {
        var messages: [ChatMessage] = []

        for (lineIndex, line) in lines.enumerated() {
            switch line {
            case .skip:
                continue

            case .user(let user):
                if user.isSidechain || user.isMeta { continue }
                appendUser(user.message.content,
                           id: stableID(user.uuid, fallback: lineIndex),
                           timestamp: user.timestamp,
                           into: &messages)

            case .assistant(let assistant):
                if assistant.isSidechain { continue }
                appendAssistant(assistant.message.content,
                                id: stableID(assistant.uuid, fallback: lineIndex),
                                timestamp: assistant.timestamp,
                                into: &messages)
            }
        }

        // Drop tool_use blocks that never received a result and aren't kept-always —
        // matches the live-stream cleanup in AppState.
        for i in messages.indices {
            messages[i].finalizeToolCalls()
        }

        return messages
    }

    // MARK: - Stable identity

    /// Derive a stable message UUID from the CLI line's `uuid`. The CLI emits a
    /// standard UUID per line, so it round-trips directly; a missing/malformed
    /// value falls back to the line index (deterministic for a given file).
    /// Identity must stay constant across reloads — a fresh random UUID per
    /// parse makes `reloadCommittedFromDisk` replace the whole committed list on
    /// every reload, forcing SwiftUI to rebuild every row and flicker the chat.
    private static func stableID(_ uuid: String?, fallback lineIndex: Int) -> UUID {
        if let uuid, let parsed = UUID(uuidString: uuid) { return parsed }
        let digest = Insecure.MD5.hash(data: Data((uuid ?? "line-\(lineIndex)").utf8))
        let b = Array(digest)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    // MARK: - User

    private static func appendUser(
        _ content: UserContent,
        id: UUID,
        timestamp: Date?,
        into messages: inout [ChatMessage]
    ) {
        let blockID = "\(id.uuidString)#0"
        switch content {
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if CLIMetaEnvelope.isEnvelope(trimmed) { return }
            messages.append(ChatMessage(
                id: id,
                role: .user,
                blocks: [.text(s, id: blockID)],
                isResponseComplete: true,
                timestamp: timestamp ?? Date()
            ))

        case .parts(let parts):
            var textsForNewMessage: [String] = []
            for part in parts {
                switch part {
                case .text(let t):
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    if CLIMetaEnvelope.isEnvelope(trimmed) { continue }
                    textsForNewMessage.append(t)
                case .toolResult(let id, let content, let isError):
                    foldToolResult(id: id, result: content, isError: isError, into: &messages)
                case .unknown:
                    continue
                }
            }
            if !textsForNewMessage.isEmpty {
                let combined = textsForNewMessage.joined(separator: "\n\n")
                messages.append(ChatMessage(
                    id: id,
                    role: .user,
                    blocks: [.text(combined, id: blockID)],
                    isResponseComplete: true,
                    timestamp: timestamp ?? Date()
                ))
            }
        }
    }

    private static func foldToolResult(
        id: String,
        result: String,
        isError: Bool,
        into messages: inout [ChatMessage]
    ) {
        // Walk backwards — tool_result almost always pairs with the most recent
        // assistant tool_use, but a single assistant turn can have multiple.
        for i in messages.indices.reversed() {
            if messages[i].toolCallIndex(id: id) != nil {
                messages[i].setToolResult(id: id, result: result, isError: isError)
                return
            }
        }
        // Orphan tool_result (assistant line missing) — drop it silently.
    }

    // MARK: - Assistant

    private static func appendAssistant(
        _ content: [AssistantContentPart],
        id: UUID,
        timestamp: Date?,
        into messages: inout [ChatMessage]
    ) {
        var blocks: [MessageBlock] = []
        for (i, part) in content.enumerated() {
            switch part {
            case .text(let t):
                guard !t.isEmpty else { continue }
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if CLIMetaEnvelope.isNoResponseRequested(trimmed) { continue }
                blocks.append(.text(t, id: "\(id.uuidString)#\(i)"))
            case .toolUse(let id, let name, let input):
                blocks.append(.toolCall(ToolCall(id: id, name: name, input: input)))
            case .thinking(let t):
                guard !t.isEmpty else { continue }
                blocks.append(.thinking(t, id: "\(id.uuidString)#\(i)"))
            case .redactedThinking:
                blocks.append(.redactedThinking(id: "\(id.uuidString)#\(i)"))
            case .skip:
                continue
            }
        }

        // Empty assistant turn — collapse into a continuation of the previous
        // assistant message rather than adding an empty bubble.
        guard !blocks.isEmpty else { return }

        // If the previous assistant turn ended with an unresolved tool_use that
        // we kept, keep them as separate ChatMessages — Clarc renders one bubble
        // per ChatMessage and the live-stream code does the same.
        messages.append(ChatMessage(
            id: id,
            role: .assistant,
            blocks: blocks,
            isResponseComplete: true,
            timestamp: timestamp ?? Date()
        ))
    }
}
