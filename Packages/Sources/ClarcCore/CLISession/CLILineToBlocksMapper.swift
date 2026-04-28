import Foundation

/// Converts a stream of decoded jsonl lines into the `[ChatMessage]` shape Clarc
/// renders. Sidechain (subagent) lines and meta caveats are skipped; tool_result
/// user-lines fold back into the matching assistant `ToolCall.result`.
public enum CLILineToBlocksMapper {

    public static func map(lines: [CLISessionLine]) -> [ChatMessage] {
        var messages: [ChatMessage] = []

        for line in lines {
            switch line {
            case .skip:
                continue

            case .user(let user):
                if user.isSidechain || user.isMeta { continue }
                appendUser(user.message.content,
                           timestamp: user.timestamp,
                           into: &messages)

            case .assistant(let assistant):
                if assistant.isSidechain { continue }
                appendAssistant(assistant.message.content,
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

    // MARK: - User

    private static func appendUser(
        _ content: UserContent,
        timestamp: Date?,
        into messages: inout [ChatMessage]
    ) {
        switch content {
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if CLIMetaEnvelope.isEnvelope(trimmed) { return }
            messages.append(ChatMessage(
                role: .user,
                blocks: [.text(s)],
                isResponseComplete: true,
                timestamp: timestamp ?? Date()
            ))

        case .parts(let parts):
            var textsForNewMessage: [String] = []
            for part in parts {
                switch part {
                case .text(let t):
                    if !t.isEmpty { textsForNewMessage.append(t) }
                case .toolResult(let id, let content, let isError):
                    foldToolResult(id: id, result: content, isError: isError, into: &messages)
                case .unknown:
                    continue
                }
            }
            if !textsForNewMessage.isEmpty {
                let combined = textsForNewMessage.joined(separator: "\n\n")
                messages.append(ChatMessage(
                    role: .user,
                    blocks: [.text(combined)],
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
        timestamp: Date?,
        into messages: inout [ChatMessage]
    ) {
        var blocks: [MessageBlock] = []
        for part in content {
            switch part {
            case .text(let t):
                if !t.isEmpty { blocks.append(.text(t)) }
            case .toolUse(let id, let name, let input):
                blocks.append(.toolCall(ToolCall(id: id, name: name, input: input)))
            case .skip:
                continue
            }
        }

        // Empty assistant turn (e.g. only a thinking block) — collapse into a
        // continuation of the previous assistant message rather than adding an
        // empty bubble.
        guard !blocks.isEmpty else { return }

        // If the previous assistant turn ended with an unresolved tool_use that
        // we kept, keep them as separate ChatMessages — Clarc renders one bubble
        // per ChatMessage and the live-stream code does the same.
        messages.append(ChatMessage(
            role: .assistant,
            blocks: blocks,
            isResponseComplete: true,
            timestamp: timestamp ?? Date()
        ))
    }
}
