import Foundation
import SwiftUI

// MARK: - InspectorTab

public enum InspectorTab: String, CaseIterable {
    case memo = "Memo"
    case terminal = "Terminal"

    public var icon: String {
        switch self {
        case .terminal: "apple.terminal"
        case .memo: "note.text"
        }
    }
}

// MARK: - QueuedMessage

public struct QueuedMessage: Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public var attachments: [Attachment]

    public init(text: String, attachments: [Attachment]) {
        self.id = UUID()
        self.text = text
        self.attachments = attachments
    }
}

/// Per-window independent UI/session state. Does not own services or shared data.
@Observable
@MainActor
public final class WindowState {

    // MARK: - Window Identity

    public let id = UUID()
    public var newSessionKey: String { "__new_\(id.uuidString)__" }

    // MARK: - Project / Session Selection

    public var selectedProject: Project?
    public var currentSessionId: String?

    // MARK: - Placeholder Tracking

    public private(set) var pendingPlaceholderIds: Set<String> = []

    // MARK: - Input

    public var inputText = ""
    public var attachments: [Attachment] = []
    public var draftTexts: [String: String] = [:]
    public var draftQueues: [String: [QueuedMessage]] = [:]

    // MARK: - Message Queue

    public var messageQueue: [QueuedMessage] = []

    public func enqueueMessage(text: String, attachments: [Attachment]) {
        messageQueue.append(QueuedMessage(text: text, attachments: attachments))
    }

    public func dequeueMessage(id: UUID) {
        messageQueue.removeAll { $0.id == id }
    }

    public func dequeueNext() -> QueuedMessage? {
        guard !messageQueue.isEmpty else { return nil }
        return messageQueue.removeFirst()
    }

    // MARK: - Permission Queue

    public var pendingPermissions: [PermissionRequest] = []

    // MARK: - UI State

    public var interactiveTerminal: InteractiveTerminalState?
    public var showInspector: Bool = false
    public var inspectorTab: InspectorTab = .memo
    public var inspectorFile: PreviewFile?
    public var diffFile: PreviewFile?
    public var showMarketplace = false
    public var showModelPicker = false
    public var showEffortPicker = false
    /// Per-session model override. When set, this model is used instead of the global default.
    /// Cleared when a new chat is started or a different session is selected.
    public var sessionModel: String?
    /// Per-session effort override. When set, passed as --effort to the CLI.
    /// Cleared when a new chat is started or a different session is selected.
    public var sessionEffort: String?
    /// Per-session permission mode override. When set, overrides the global permissionMode.
    /// Cleared when a new chat is started or a different session is selected.
    public var sessionPermissionMode: PermissionMode?
    public var requestInputFocus = false
    public var registryVersion = 0
    public var isInitialized = false
    public var errorMessage: String?
    public var showError = false

    // MARK: - Window Kind

    public var isProjectWindow = false

    // MARK: - Focus Mode

    public var focusMode: Bool = false

    // MARK: - Session Switch Task

    private var sessionSwitchTask: Task<Void, Never>?

    public init() {}

    // MARK: - Internal Helpers

    public func insertPendingPlaceholder(_ id: String) {
        pendingPlaceholderIds.insert(id)
    }

    public func removePendingPlaceholder(_ id: String) {
        pendingPlaceholderIds.remove(id)
    }

    public func cancelSessionSwitchTask() {
        sessionSwitchTask?.cancel()
    }

    public func setSessionSwitchTask(_ task: Task<Void, Never>) {
        sessionSwitchTask = task
    }

    // MARK: - Attachment Helpers

    public func addAttachment(_ attachment: Attachment) {
        attachments.append(attachment)
    }

    public func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }
}
