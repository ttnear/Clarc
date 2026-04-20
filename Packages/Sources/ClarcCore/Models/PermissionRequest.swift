import Foundation

// MARK: - Permission Request

public struct PermissionRequest: Identifiable, Sendable {
    public let id: String
    public let toolName: String
    public let toolInput: [String: JSONValue]
    public let runToken: String
    /// Snapshotted at hook receipt so the modal isn't affected by later picker changes.
    public let streamPermissionMode: PermissionMode?

    public init(
        id: String,
        toolName: String,
        toolInput: [String: JSONValue],
        runToken: String,
        streamPermissionMode: PermissionMode? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.toolInput = toolInput
        self.runToken = runToken
        self.streamPermissionMode = streamPermissionMode
    }
}

// MARK: - Tool Category

public enum ToolCategory: Sendable {
    case readOnly
    case fileModification
    case execution
    case mcp
    case unknown

    public init(toolName: String) {
        switch toolName.lowercased() {
        case "read", "glob", "grep", "list", "search":
            self = .readOnly
        case "edit", "write", "multiedit", "multi_edit":
            self = .fileModification
        case "bash", "execute":
            self = .execution
        default:
            if toolName.lowercased().hasPrefix("mcp__") {
                self = .mcp
            } else {
                self = .unknown
            }
        }
    }

    public var isTransient: Bool {
        self == .readOnly || self == .execution
    }

    public var sfSymbol: String {
        switch self {
        case .readOnly: return "doc.text"
        case .fileModification: return "pencil"
        case .execution: return "terminal"
        case .mcp: return "puzzlepiece.extension"
        case .unknown: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Permission Decision

public enum PermissionDecision: Sendable, Equatable {
    case allow
    case deny
    /// In-memory per-tool allow for the current session (Edit/Write/MultiEdit/mcp__*).
    case allowSessionTool
    /// Per-project persistent allow for an exact Bash command string.
    case allowAlwaysCommand(command: String)
}
