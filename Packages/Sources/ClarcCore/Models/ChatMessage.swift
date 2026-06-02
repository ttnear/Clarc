import Foundation

// MARK: - Message Block

public struct MessageBlock: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var text: String?
    public var toolCall: ToolCall?
    public var thinking: String?
    public var thinkingDuration: TimeInterval?
    public var isThinkingRedacted: Bool

    public var isText: Bool { text != nil }
    public var isToolCall: Bool { toolCall != nil }
    public var isThinking: Bool { thinking != nil || isThinkingRedacted }

    public init(
        id: String,
        text: String? = nil,
        toolCall: ToolCall? = nil,
        thinking: String? = nil,
        thinkingDuration: TimeInterval? = nil,
        isThinkingRedacted: Bool = false
    ) {
        self.id = id
        self.text = text
        self.toolCall = toolCall
        self.thinking = thinking
        self.thinkingDuration = thinkingDuration
        self.isThinkingRedacted = isThinkingRedacted
    }

    public static func text(_ text: String, id: String = UUID().uuidString) -> MessageBlock {
        MessageBlock(id: id, text: text)
    }

    public static func toolCall(_ toolCall: ToolCall) -> MessageBlock {
        MessageBlock(id: toolCall.id, toolCall: toolCall)
    }

    public static func thinking(
        _ thinking: String,
        duration: TimeInterval? = nil,
        id: String = UUID().uuidString
    ) -> MessageBlock {
        MessageBlock(id: id, thinking: thinking, thinkingDuration: duration)
    }

    public static func redactedThinking(id: String = UUID().uuidString) -> MessageBlock {
        MessageBlock(id: id, isThinkingRedacted: true)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, toolCall, thinking, thinkingDuration, isThinkingRedacted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        toolCall = try c.decodeIfPresent(ToolCall.self, forKey: .toolCall)
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        thinkingDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .thinkingDuration)
        isThinkingRedacted = try c.decodeIfPresent(Bool.self, forKey: .isThinkingRedacted) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(toolCall, forKey: .toolCall)
        try c.encodeIfPresent(thinking, forKey: .thinking)
        try c.encodeIfPresent(thinkingDuration, forKey: .thinkingDuration)
        if isThinkingRedacted { try c.encode(true, forKey: .isThinkingRedacted) }
    }
}

// MARK: - Chat Message

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public let role: Role
    public var blocks: [MessageBlock]
    public var isStreaming: Bool
    public var isResponseComplete: Bool
    public let timestamp: Date
    public var attachmentPaths: [AttachmentInfo]
    public var duration: TimeInterval?
    public var isError: Bool
    public var isCompactBoundary: Bool

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String = "",
        blocks: [MessageBlock]? = nil,
        isStreaming: Bool = false,
        isResponseComplete: Bool = false,
        timestamp: Date = Date(),
        attachments: [Attachment] = [],
        duration: TimeInterval? = nil,
        isError: Bool = false,
        isCompactBoundary: Bool = false
    ) {
        self.id = id
        self.role = role
        if let blocks {
            self.blocks = blocks
        } else if !content.isEmpty {
            self.blocks = [.text(content)]
        } else {
            self.blocks = []
        }
        self.isStreaming = isStreaming
        self.isResponseComplete = isResponseComplete
        self.timestamp = timestamp
        self.attachmentPaths = attachments.map {
            AttachmentInfo(name: $0.name, path: $0.path, type: $0.type.rawValue)
        }
        self.duration = duration
        self.isError = isError
        self.isCompactBoundary = isCompactBoundary
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, role, blocks, isStreaming, isResponseComplete, timestamp, attachmentPaths, duration, isError, isCompactBoundary
        case content, toolCalls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        isResponseComplete = try container.decodeIfPresent(Bool.self, forKey: .isResponseComplete) ?? false
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        attachmentPaths = try container.decodeIfPresent([AttachmentInfo].self, forKey: .attachmentPaths) ?? []
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        isCompactBoundary = try container.decodeIfPresent(Bool.self, forKey: .isCompactBoundary) ?? false

        if let decodedBlocks = try container.decodeIfPresent([MessageBlock].self, forKey: .blocks) {
            blocks = decodedBlocks
        } else {
            var migrated: [MessageBlock] = []
            if let content = try container.decodeIfPresent(String.self, forKey: .content),
               !content.isEmpty {
                migrated.append(.text(content))
            }
            if let toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls) {
                for tc in toolCalls {
                    migrated.append(.toolCall(tc))
                }
            }
            blocks = migrated
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(blocks, forKey: .blocks)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(isResponseComplete, forKey: .isResponseComplete)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(attachmentPaths, forKey: .attachmentPaths)
        try container.encodeIfPresent(duration, forKey: .duration)
        if isError { try container.encode(isError, forKey: .isError) }
        if isCompactBoundary { try container.encode(isCompactBoundary, forKey: .isCompactBoundary) }
    }

    // MARK: - Convenience Accessors

    public var content: String {
        get {
            blocks.compactMap(\.text).joined(separator: "\n\n")
        }
        set {
            blocks.removeAll { $0.isText }
            if !newValue.isEmpty {
                blocks.insert(.text(newValue), at: 0)
            }
        }
    }

    public var toolCalls: [ToolCall] {
        blocks.compactMap(\.toolCall)
    }

    public mutating func appendText(_ text: String) {
        if let lastTextIndex = blocks.lastIndex(where: { $0.isText }) {
            blocks[lastTextIndex].text! += text
        } else {
            blocks.append(.text(text))
        }
    }

    public mutating func appendToolCall(_ toolCall: ToolCall) {
        blocks.append(.toolCall(toolCall))
    }

    public mutating func appendThinkingDelta(_ text: String, blockId: String) {
        if let lastIdx = blocks.indices.last,
           blocks[lastIdx].isThinking,
           blocks[lastIdx].id == blockId {
            blocks[lastIdx].thinking = (blocks[lastIdx].thinking ?? "") + text
        } else {
            blocks.append(.thinking(text, id: blockId))
        }
    }

    public mutating func finalizeThinking(blockId: String, duration: TimeInterval?) {
        guard let idx = blocks.lastIndex(where: { $0.id == blockId }) else { return }
        blocks[idx].thinkingDuration = duration
        if (blocks[idx].thinking?.isEmpty ?? true) && !blocks[idx].isThinkingRedacted {
            blocks.remove(at: idx)
        }
    }

    public func toolCallIndex(id: String) -> Int? {
        blocks.firstIndex(where: { $0.toolCall?.id == id })
    }

    public mutating func setToolResult(id: String, result: String, isError: Bool) {
        guard let index = toolCallIndex(id: id),
              let toolCall = blocks[index].toolCall else { return }
        if result.isEmpty && !isError && !toolCall.isKeepAlways {
            blocks.remove(at: index)
        } else {
            blocks[index].toolCall?.result = result
            blocks[index].toolCall?.isError = isError
        }
    }

    public mutating func finalizeToolCalls() {
        blocks.removeAll { block in
            guard let toolCall = block.toolCall else { return false }
            if toolCall.isKeepAlways { return false }
            return toolCall.result == nil || (toolCall.result?.isEmpty == true && !toolCall.isError)
        }
    }
}

// MARK: - Identity Reconciliation

extension ChatMessage {
    /// Disk is the source of truth for message *content*, but a fresh parse of the
    /// CLI jsonl assigns ids derived from the line `uuid` — which differ from the
    /// random ids a live stream produced for the same turns. Swapping them in
    /// re-keys every SwiftUI row and visibly flickers the chat when a stream ends
    /// and `reloadCommittedFromDisk` runs.
    ///
    /// Carry the previous render's ids onto the freshly parsed messages wherever
    /// they line up (same index, same role), so identity stays stable while content
    /// still comes from disk. Text-block ids are preserved the same way; tool-call
    /// blocks already key off the stable CLI tool_use id, so they need no help.
    /// Anything that doesn't line up keeps its disk id — a one-time re-key there is
    /// safer than grafting identity onto the wrong message.
    public static func reconcilingIdentity(
        _ incoming: [ChatMessage],
        from previous: [ChatMessage]
    ) -> [ChatMessage] {
        guard !previous.isEmpty else { return incoming }
        return incoming.enumerated().map { index, message in
            guard index < previous.count, previous[index].role == message.role else { return message }
            var reconciled = message
            reconciled.id = previous[index].id
            let priorBlocks = previous[index].blocks
            reconciled.blocks = message.blocks.enumerated().map { blockIndex, block in
                guard blockIndex < priorBlocks.count,
                      block.toolCall == nil,
                      priorBlocks[blockIndex].toolCall == nil else { return block }
                var carried = block
                carried.id = priorBlocks[blockIndex].id
                return carried
            }
            return reconciled
        }
    }
}

// MARK: - Attachment Info

public struct AttachmentInfo: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let type: String

    public var isImage: Bool { type == "image" }

    public init(name: String, path: String, type: String) {
        self.name = name
        self.path = path
        self.type = type
    }
}

// MARK: - Role

public enum Role: String, Codable, Sendable {
    case user
    case assistant
}

// MARK: - Tool Call

public struct ToolCall: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public var input: [String: JSONValue]
    public var result: String?
    public var isError: Bool

    public var hasNonEmptyResult: Bool {
        result.map { !$0.isEmpty } ?? false
    }

    /// Tool names that must stay in the message block even without a result —
    /// either because the result would be empty by design, or because the UI
    /// needs to render them before the user/CLI produces a result.
    public static let keepAlwaysNames: Set<String> = [
        "agent", "edit", "multiedit", "multi_edit", "write", "askuserquestion"
    ]

    public var isKeepAlways: Bool {
        Self.keepAlwaysNames.contains(name.lowercased())
    }

    public init(
        id: String,
        name: String,
        input: [String: JSONValue] = [:],
        result: String? = nil,
        isError: Bool = false
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.result = result
        self.isError = isError
    }
}
