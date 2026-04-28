import Foundation

/// One decoded line from a Claude Code CLI session jsonl. Most line types are
/// internal bookkeeping (snapshots, diagnostics, hooks) and are not user-visible;
/// we only model the two we need to render — user and assistant — and skip the
/// rest. Unknown `type` values are silently dropped to stay forward-compatible
/// with new CLI versions.
public enum CLISessionLine: Sendable {
    case user(UserLine)
    case assistant(AssistantLine)
    case skip
}

extension CLISessionLine: Decodable {
    private enum DiscriminatorKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "user":
            self = .user(try UserLine(from: decoder))
        case "assistant", "message":
            self = .assistant(try AssistantLine(from: decoder))
        default:
            self = .skip
        }
    }
}

// MARK: - User line

public struct UserLine: Decodable, Sendable {
    public let uuid: String?
    public let parentUuid: String?
    public let timestamp: Date?
    public let sessionId: String?
    public let cwd: String?
    public let isMeta: Bool
    public let isSidechain: Bool
    public let message: CLIUserMessage

    private enum CodingKeys: String, CodingKey {
        case uuid, parentUuid, timestamp, sessionId, cwd, isMeta, isSidechain, message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decodeIfPresent(String.self, forKey: .uuid)
        parentUuid = try c.decodeIfPresent(String.self, forKey: .parentUuid)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        isMeta = try c.decodeIfPresent(Bool.self, forKey: .isMeta) ?? false
        isSidechain = try c.decodeIfPresent(Bool.self, forKey: .isSidechain) ?? false
        message = try c.decode(CLIUserMessage.self, forKey: .message)
    }
}

public struct CLIUserMessage: Decodable, Sendable {
    public let content: UserContent

    public init(content: UserContent) { self.content = content }
}

/// `content` may be a plain string ("hi") or an array of typed parts (only
/// tool_result is meaningful to us; text inside an array is rare for user
/// messages but handled).
public enum UserContent: Sendable {
    case string(String)
    case parts([UserContentPart])
}

extension UserContent: Decodable {
    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let s = try? single.decode(String.self) {
            self = .string(s)
        } else {
            let parts = (try? single.decode([UserContentPart].self)) ?? []
            self = .parts(parts)
        }
    }
}

public enum UserContentPart: Sendable {
    case text(String)
    case toolResult(id: String, content: String, isError: Bool)
    case unknown
}

extension UserContentPart: Decodable {
    private enum Keys: String, CodingKey {
        case type, text
        case tool_use_id, content, is_error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "text":
            self = .text(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool_result":
            let id = try c.decodeIfPresent(String.self, forKey: .tool_use_id) ?? ""
            let isError = try c.decodeIfPresent(Bool.self, forKey: .is_error) ?? false
            // tool_result.content can be a string or an array of {type:"text", text:"..."}.
            let content = Self.flattenToolResult(container: c)
            self = .toolResult(id: id, content: content, isError: isError)
        default:
            self = .unknown
        }
    }

    private static func flattenToolResult(container c: KeyedDecodingContainer<Keys>) -> String {
        if let s = try? c.decodeIfPresent(String.self, forKey: .content), !s.isEmpty {
            return s
        }
        if let parts = try? c.decodeIfPresent([ToolResultPart].self, forKey: .content) {
            return parts.compactMap(\.text).joined(separator: "\n")
        }
        return ""
    }

    private struct ToolResultPart: Decodable {
        let type: String?
        let text: String?
    }
}

// MARK: - Assistant line

public struct AssistantLine: Decodable, Sendable {
    public let uuid: String?
    public let parentUuid: String?
    public let timestamp: Date?
    public let sessionId: String?
    public let cwd: String?
    public let isSidechain: Bool
    public let message: CLIAssistantMessage

    private enum CodingKeys: String, CodingKey {
        case uuid, parentUuid, timestamp, sessionId, cwd, isSidechain, message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decodeIfPresent(String.self, forKey: .uuid)
        parentUuid = try c.decodeIfPresent(String.self, forKey: .parentUuid)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        isSidechain = try c.decodeIfPresent(Bool.self, forKey: .isSidechain) ?? false
        message = try c.decode(CLIAssistantMessage.self, forKey: .message)
    }
}

public struct CLIAssistantMessage: Decodable, Sendable {
    public let id: String?
    public let model: String?
    public let content: [AssistantContentPart]

    private enum CodingKeys: String, CodingKey {
        case id, model, content
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        content = (try? c.decode([AssistantContentPart].self, forKey: .content)) ?? []
    }
}

/// We deliberately drop `thinking` blocks at decode time — they can be tens of
/// KB of base64-ish signature data and bloat memory. We don't render them, so
/// they don't reach `MessageBlock`.
public enum AssistantContentPart: Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case skip
}

extension AssistantContentPart: Decodable {
    private enum Keys: String, CodingKey {
        case type, text, id, name, input
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "text":
            self = .text(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool_use":
            let id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            let name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            let input = (try? c.decode([String: JSONValue].self, forKey: .input)) ?? [:]
            self = .toolUse(id: id, name: name, input: input)
        default:
            // thinking, server_tool_use, redacted_thinking, ...
            self = .skip
        }
    }
}
