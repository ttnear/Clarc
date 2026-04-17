import Foundation
import ClarcCore
import SwiftUI
import os
import ClarcChatKit

// MARK: - Per-Session Stream State

/// Encapsulates all independent state per session.
/// Stored in the `AppState.sessionStates` dictionary keyed by session ID.
struct SessionStreamState {
    // Messages
    var messages: [ChatMessage] = []

    // Streaming
    var isStreaming = false
    var isThinking = false
    var needsNewMessage = false   // After receiving .user(tool result), the next block starts a new ChatMessage
    var activeStreamId: UUID?
    var streamingStartDate: Date?
    var streamTask: Task<Void, Never>?

    // Text delta buffer (50ms throttle)
    var textDeltaBuffer = ""
    var pendingToolResults: [(toolUseId: String, content: String, isError: Bool)] = []
    var flushTask: Task<Void, Never>?

    // tool_use input streaming buffer
    var activeToolId: String?           // tool_use id currently receiving input_json_delta
    var activeToolInputBuffer: String = ""  // accumulator for input_json_delta

    // Per-session model override (persisted in memory across session switches)
    var model: String?

    // Session statistics
    var costUsd: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var durationMs: Double = 0
    var turns: Int = 0
    var lastTurnContextUsedPercentage: Double?
    var activeModelName: String?
}


@Observable
@MainActor
final class AppState {

    // MARK: - Logger

    private let logger = Logger(subsystem: "com.claudework", category: "AppState")

    // MARK: - Projects (shared)

    var projects: [Project] = []

    // MARK: - Per-Session State (shared — managed independently by session ID regardless of window)

    /// Independent state for all active sessions. Key: sessionId
    /// `internal` (not private) — read access required from WindowState / extensions
    var sessionStates: [String: SessionStreamState] = [:]

    // MARK: - Session Summaries (shared — lightweight metadata for all projects)

    var allSessionSummaries: [ChatSession.Summary] = []

    // MARK: - Theme

    var selectedTheme: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "selectedTheme") ?? "") ?? .claude {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
            ThemeStore.shared.current = selectedTheme
            themeRevision += 1
        }
    }
    /// Incrementing causes NavigationSplitView to rebuild and immediately apply theme colors
    var themeRevision: Int = 0

    // MARK: - Model

    static let availableModels = ["default", "best", "opus", "opus[1m]", "opusplan", "sonnet", "sonnet[1m]", "haiku"]

    static func modelDisplayName(_ model: String) -> String {
        switch model {
        case "default": return "Default"
        case "best": return "Best"
        case "opus": return "Opus"
        case "opus[1m]": return "Opus 1M"
        case "opusplan": return "Opus Plan"
        case "sonnet": return "Sonnet"
        case "sonnet[1m]": return "Sonnet 1M"
        case "haiku": return "Haiku"
        default: return model.capitalized
        }
    }

    static func modelDescription(_ model: String) -> String {
        let key: String
        switch model {
        case "default":   key = "model.desc.default"
        case "best":      key = "model.desc.best"
        case "opus":      key = "model.desc.opus"
        case "opus[1m]":  key = "model.desc.opus1m"
        case "opusplan":  key = "model.desc.opusplan"
        case "sonnet":    key = "model.desc.sonnet"
        case "sonnet[1m]": key = "model.desc.sonnet1m"
        case "haiku":     key = "model.desc.haiku"
        default: return ""
        }
        return NSLocalizedString(key, comment: "")
    }
    static let availableEfforts = ["low", "medium", "high", "xhigh", "max"]
    var selectedModel: String = UserDefaults.standard.string(forKey: "selectedModel") ?? "opus" {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    // MARK: - Notifications

    var notificationsEnabled: Bool = (UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    /// Pending session to navigate to when a project window opens or is already open.
    /// Keyed by projectId; consumed once applied.
    var pendingNotificationSession: [UUID: String] = [:]

    /// Sets the model for the current session and persists it in the session state.
    func setSessionModel(_ model: String, in window: WindowState) {
        window.sessionModel = model
        let key = window.currentSessionId ?? window.newSessionKey
        updateState(key) { $0.model = model }
    }

    func modelDisplayName(for model: String, in window: WindowState) -> String {
        if let active = activeModelName(in: window) {
            return active
        }
        return Self.modelDisplayName(model)
    }

    static func formatModelId(_ raw: String) -> String {
        let lower = raw.lowercased()
        let family: String
        if lower.contains("opus") { family = "Opus" }
        else if lower.contains("sonnet") { family = "Sonnet" }
        else if lower.contains("haiku") { family = "Haiku" }
        else { return raw }

        let parts = lower.components(separatedBy: CharacterSet(charactersIn: "-"))
        if let idx = parts.firstIndex(where: { $0 == family.lowercased() }),
           idx + 1 < parts.count {
            let ver = parts[(idx + 1)...].prefix(2).filter { $0.allSatisfy(\.isNumber) }
            if !ver.isEmpty { return "\(family) \(ver.joined(separator: "."))" }
        }
        return family
    }

    // MARK: - Permissions

    var permissionMode: PermissionMode = .default

    // MARK: - GitHub

    var isLoggedIn = false
    var gitHubUser: GitHubUser?
    var repos: [GitHubRepo] = []

    // MARK: - CLI Version

    var claudeVersion: String?

    // MARK: - Marketplace

    var marketplaceCatalog: [MarketplacePlugin] = []
    var marketplaceLoading = false
    var marketplaceInstalledNames: Set<String> = []
    var marketplacePluginStates: [String: PluginInstallStatus] = [:]

    // MARK: - Onboarding

    var claudeInstalled = false
    var onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")

    // MARK: - Services

    let claude = ClaudeService()
    let github = GitHubService()
    let permission = PermissionServer()
    let persistence = PersistenceService()
    let marketplace = MarketplaceService()

    // MARK: - Private State

    // MARK: - Window-Scoped Session State Accessors

    func streamState(in window: WindowState) -> SessionStreamState {
        sessionStates[window.currentSessionId ?? window.newSessionKey] ?? SessionStreamState()
    }

    func messages(in window: WindowState) -> [ChatMessage] {
        streamState(in: window).messages
    }

    func isStreaming(in window: WindowState) -> Bool {
        streamState(in: window).isStreaming
    }

    func isThinking(in window: WindowState) -> Bool {
        streamState(in: window).isThinking
    }

    func streamingStartDate(in window: WindowState) -> Date? {
        streamState(in: window).streamingStartDate
    }

    func activeModelName(in window: WindowState) -> String? {
        streamState(in: window).activeModelName
    }

    func lastTurnContextUsedPercentage(in window: WindowState) -> Double? {
        streamState(in: window).lastTurnContextUsedPercentage
    }

    func sessionCostUsd(in window: WindowState) -> Double {
        streamState(in: window).costUsd
    }

    func sessionTurns(in window: WindowState) -> Int {
        streamState(in: window).turns
    }

    func sessionInputTokens(in window: WindowState) -> Int {
        streamState(in: window).inputTokens
    }

    func sessionOutputTokens(in window: WindowState) -> Int {
        streamState(in: window).outputTokens
    }

    func sessionCacheCreationTokens(in window: WindowState) -> Int {
        streamState(in: window).cacheCreationTokens
    }

    func sessionCacheReadTokens(in window: WindowState) -> Int {
        streamState(in: window).cacheReadTokens
    }

    func sessionDurationMs(in window: WindowState) -> Double {
        streamState(in: window).durationMs
    }

    func currentSession(in window: WindowState) -> ChatSession? {
        guard let id = window.currentSessionId else { return nil }
        guard let summary = allSessionSummaries.first(where: { $0.id == id }) else { return nil }
        return summary.makeSession()
    }

    /// Check whether a given session is streaming in the background (not foreground) of this window
    func isBackgroundStreaming(_ sessionId: String, in window: WindowState) -> Bool {
        guard sessionId != (window.currentSessionId ?? window.newSessionKey) else { return false }
        return sessionStates[sessionId]?.isStreaming ?? false
    }

    /// Returns the set of session IDs currently streaming in the background of this window.
    func backgroundStreamingSessionIds(in window: WindowState) -> Set<String> {
        let currentKey = window.currentSessionId ?? window.newSessionKey
        return Set(sessionStates.compactMap { key, state in
            (state.isStreaming && key != currentKey) ? key : nil
        })
    }

    // MARK: - Initialization

    /// Once per app launch — start services and load shared data
    func initialize() async {
        ThemeStore.shared.current = selectedTheme

        let binary = await claude.findClaudeBinary()
        claudeInstalled = binary != nil

        if binary != nil {
            do {
                claudeVersion = try await claude.checkVersion()
            } catch {
                logger.warning("Failed to fetch Claude CLI version: \(error.localizedDescription)")
            }
        }

        projects = await persistence.loadProjects()

        if let cachedUser = await persistence.loadGitHubUser() {
            gitHubUser = cachedUser
            isLoggedIn = true
            _ = await github.loadToken()
        }

        // Load all session summaries (excluding message bodies)
        allSessionSummaries = await persistence.loadAllSessionSummaries()

        if claudeInstalled && !onboardingCompleted {
            onboardingCompleted = true
            UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        }

        permissionMode = Self.readPermissionModeFromSettings()

        do {
            try await permission.start()
        } catch {
            logger.error("Failed to start permission server: \(error.localizedDescription)")
        }

        // Permission request routing is handled per-window in initializeWindow's listener.
    }

    /// Per-window initialization — restore selected project and load session history
    func initializeWindow(_ window: WindowState, selectingProjectId: UUID? = nil) async {
        // Subscribe to permission broadcasts — appends requests to this window's pendingPermissions.
        // subscribe() issues a window-exclusive stream, so events are not stolen across multiple windows.
        Task { [weak self] in
            guard let self else { return }
            let (_, stream) = await self.permission.subscribe()
            for await request in stream {
                guard !Task.isCancelled else { break }
                if !window.pendingPermissions.contains(where: { $0.id == request.id }) {
                    window.pendingPermissions.append(request)
                }
            }
        }

        if let projectId = selectingProjectId,
           let project = projects.first(where: { $0.id == projectId }) {
            selectProject(project, in: window)
        } else if let savedId = UserDefaults.standard.string(forKey: "selectedProjectId"),
                  let uuid = UUID(uuidString: savedId),
                  let project = projects.first(where: { $0.id == uuid }) {
            selectProject(project, in: window)
        } else if let first = projects.first {
            selectProject(first, in: window)
        }

        window.isInitialized = true
    }

    // MARK: - ChatBridge Setup

    /// Configures a `ChatBridge`'s action handlers and starts an observation loop that keeps
    /// the bridge's state properties in sync with the underlying `sessionStates`.
    func setupChatBridge(_ bridge: ChatBridge, for window: WindowState) {
        bridge.sendHandler = { [weak self, weak window] in
            guard let self, let window else { return }
            await self.send(in: window)
        }
        bridge.cancelStreamingHandler = { [weak self, weak window] in
            guard let self, let window else { return }
            await self.cancelStreaming(in: window)
        }
        bridge.sendSlashCommandHandler = { [weak self, weak window] command in
            guard let self, let window else { return }
            await self.sendSlashCommand(command, in: window)
        }
        bridge.runTerminalCommandHandler = { [weak self, weak window] command in
            guard let self, let window else { return }
            await self.runTerminalCommand(command, in: window)
        }
        bridge.editAndResendHandler = { [weak self, weak window] messageId, newContent in
            guard let self, let window else { return }
            await self.editAndResend(messageId: messageId, newContent: newContent, in: window)
        }
        bridge.fetchRateLimitHandler = {
            await RateLimitService.shared.fetchUsage()
        }

        startBridgeObservation(bridge, for: window)
    }

    /// Runs a reactive observation loop: reads AppState + WindowState properties into the bridge,
    /// then re-registers after each change. Stops when the bridge or window is deallocated.
    private func startBridgeObservation(_ bridge: ChatBridge, for window: WindowState) {
        func observe() {
            withObservationTracking {
                let state = streamState(in: window)
                bridge.messages = state.messages
                bridge.isStreaming = state.isStreaming
                bridge.isThinking = state.isThinking
                bridge.streamingStartDate = state.streamingStartDate
                bridge.lastTurnContextUsedPercentage = state.lastTurnContextUsedPercentage
                bridge.modelDisplayName = modelDisplayName(for: window.sessionModel ?? selectedModel, in: window)
                bridge.sessionStats = ChatSessionStats(
                    costUsd: state.costUsd,
                    inputTokens: state.inputTokens,
                    outputTokens: state.outputTokens,
                    cacheCreationTokens: state.cacheCreationTokens,
                    cacheReadTokens: state.cacheReadTokens,
                    durationMs: state.durationMs,
                    turns: state.turns
                )
            } onChange: {
                Task { @MainActor in observe() }
            }
        }
        Task { @MainActor in observe() }
    }

    // MARK: - Edit & Resend

    func editAndResend(messageId: UUID, newContent: String, in window: WindowState) async {
        let key = window.currentSessionId ?? window.newSessionKey
        var snapshot = sessionStates[key]?.messages ?? []
        guard let index = snapshot.firstIndex(where: { $0.id == messageId }),
              snapshot[index].role == .user else { return }

        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isStreaming(in: window) {
            await cancelStreaming(in: window)
        }

        snapshot.removeSubrange((index + 1)...)
        snapshot[index].content = trimmed

        window.currentSessionId = nil
        sessionStates.removeValue(forKey: window.newSessionKey)
        await sendPrompt(trimmed, skipAppendingUserMessage: true, initialMessages: snapshot, in: window)
    }

    // MARK: - Send Message

    func send(in window: WindowState) async {
        let prompt = window.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentAttachments = window.attachments
        guard !prompt.isEmpty || !currentAttachments.isEmpty else { return }

        if currentAttachments.isEmpty, await handleNativeSlashCommand(prompt, in: window) {
            window.inputText = ""
            return
        }

        window.inputText = ""
        window.draftTexts.removeValue(forKey: window.currentSessionId ?? "new")
        window.attachments = []

        let (resolvedAttachments, tempFilePaths) = AttachmentFactory.resolvingClipboardImages(currentAttachments)
        let fullPrompt = buildPromptWithAttachments(prompt, attachments: resolvedAttachments)

        await sendPrompt(fullPrompt, displayText: prompt, attachments: resolvedAttachments,
                         tempFilePaths: tempFilePaths, in: window)
    }

    /// Slash commands handled natively. Returns true if handled.
    private func handleNativeSlashCommand(_ text: String, in window: WindowState) async -> Bool {
        guard text.hasPrefix("/") else { return false }
        let parts = text.split(separator: " ", maxSplits: 1)
        let command = parts.first.map { String($0.dropFirst()) } ?? ""

        switch command {
        case "clear":
            startNewChat(in: window)
            return true
        case "model":
            if parts.count > 1 {
                let arg = String(parts[1]).trimmingCharacters(in: .whitespaces).lowercased()
                let matched = Self.availableModels.first { $0 == arg } ?? Self.availableModels.first { arg.contains($0) } ?? arg
                setSessionModel(matched, in: window)
            } else {
                window.showModelPicker = true
            }
            return true
        case "effort":
            if parts.count > 1 {
                let arg = String(parts[1]).trimmingCharacters(in: .whitespaces).lowercased()
                window.sessionEffort = Self.availableEfforts.contains(arg) ? arg : nil
            } else {
                window.showEffortPicker = true
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Send Slash Command

    func sendSlashCommand(_ command: String, in window: WindowState) async {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if await handleNativeSlashCommand(trimmed, in: window) { return }

        let baseName = trimmed.split(separator: " ", maxSplits: 1)
            .first.map { String($0.dropFirst()) } ?? ""

        let isInteractive = SlashCommandRegistry.commands
            .first { $0.name == baseName }?.isInteractive ?? false

        if isInteractive {
            await sendInteractiveCommand(trimmed, in: window)
        } else {
            await sendPrompt(trimmed, in: window)
        }
    }

    private func sendInteractiveCommand(_ command: String, in window: WindowState) async {
        let title = command.trimmingCharacters(in: .whitespaces)
        await launchTerminal(title: title, initialCommand: command, in: window)
    }

    func runTerminalCommand(_ command: String, in window: WindowState) async {
        let title = command.trimmingCharacters(in: .whitespaces)
        await launchTerminal(title: title, initialCommand: command, rawShell: true, in: window)
    }

    func openTerminal(in window: WindowState) async {
        if window.showInspector && window.inspectorTab == .terminal {
            window.showInspector = false
        } else {
            window.inspectorTab = .terminal
            window.showInspector = true
        }
    }

    private func launchTerminal(
        title: String,
        initialCommand: String? = nil,
        reportToChat: Bool = true,
        rawShell: Bool = false,
        in window: WindowState
    ) async {
        guard let project = window.selectedProject else {
            handleError(AppError.noProjectSelected, in: window)
            return
        }

        let arguments: [String]
        if rawShell {
            arguments = ["-il"]
        } else {
            guard let binary = await claude.findClaudeBinary() else {
                handleError(AppError.claudeNotInstalled, in: window)
                return
            }
            arguments = ["-ilc", binary]
        }

        window.interactiveTerminal = InteractiveTerminalState(
            title: title,
            executable: "/bin/zsh",
            arguments: arguments,
            currentDirectory: project.path,
            initialCommand: initialCommand,
            reportToChat: reportToChat
        )
    }

    func dismissInteractiveTerminal(exitCode: Int32, in window: WindowState) {
        guard let terminal = window.interactiveTerminal else { return }
        window.interactiveTerminal = nil

        guard terminal.reportToChat else { return }

        let key = window.currentSessionId ?? window.newSessionKey
        updateState(key) { state in
            state.messages.append(ChatMessage(role: .user, content: terminal.title))
            let result = exitCode == 0 ? "Done" : "exit code: \(exitCode)"
            let toolCall = ToolCall(
                id: UUID().uuidString,
                name: InteractiveTerminalState.toolName,
                input: ["command": .string(terminal.title)],
                result: result,
                isError: exitCode != 0
            )
            state.messages.append(ChatMessage(role: .assistant, blocks: [.toolCall(toolCall)]))
        }
        Task { await saveCurrentSession(in: window) }
    }

    // MARK: - Shared Send Logic

    private func sendPrompt(
        _ prompt: String,
        displayText: String? = nil,
        attachments: [Attachment] = [],
        skipAppendingUserMessage: Bool = false,
        initialMessages: [ChatMessage]? = nil,
        tempFilePaths: [String] = [],
        in window: WindowState
    ) async {
        guard let project = window.selectedProject else {
            handleError(AppError.noProjectSelected, in: window)
            return
        }

        if isStreaming(in: window) {
            await cancelStreaming(in: window)
        }

        let streamId = UUID()
        let isNewSession = window.currentSessionId == nil
        let isPending = window.currentSessionId.map { window.pendingPlaceholderIds.contains($0) } ?? false
        let cliSessionId: String? = (isNewSession || isPending) ? nil : window.currentSessionId

        if isNewSession {
            let tempId = "pending-\(streamId.uuidString)"
            window.currentSessionId = tempId
            window.insertPendingPlaceholder(tempId)
            if let model = window.sessionModel {
                updateState(tempId) { $0.model = model }
            }
        }

        let sessionKey = window.currentSessionId!

        // Apply initialMessages if provided
        if let initial = initialMessages {
            updateState(sessionKey) { $0.messages = initial }
        }

        if !skipAppendingUserMessage {
            updateState(sessionKey) { state in
                state.messages.append(ChatMessage(
                    role: .user,
                    content: displayText ?? prompt,
                    attachments: attachments
                ))
            }
        }

        updateState(sessionKey) { state in
            state.isStreaming = true
            state.activeStreamId = streamId
            state.streamingStartDate = Date()
        }
        await permission.refreshRunToken()

        var hookSettingsPath: String?
        if !permissionMode.skipsHookPipeline {
            do {
                hookSettingsPath = try await permission.writeHookSettingsFile()
            } catch {
                logger.error("Failed to write hook settings: \(error.localizedDescription)")
            }
        }

        if isNewSession {
            let titleText = prompt.count > 50 ? String(prompt.prefix(50)) + "..." : prompt
            let placeholder = ChatSession(id: sessionKey, projectId: project.id, title: titleText, messages: [])
            allSessionSummaries.insert(placeholder.summary, at: 0)
        } else {
            await saveCurrentSession(in: window)
        }

        let currentPermissionMode = permissionMode
        let task = Task { [weak self, window] in
            guard let self else { return }
            await self.processStream(
                streamId: streamId,
                prompt: prompt,
                cwd: project.path,
                cliSessionId: cliSessionId,
                internalSessionKey: sessionKey,
                model: window.sessionModel ?? self.selectedModel,
                effort: window.sessionEffort,
                hookSettingsPath: hookSettingsPath,
                permissionMode: currentPermissionMode,
                projectId: project.id,
                window: window
            )
            for path in tempFilePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        sessionStates[sessionKey, default: SessionStreamState()].streamTask = task
    }

    // MARK: - Stream Processing

    private func stateForSession(_ key: String) -> SessionStreamState {
        sessionStates[key] ?? SessionStreamState()
    }

    private func updateState(_ key: String, _ mutate: (inout SessionStreamState) -> Void) {
        guard var state = sessionStates[key] else {
            var fresh = SessionStreamState()
            mutate(&fresh)
            sessionStates[key] = fresh
            return
        }
        mutate(&state)
        sessionStates[key] = state
    }

    private func finalizeStreamSession(
        for sessionKey: String,
        extraMutations: ((inout SessionStreamState) -> Void)? = nil
    ) {
        flushPendingUpdates(for: sessionKey)
        updateState(sessionKey) { state in
            state.flushTask?.cancel()
            state.flushTask = nil
            state.isStreaming = false
            state.isThinking = false
            state.needsNewMessage = false
            state.activeStreamId = nil
            state.streamTask = nil
            state.activeToolId = nil
            state.activeToolInputBuffer = ""
            state.textDeltaBuffer = ""
            state.pendingToolResults.removeAll()

            extraMutations?(&state)

            if let idx = state.messages.indices.reversed().first(where: {
                state.messages[$0].role == .assistant && state.messages[$0].isStreaming
            }) {
                state.messages[idx].isStreaming = false
                state.messages[idx].isResponseComplete = true
                state.messages[idx].finalizeToolCalls()
                if let start = state.streamingStartDate {
                    state.messages[idx].duration = Date().timeIntervalSince(start)
                }
            }
            state.streamingStartDate = nil
        }
    }

    private func processStream(
        streamId: UUID,
        prompt: String,
        cwd: String,
        cliSessionId: String?,
        internalSessionKey: String,
        model: String?,
        effort: String? = nil,
        hookSettingsPath: String?,
        permissionMode: PermissionMode = .default,
        projectId: UUID,
        window: WindowState
    ) async {
        let streamStart = Date()
        logger.info("[Stream:UI] starting processStream (cli=\(cliSessionId ?? "new"), key=\(internalSessionKey))")

        var sessionKey = internalSessionKey

        let stream = await claude.send(
            streamId: streamId,
            prompt: prompt,
            cwd: cwd,
            sessionId: cliSessionId,
            model: model,
            effort: effort,
            hookSettingsPath: hookSettingsPath,
            permissionMode: permissionMode
        )

        startFlushTimer(for: sessionKey)

        var eventCount = 0
        var lastEventTime = Date()

        do {
            for await event in stream {
                eventCount += 1
                let gap = Date().timeIntervalSince(lastEventTime)
                lastEventTime = Date()

                guard !Task.isCancelled else {
                    logger.info("[Stream:UI] task cancelled after \(eventCount) events")
                    break
                }

                let ownsSession = stateForSession(sessionKey).activeStreamId == streamId

                if !ownsSession {
                    if case .result(let resultEvent) = event {
                        logger.info("[Stream:UI] event #\(eventCount) .result received after losing ownership — saving to disk")
                        if sessionKey != resultEvent.sessionId {
                            if let state = sessionStates.removeValue(forKey: sessionKey) {
                                sessionStates[resultEvent.sessionId] = state
                            }
                            sessionKey = resultEvent.sessionId
                        }
                        let msgs = stateForSession(sessionKey).messages
                        if !msgs.isEmpty {
                            await saveSession(sessionId: resultEvent.sessionId, projectId: projectId, messages: msgs)
                        }
                    } else {
                        logger.debug("[Stream:UI] event #\(eventCount) — stream \(streamId) no longer owns session \(sessionKey), skipping")
                    }
                    continue
                }

                switch event {
                case .system(let systemEvent):
                    logger.info("[Stream:UI] event #\(eventCount) .system (gap=\(String(format: "%.1f", gap))s)")
                    if let model = systemEvent.model {
                        updateState(sessionKey) { $0.activeModelName = model }
                    }
                    if let sid = systemEvent.sessionId {
                        if sessionKey != sid {
                            let oldKey = sessionKey
                            if let state = sessionStates.removeValue(forKey: oldKey) {
                                sessionStates[sid] = state
                            }
                            sessionKey = sid
                            startFlushTimer(for: sid)

                            // If this is the foreground session, also update window.currentSessionId
                            let isFg = (window.currentSessionId ?? window.newSessionKey) == oldKey || window.currentSessionId == nil
                            if isFg { window.currentSessionId = sid }
                        }

                        let expectedPlaceholder = "pending-\(streamId.uuidString)"
                        if window.pendingPlaceholderIds.contains(expectedPlaceholder),
                           let idx = allSessionSummaries.firstIndex(where: { $0.id == expectedPlaceholder }) {
                            let old = allSessionSummaries[idx]
                            let replacement = ChatSession(
                                id: sid,
                                projectId: old.projectId,
                                title: old.title,
                                messages: [],
                                createdAt: old.createdAt,
                                updatedAt: Date()
                            )
                            allSessionSummaries.removeAll { $0.id == expectedPlaceholder || $0.id == sid }
                            allSessionSummaries.insert(replacement.summary, at: 0)
                            window.removePendingPlaceholder(expectedPlaceholder)
                        } else {
                            if window.pendingPlaceholderIds.contains(expectedPlaceholder) {
                                window.removePendingPlaceholder(expectedPlaceholder)
                                allSessionSummaries.removeAll { $0.id == expectedPlaceholder }
                            }

                            // A retry reuses the same pending session key (oldKey) with a new streamId,
                            // so expectedPlaceholder won't match oldKey. Clean up the stale placeholder
                            // here to prevent the old entry from persisting as a duplicate in history.
                            let oldKey = sessionKey == sid ? internalSessionKey : sessionKey
                            if oldKey != expectedPlaceholder && window.pendingPlaceholderIds.contains(oldKey) {
                                allSessionSummaries.removeAll { $0.id == oldKey }
                                window.removePendingPlaceholder(oldKey)
                            }

                            if !allSessionSummaries.contains(where: { $0.id == sid }),
                               let project = projects.first(where: { $0.id == projectId }) {
                                let msgs = stateForSession(sessionKey).messages
                                let firstUserContent = msgs.first(where: { $0.role == .user })?.content
                                let title: String
                                if let content = firstUserContent {
                                    title = content.count > 50 ? String(content.prefix(50)) + "..." : content
                                } else {
                                    title = "New Session"
                                }
                                let newSession = ChatSession(id: sid, projectId: project.id, title: title, messages: [], updatedAt: Date())
                                allSessionSummaries.insert(newSession.summary, at: 0)
                            }
                        }
                    }

                    if systemEvent.subtype == "compact_boundary" {
                        updateState(sessionKey) { state in
                            state.messages.append(ChatMessage(role: .assistant, content: "Previous conversation has been compacted", isCompactBoundary: true))
                        }
                    }

                case .assistant(let assistantMessage):
                    logger.debug("[Stream:UI] event #\(eventCount) .assistant (gap=\(String(format: "%.1f", gap))s, blocks=\(assistantMessage.content.count))")
                    // Extract text only when no text_delta has been received in the current turn.
                    // Normally content_block_delta(text_delta) is the primary path, so this branch rarely executes.
                    updateState(sessionKey) { state in
                        guard state.textDeltaBuffer.isEmpty else { return }
                        let afterLastUser = (state.messages.lastIndex(where: { $0.role == .user }).map { $0 + 1 }) ?? 0
                        let hasStreamedText = state.messages.suffix(from: afterLastUser).contains {
                            $0.role == .assistant && $0.blocks.contains(where: \.isText)
                        }
                        guard !hasStreamedText else { return }
                        for block in assistantMessage.content {
                            if case .text(let text) = block, !text.isEmpty {
                                state.textDeltaBuffer += text
                            }
                        }
                    }

                case .user(let userMessage):
                    logger.debug("[Stream:UI] event #\(eventCount) .user (gap=\(String(format: "%.1f", gap))s, toolUseId=\(userMessage.toolUseId ?? "none"))")
                    updateState(sessionKey) { state in
                        guard let toolUseId = userMessage.toolUseId else { return }
                        state.pendingToolResults.append((toolUseId, userMessage.content, userMessage.isError))
                        state.needsNewMessage = true
                    }

                case .result(let resultEvent):
                    logger.info("[Stream:UI] event #\(eventCount) .result (gap=\(String(format: "%.1f", gap))s, isError=\(resultEvent.isError), session=\(resultEvent.sessionId))")

                    if sessionKey != resultEvent.sessionId {
                        if let state = sessionStates.removeValue(forKey: sessionKey) {
                            sessionStates[resultEvent.sessionId] = state
                        }
                        sessionKey = resultEvent.sessionId
                    }

                    finalizeStreamSession(for: sessionKey) { state in
                        if let cost = resultEvent.totalCostUsd { state.costUsd = cost }
                        if let duration = resultEvent.durationMs { state.durationMs += duration }
                        if let turns = resultEvent.totalTurns { state.turns += turns }
                        if let usage = resultEvent.usage {
                            state.inputTokens += usage.inputTokens
                            state.outputTokens += usage.outputTokens
                            state.cacheCreationTokens += usage.cacheCreationInputTokens
                            state.cacheReadTokens += usage.cacheReadInputTokens
                        }
                    }

                    let isFg = (window.currentSessionId ?? window.newSessionKey) == sessionKey
                    if isFg {
                        window.currentSessionId = resultEvent.sessionId
                        if resultEvent.isError {
                            addErrorMessage("Claude returned an error.", in: window)
                        }
                    }

                    await saveSession(
                        sessionId: resultEvent.sessionId,
                        projectId: projectId,
                        messages: stateForSession(sessionKey).messages
                    )

                    if !resultEvent.isError {
                        let sid = resultEvent.sessionId
                        let key = sessionKey
                        let cwdCapture = cwd
                        Task { [weak self] in
                            guard let self else { return }
                            if let pct = await claude.fetchContextPercentage(sessionId: sid, cwd: cwdCapture) {
                                updateState(key) { $0.lastTurnContextUsedPercentage = pct }
                            }
                        }

                        if notificationsEnabled && !NSApp.isActive {
                            let title = allSessionSummaries.first(where: { $0.id == resultEvent.sessionId })?.title ?? "New Session"
                            let firstSentence = stateForSession(sessionKey).messages
                                .last(where: { $0.role == .assistant && !$0.isError })
                                .flatMap { msg -> String? in
                                    let text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !text.isEmpty else { return nil }
                                    let sentence = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? text
                                    return sentence.trimmingCharacters(in: .whitespaces)
                                } ?? ""
                            let pid = projectId
                            let sid = resultEvent.sessionId
                            Task { @MainActor in
                                await NotificationService.shared.postResponseComplete(title: title, body: firstSentence, projectId: pid, sessionId: sid)
                            }
                        }

                        // If this session is running in the background, automatically process any queued messages.
                        // Foreground sessions are handled by InputBarView via isStreaming onChange.
                        if !isFg {
                            await processBackgroundQueue(for: sessionKey, projectId: projectId, cwd: cwd, in: window)
                        }
                    }

                case .rateLimitEvent(let info):
                    logger.warning("[Stream:UI] event #\(eventCount) .rateLimitEvent (retrySec=\(info.retrySec ?? 0))")
                    if (window.currentSessionId ?? window.newSessionKey) == sessionKey,
                       let retry = info.retrySec, retry > 0 {
                        addErrorMessage("Rate limited. Retrying in \(Int(retry))s...", in: window)
                    }

                case .unknown(let raw):
                    if eventCount <= 5 || eventCount % 100 == 0 {
                        logger.debug("[Stream:UI] event #\(eventCount) .unknown (gap=\(String(format: "%.1f", gap))s, len=\(raw.count))")
                    }
                    handlePartialEvent(raw, for: sessionKey)
                }
            }

            let elapsed = Date().timeIntervalSince(streamStart)
            logger.info("[Stream:UI] stream ended after \(eventCount) events, \(String(format: "%.1f", elapsed))s total")

            if eventCount == 0 {
                let stderrOutput = await claude.consumeStderr(for: streamId)
                addErrorMessage("No response received", in: window)
                logger.error("[Stream:UI] no events received — appending error bubble. stderr=\(stderrOutput ?? "nil")")
            }

            let isStillOwner = stateForSession(sessionKey).activeStreamId == streamId
            let stillStreaming = stateForSession(sessionKey).isStreaming
            if stillStreaming && isStillOwner {
                logger.warning("[Stream:UI] isStreaming was still true at stream end — forcing cleanup")
                finalizeStreamSession(for: sessionKey)
                let msgs = stateForSession(sessionKey).messages
                if !msgs.isEmpty {
                    await saveSession(sessionId: sessionKey, projectId: projectId, messages: msgs)
                }
            } else if stillStreaming && !isStillOwner {
                let currentOwner = stateForSession(sessionKey).activeStreamId
                if currentOwner == nil {
                    logger.warning("[Stream:UI] stream \(streamId) ended — no active owner for session, forcing cleanup")
                    finalizeStreamSession(for: sessionKey)
                    let msgs = stateForSession(sessionKey).messages
                    if !msgs.isEmpty {
                        await saveSession(sessionId: sessionKey, projectId: projectId, messages: msgs)
                    }
                } else {
                    logger.info("[Stream:UI] stream \(streamId) ended but newer stream \(currentOwner!) owns session — skipping cleanup")
                }
            }
        }
    }

    // MARK: - Text Delta Throttle (50ms)

    private func startFlushTimer(for sessionKey: String) {
        stopFlushTimer(for: sessionKey)
        let capturedKey = sessionKey
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { break }
                self?.flushPendingUpdates(for: capturedKey)
            }
        }
        sessionStates[sessionKey, default: SessionStreamState()].flushTask = task
    }

    private func stopFlushTimer(for sessionKey: String) {
        sessionStates[sessionKey]?.flushTask?.cancel()
        sessionStates[sessionKey]?.flushTask = nil
    }

    private func flushPendingUpdates(for key: String) {
        guard var state = sessionStates[key] else { return }

        let hasText = !state.textDeltaBuffer.isEmpty
        let hasToolResults = !state.pendingToolResults.isEmpty

        guard hasText || hasToolResults else { return }

        func lastAssistantIdx() -> Int? {
            state.messages.indices.reversed().first { state.messages[$0].role == .assistant }
        }
        func lastStreamingAssistantIdx() -> Int? {
            state.messages.indices.reversed().first { state.messages[$0].role == .assistant && state.messages[$0].isStreaming }
        }

        // 1. Tool results — apply to the current streaming assistant message
        if hasToolResults {
            let results = state.pendingToolResults
            state.pendingToolResults.removeAll(keepingCapacity: true)
            if let idx = lastAssistantIdx() {
                for (toolUseId, content, isError) in results {
                    state.messages[idx].setToolResult(id: toolUseId, result: content, isError: isError)
                }
            }
        }

        // 2. Text delta flush
        if hasText {
            let buffered = state.textDeltaBuffer
            state.textDeltaBuffer = ""
            if let idx = lastStreamingAssistantIdx() {
                if state.needsNewMessage {
                    // New Claude turn after receiving tool result — start a new ChatMessage
                    state.messages[idx].isStreaming = false
                    state.messages[idx].finalizeToolCalls()
                    state.needsNewMessage = false
                    state.messages.append(ChatMessage(role: .assistant, content: buffered, isStreaming: true))
                } else {
                    state.messages[idx].appendText(buffered)
                }
            } else {
                state.messages.append(ChatMessage(role: .assistant, content: buffered, isStreaming: true))
            }
        }

        sessionStates[key] = state
    }

    // MARK: - Stream Event Handler

    private func handlePartialEvent(_ raw: String, for sessionKey: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let event: [String: Any]
        if let type = json["type"] as? String, type == "stream_event",
           let nested = json["event"] as? [String: Any] {
            event = nested
        } else {
            event = json
        }

        guard let eventType = event["type"] as? String else { return }

        switch eventType {
        case "content_block_start":
            guard let contentBlock = event["content_block"] as? [String: Any],
                  let blockType = contentBlock["type"] as? String else { return }

            if blockType == "tool_use" {
                guard let id = contentBlock["id"] as? String,
                      let name = contentBlock["name"] as? String else { return }
                let toolCall = ToolCall(id: id, name: name, input: [:])
                // Flush the text buffer first so text blocks are committed before tools
                flushPendingUpdates(for: sessionKey)
                updateState(sessionKey) { state in
                    state.isThinking = false
                    // needsNewMessage: new Claude turn after tool result — create a new ChatMessage
                    if state.needsNewMessage {
                        if let idx = state.messages.indices.reversed().first(where: { state.messages[$0].role == .assistant && state.messages[$0].isStreaming }) {
                            state.messages[idx].isStreaming = false
                            state.messages[idx].finalizeToolCalls()
                        }
                        state.messages.append(ChatMessage(role: .assistant, isStreaming: true))
                        state.needsNewMessage = false
                    } else if state.messages.last?.role != .assistant || !(state.messages.last?.isStreaming ?? false) {
                        state.messages.append(ChatMessage(role: .assistant, isStreaming: true))
                    }
                    if let lastIndex = state.messages.indices.last,
                       state.messages[lastIndex].role == .assistant {
                        state.messages[lastIndex].appendToolCall(toolCall)
                    }
                    // Ready to receive input_json_delta
                    state.activeToolId = id
                    state.activeToolInputBuffer = ""
                }
            } else if blockType == "text" {
                // New text block started — if needsNewMessage, prepare a new ChatMessage
                updateState(sessionKey) { state in
                    if state.needsNewMessage {
                        // Keep the flag so a new message is created on the next text_delta flush
                        // (needsNewMessage is handled inside flush)
                    }
                    state.isThinking = false
                    state.activeToolId = nil
                    state.activeToolInputBuffer = ""
                }
            } else if blockType == "thinking" {
                updateState(sessionKey) { $0.isThinking = true }
            }

        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return }

            if deltaType == "text_delta", let text = delta["text"] as? String {
                updateState(sessionKey) { state in
                    state.isThinking = false
                    state.textDeltaBuffer += text
                }
            } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                updateState(sessionKey) { state in
                    state.activeToolInputBuffer += partial
                }
            } else if deltaType == "thinking_delta" {
                updateState(sessionKey) { $0.isThinking = true }
            }

        case "content_block_stop":
            // Finalize tool_use input — parse the accumulated JSON and apply to the tool call
            updateState(sessionKey) { state in
                guard let toolId = state.activeToolId, !state.activeToolInputBuffer.isEmpty else {
                    state.activeToolId = nil
                    return
                }
                let buffer = state.activeToolInputBuffer
                state.activeToolId = nil
                state.activeToolInputBuffer = ""

                guard let inputData = buffer.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode([String: JSONValue].self, from: inputData) else { return }

                if let msgIdx = state.messages.indices.reversed().first(where: { state.messages[$0].role == .assistant && state.messages[$0].isStreaming }),
                   let blockIdx = state.messages[msgIdx].toolCallIndex(id: toolId) {
                    state.messages[msgIdx].blocks[blockIdx].toolCall?.input = parsed
                }
            }

        default:
            break
        }
    }

    // MARK: - Cancel

    private func detachCurrentStream(in window: WindowState) {
        let key = window.currentSessionId ?? window.newSessionKey
        flushPendingUpdates(for: key)
        stopFlushTimer(for: key)
    }

    func cancelStreaming(in window: WindowState) async {
        let key = window.currentSessionId ?? window.newSessionKey
        let streamToCancel = sessionStates[key]?.activeStreamId
        sessionStates[key]?.streamTask?.cancel()
        sessionStates[key]?.streamTask = nil
        // Set isStreaming=false before suspending so that processStream — which may run
        // on the MainActor while we await — does not call finalizeStreamSession and
        // incorrectly mark the cancelled message as isResponseComplete=true.
        sessionStates[key]?.isStreaming = false
        sessionStates[key]?.activeStreamId = nil

        if let streamToCancel {
            await claude.cancel(streamId: streamToCancel)
        }

        flushPendingUpdates(for: key)
        stopFlushTimer(for: key)

        updateState(key) { state in
            state.isStreaming = false
            state.isThinking = false
            state.needsNewMessage = false
            state.activeStreamId = nil
            state.streamTask = nil
            state.activeToolId = nil
            state.activeToolInputBuffer = ""
            state.textDeltaBuffer = ""
            state.pendingToolResults.removeAll()
            state.streamingStartDate = nil
            // Reset the last assistant message: clear streaming flag, completion marker,
            // and duration so a cancelled response never shows "✓ Xs" in the UI.
            if let lastIndex = state.messages.indices.last,
               state.messages[lastIndex].role == .assistant {
                state.messages[lastIndex].isStreaming = false
                state.messages[lastIndex].isResponseComplete = false
                state.messages[lastIndex].duration = nil
            }
        }

        window.showError = false
        window.errorMessage = nil

        // Save messages accumulated up to the point of cancellation to disk (prevent data loss)
        if let project = window.selectedProject {
            let messages = stateForSession(key).messages
            if !messages.isEmpty {
                await saveSession(sessionId: key, projectId: project.id, messages: messages)
            }
        }

        // Clean up placeholder session on cancellation
        if let sid = window.currentSessionId, window.pendingPlaceholderIds.contains(sid) {
            allSessionSummaries.removeAll { $0.id == sid }
            window.removePendingPlaceholder(sid)
            sessionStates.removeValue(forKey: sid)
            window.currentSessionId = nil
        }
    }

    private func recordStreamingDuration(for key: String) {
        guard let start = sessionStates[key]?.streamingStartDate else { return }
        let duration = Date().timeIntervalSince(start)
        updateState(key) { state in
            state.streamingStartDate = nil
            if let idx = state.messages.indices.reversed().first(where: { state.messages[$0].role == .assistant }) {
                state.messages[idx].duration = duration
            }
        }
    }

    // MARK: - Permission Response

    func respondToPermission(_ request: PermissionRequest, decision: PermissionDecision, in window: WindowState) async {
        await permission.respond(toolUseId: request.id, decision: decision)
        window.pendingPermissions.removeAll { $0.id == request.id }
    }

    // MARK: - Project Management

    func addProject(name: String, path: String, gitHubRepo: String?) async {
        let project = Project(name: name, path: path, gitHubRepo: gitHubRepo)
        projects.append(project)
        do {
            try await persistence.saveProjects(projects)
        } catch {
            logger.error("Failed to save projects: \(error.localizedDescription)")
        }
    }

    func selectProject(_ project: Project, in window: WindowState) {
        guard window.selectedProject?.id != project.id else { return }

        if isStreaming(in: window) {
            detachCurrentStream(in: window)
        }

        if let currentId = window.currentSessionId,
           let currentProject = window.selectedProject,
           let state = sessionStates[currentId],
           !state.messages.isEmpty {
            let title = allSessionSummaries.first(where: { $0.id == currentId })?.title ?? "Session"
            let session = ChatSession(id: currentId, projectId: currentProject.id, title: title, messages: state.messages, updatedAt: lastResponseDate(from: state.messages))
            Task {
                do { try await self.persistence.saveSession(session) }
                catch { self.logger.error("Failed to save current session before project switch: \(error.localizedDescription)") }
            }
        }

        window.selectedProject = project
        for (key, state) in sessionStates where !state.isStreaming {
            sessionStates.removeValue(forKey: key)
        }
        window.currentSessionId = nil

        UserDefaults.standard.set(project.id.uuidString, forKey: "selectedProjectId")

        // Always start a new session on project switch — instant, no message loading
        startNewChat(in: window)

        // Refresh session history in the background
        Task { [weak self] in
            guard let self else { return }
            await loadSessionHistory(in: window)
        }
    }

    func addProjectFromFolder(_ url: URL, in window: WindowState) async {
        let isGitRepo = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        let gitHubRepo = isGitRepo ? detectGitHubRepo(at: url.path) : nil
        await addAndSelectProject(name: url.lastPathComponent, path: url.path, gitHubRepo: gitHubRepo, in: window)
    }

    private nonisolated func detectGitHubRepo(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["remote", "get-url", "origin"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let urlString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return nil }

        return parseGitHubOwnerRepo(from: urlString)
    }

    private nonisolated func parseGitHubOwnerRepo(from urlString: String) -> String? {
        if urlString.contains("github.com") {
            let cleaned = urlString
                .replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: "http://github.com/", with: "")
                .replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let parts = cleaned.split(separator: "/")
            if parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
        }
        return nil
    }

    private func addAndSelectProject(name: String, path: String, gitHubRepo: String? = nil, in window: WindowState) async {
        await addProject(name: name, path: path, gitHubRepo: gitHubRepo)
        if let project = projects.last {
            selectProject(project, in: window)
        }
    }

    // MARK: - Session Management

    /// Load/refresh the project's session list into allSessionSummaries
    func loadSessionHistory(in window: WindowState) async {
        guard let project = window.selectedProject else { return }
        let sessions = await persistence.loadSessions(for: project.id)
        // Replace that project's summaries with the latest data from disk
        allSessionSummaries.removeAll { $0.projectId == project.id }
        allSessionSummaries.append(contentsOf: sessions.map(\.summary))
    }

    private func switchToSession(_ session: ChatSession, messages loadedMessages: [ChatMessage]? = nil, in window: WindowState) {
        saveDraft(in: window)
        saveQueue(in: window)

        if isStreaming(in: window) {
            detachCurrentStream(in: window)
        }

        let outgoingId = window.currentSessionId

        if sessionStates[session.id] == nil {
            var state = SessionStreamState()
            state.model = session.model
            if let msgs = loadedMessages {
                state.messages = cleanLoadedMessages(msgs)
                sessionStates[session.id] = state
            } else {
                // Switch with an empty state first; actual messages are loaded in the background and injected later
                sessionStates[session.id] = state
                if let project = window.selectedProject {
                    loadMessagesInBackground(projectId: project.id, sessionId: session.id)
                }
            }
        } else if sessionStates[session.id]?.messages.isEmpty == true,
                  sessionStates[session.id]?.isStreaming != true,
                  let project = window.selectedProject {
            // Restore model from disk if not already set in memory
            if sessionStates[session.id]?.model == nil {
                sessionStates[session.id]?.model = session.model
            }
            loadMessagesInBackground(projectId: project.id, sessionId: session.id)
        }

        if sessionStates[session.id]?.isStreaming == true {
            flushPendingUpdates(for: session.id)
        }

        window.currentSessionId = session.id
        window.sessionModel = sessionStates[session.id]?.model ?? session.model
        window.inputText = window.draftTexts[session.id] ?? ""
        window.messageQueue = window.draftQueues[session.id] ?? []

        releaseOutgoingSession(outgoingId, excluding: session.id, in: window)

        if sessionStates[session.id]?.isStreaming == true {
            startFlushTimer(for: session.id)
        }
    }

    private func releaseOutgoingSession(_ outgoingId: String?, excluding newId: String? = nil, in window: WindowState) {
        guard let outgoingId,
              outgoingId != newId,
              !(sessionStates[outgoingId]?.isStreaming ?? false) else { return }
        let outgoingMessages = sessionStates[outgoingId]?.messages ?? []
        Task { [weak self] in
            guard let self else { return }
            if !outgoingMessages.isEmpty, let project = window.selectedProject {
                let title = allSessionSummaries.first(where: { $0.id == outgoingId })?.title ?? "Session"
                let outgoing = ChatSession(id: outgoingId, projectId: project.id, title: title, messages: outgoingMessages, updatedAt: lastResponseDate(from: outgoingMessages))
                do { try await persistence.saveSession(outgoing) }
                catch { logger.error("Failed to save outgoing session: \(error.localizedDescription)") }
            }
            if window.currentSessionId != outgoingId {
                sessionStates.removeValue(forKey: outgoingId)
            }
        }
    }

    private func didSwitchToSession(_ session: ChatSession) async {
        if let index = projects.firstIndex(where: { $0.id == session.projectId }) {
            projects[index].lastSessionId = session.id
            do {
                try await persistence.saveProjects(projects)
            } catch {
                logger.error("Failed to save projects: \(error.localizedDescription)")
            }
        }
    }

    func resumeSession(_ session: ChatSession, in window: WindowState) async {
        switchToSession(session, in: window)
        await didSwitchToSession(session)
    }

    // MARK: - GitHub

    func loginToGitHub() async throws -> DeviceCodeResponse {
        try await github.startDeviceFlow()
    }

    func completeGitHubLogin(deviceCode: String, interval: Int) async throws {
        _ = try await github.pollForToken(deviceCode: deviceCode, interval: interval)

        let user = try await github.fetchUser()
        gitHubUser = user
        isLoggedIn = true
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")

        do { try await persistence.saveGitHubUser(user) }
        catch { logger.error("Failed to cache GitHub user: \(error.localizedDescription)") }

        do {
            let publicKey = try await github.setupSSH()
            try await github.registerSSHKey(publicKey)
        } catch {
            logger.warning("SSH setup failed: \(error.localizedDescription)")
        }
    }

    func skipGitHubLogin() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
    }

    var isFetchingRepos = false

    func fetchRepos() async {
        isFetchingRepos = true
        defer { isFetchingRepos = false }
        do { repos = try await github.fetchRepos() }
        catch { logger.error("Failed to fetch repos: \(error.localizedDescription)") }
    }

    func cloneAndAddProject(_ repo: GitHubRepo, in window: WindowState) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let clonePath = "\(home)/Clarc/\(repo.name)"
        let parentDir = "\(home)/Clarc"
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir) {
            try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }
        try await github.cloneRepo(repo, to: clonePath)
        await addAndSelectProject(name: repo.name, path: clonePath, gitHubRepo: repo.fullName, in: window)
    }

    // MARK: - View Convenience API

    func startNewChat(in window: WindowState) {
        if isStreaming(in: window) { detachCurrentStream(in: window) }
        saveDraft(in: window)
        saveQueue(in: window)
        releaseOutgoingSession(window.currentSessionId, in: window)
        window.currentSessionId = nil
        window.sessionModel = nil
        sessionStates.removeValue(forKey: window.newSessionKey)
        window.inputText = window.draftTexts["new"] ?? ""
        window.messageQueue = window.draftQueues["new"] ?? []
        window.requestInputFocus = true
    }

    func renameSession(_ session: ChatSession, to newTitle: String) async {
        if let si = allSessionSummaries.firstIndex(where: { $0.id == session.id }) {
            allSessionSummaries[si].title = newTitle
        }
        // Load full session from disk to preserve existing messages (the caller
        // may pass a summary-backed session with empty messages).
        let base = persistence.loadSession(projectId: session.projectId, sessionId: session.id) ?? session
        var updated = base
        updated.title = newTitle
        do { try await persistence.saveSession(updated) }
        catch { logger.error("Failed to save renamed session: \(error.localizedDescription)") }
    }

    func togglePinSession(_ session: ChatSession) async {
        guard let si = allSessionSummaries.firstIndex(where: { $0.id == session.id }) else { return }
        allSessionSummaries[si].isPinned.toggle()
        let newIsPinned = allSessionSummaries[si].isPinned
        // Load full session from disk to preserve existing messages (session may have messages: [])
        let base = persistence.loadSession(projectId: session.projectId, sessionId: session.id) ?? session
        var updated = base
        updated.isPinned = newIsPinned
        do { try await persistence.saveSession(updated) }
        catch { logger.error("Failed to save pinned session: \(error.localizedDescription)") }
    }

    func renameProject(_ project: Project, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].name = trimmed
        do {
            try await persistence.saveProjects(projects)
        } catch {
            logger.error("Failed to save projects after rename: \(error.localizedDescription)")
        }
    }

    func deleteProject(_ project: Project, in window: WindowState) async {
        // Switch away if the deleted project is currently selected
        if window.selectedProject?.id == project.id {
            let next = projects.first(where: { $0.id != project.id })
            if let next {
                selectProject(next, in: window)
            } else {
                window.selectedProject = nil
                window.currentSessionId = nil
            }
        }

        // Remove all in-memory session summaries for this project
        allSessionSummaries.removeAll { $0.projectId == project.id }

        // Remove from projects list and persist
        projects.removeAll { $0.id == project.id }
        do {
            try await persistence.saveProjects(projects)
        } catch {
            logger.error("Failed to save projects after deletion: \(error.localizedDescription)")
        }
    }

    func deleteSession(_ session: ChatSession, in window: WindowState) async {
        if window.currentSessionId == session.id {
            startNewChat(in: window)
        }
        do {
            try await persistence.deleteSession(projectId: session.projectId, sessionId: session.id)
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription)")
        }
        allSessionSummaries.removeAll { $0.id == session.id }
        sessionStates.removeValue(forKey: session.id)
    }

    func deleteAllSessions(projectId: UUID? = nil, in window: WindowState) async {
        let toDelete: [ChatSession.Summary]
        if let projectId {
            toDelete = allSessionSummaries.filter { $0.projectId == projectId }
        } else {
            toDelete = allSessionSummaries
        }

        startNewChat(in: window)

        for summary in toDelete {
            do {
                try await persistence.deleteSession(projectId: summary.projectId, sessionId: summary.id)
            } catch {
                logger.error("Failed to delete session \(summary.id): \(error.localizedDescription)")
            }
        }

        let ids = Set(toDelete.map(\.id))
        allSessionSummaries.removeAll { ids.contains($0.id) }
        for id in ids { sessionStates.removeValue(forKey: id) }
    }

    func selectSession(id: String, in window: WindowState) {
        guard window.currentSessionId != id else { return }

        window.cancelSessionSwitchTask()

        if let summary = allSessionSummaries.first(where: { $0.id == id }),
           summary.projectId == window.selectedProject?.id {
            let session = summary.makeSession()
            switchToSession(session, in: window)
            window.requestInputFocus = true
            window.setSessionSwitchTask(Task {
                guard !Task.isCancelled else { return }
                await didSwitchToSession(session)
            })
            return
        }

        // If it's a session from another project, switch the project as well
        guard let summary = allSessionSummaries.first(where: { $0.id == id }),
              let project = projects.first(where: { $0.id == summary.projectId }) else { return }

        window.setSessionSwitchTask(Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            selectProject(project, in: window)
            guard !Task.isCancelled else { return }
            if let s = allSessionSummaries.first(where: { $0.id == id }) {
                let session = ChatSession(id: s.id, projectId: s.projectId, title: s.title, messages: [], isPinned: s.isPinned)
                if sessionStates[session.id] == nil,
                   let full = persistence.loadSession(projectId: project.id, sessionId: id) {
                    switchToSession(full, messages: full.messages, in: window)
                } else {
                    switchToSession(session, in: window)
                }
                window.requestInputFocus = true
                await didSwitchToSession(session)
            }
        })
    }

    func addProject(_ project: Project) {
        projects.append(project)
        Task {
            do { try await persistence.saveProjects(projects) }
            catch { logger.error("Failed to save projects: \(error.localizedDescription)") }
        }
    }

    // MARK: - Marketplace

    func loadMarketplace(forceRefresh: Bool = false) async {
        marketplaceLoading = true
        defer { marketplaceLoading = false }

        async let catalog = marketplace.fetchCatalog(forceRefresh: forceRefresh)
        async let installed = marketplace.installedPluginNames()

        marketplaceCatalog = await catalog
        marketplaceInstalledNames = await installed
    }

    func installMarketplacePlugin(_ plugin: MarketplacePlugin) async {
        marketplacePluginStates[plugin.id] = .installing
        do {
            try await marketplace.installPlugin(plugin)
            marketplacePluginStates[plugin.id] = .installed
            marketplaceInstalledNames.insert(plugin.name)
        } catch {
            marketplacePluginStates[plugin.id] = .failed(error.localizedDescription)
            logger.error("Failed to install plugin \(plugin.name): \(error.localizedDescription)")
        }
    }

    func uninstallMarketplacePlugin(_ plugin: MarketplacePlugin) async {
        do {
            try await marketplace.uninstallPlugin(plugin)
            marketplaceInstalledNames.remove(plugin.name)
            marketplacePluginStates[plugin.id] = .notInstalled
        } catch {
            logger.error("Failed to uninstall plugin \(plugin.name): \(error.localizedDescription)")
        }
    }

    // MARK: - Attachment Management

    func addAttachment(_ attachment: Attachment, in window: WindowState) {
        window.attachments.append(attachment)
    }

    func removeAttachment(_ id: UUID, in window: WindowState) {
        window.attachments.removeAll { $0.id == id }
    }

    private func buildPromptWithAttachments(_ text: String, attachments: [Attachment]) -> String {
        guard !attachments.isEmpty else { return text }
        let attachmentLines = attachments.map(\.promptContext).joined(separator: "\n")
        let userText = text.isEmpty ? "See attached files" : text
        return "\(attachmentLines)\n\n\(userText)"
    }

    // MARK: - Private Helpers

    /// Extract the last response time from the message list. Based on the last assistant message; falls back to the last message, then current time.
    private func lastResponseDate(from messages: [ChatMessage]) -> Date {
        messages.last(where: { $0.role == .assistant })?.timestamp
            ?? messages.last?.timestamp
            ?? Date()
    }

    private func cleanLoadedMessages(_ raw: [ChatMessage]) -> [ChatMessage] {
        raw.compactMap { message in
            var msg = message
            msg.isStreaming = false
            if msg.blocks.isEmpty && msg.role == .assistant { return nil }
            return msg
        }
    }

    /// Load messages in the background and inject without blocking the main thread.
    /// Does not overwrite if currently streaming or if messages already exist.
    private func loadMessagesInBackground(projectId: UUID, sessionId: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let full = self.persistence.loadSession(projectId: projectId, sessionId: sessionId)
            guard let full else { return }
            let cleaned = await self.cleanLoadedMessages(full.messages)
            await MainActor.run {
                guard var state = self.sessionStates[sessionId] else { return }
                guard !state.isStreaming, state.messages.isEmpty else { return }
                state.messages = cleaned
                if state.model == nil { state.model = full.model }
                self.sessionStates[sessionId] = state
            }
        }
    }

    private func saveCurrentSession(in window: WindowState) async {
        guard let project = window.selectedProject,
              let sessionId = window.currentSessionId else { return }
        await saveSession(
            sessionId: sessionId,
            projectId: project.id,
            messages: stateForSession(sessionId).messages
        )
    }

    private func saveSession(sessionId: String, projectId: UUID, messages: [ChatMessage]) async {
        guard !messages.isEmpty else { return }

        // Preserve the existing title (which may have been renamed by the user).
        // Only auto-generate a title when no summary exists yet for this session.
        let title: String
        if let existing = allSessionSummaries.first(where: { $0.id == sessionId }), !existing.title.isEmpty {
            title = existing.title
        } else {
            let firstUserContent = messages.first(where: { $0.role == .user })?.content
            title = firstUserContent.map { $0.count > 50 ? String($0.prefix(50)) + "..." : $0 } ?? "New Session"
        }

        let sessionModel = sessionStates[sessionId]?.model
        let session = ChatSession(id: sessionId, projectId: projectId, title: title, messages: messages, updatedAt: lastResponseDate(from: messages), model: sessionModel)

        do {
            try await persistence.saveSession(session)
        } catch {
            logger.error("Failed to save session \(sessionId): \(error.localizedDescription)")
        }

        // Update allSessionSummaries — skipped while streaming (updated only once after completion)
        let isCurrentlyStreaming = sessionStates[sessionId]?.isStreaming ?? false
        if !isCurrentlyStreaming {
            let summary = session.summary
            withAnimation(nil) {
                while allSessionSummaries.filter({ $0.id == sessionId }).count > 1,
                      let lastIdx = allSessionSummaries.lastIndex(where: { $0.id == sessionId }) {
                    allSessionSummaries.remove(at: lastIdx)
                }
                if let index = allSessionSummaries.firstIndex(where: { $0.id == sessionId }) {
                    allSessionSummaries[index] = summary
                } else {
                    allSessionSummaries.insert(summary, at: 0)
                }
            }
        }

        // Update the project's lastSessionId
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].lastSessionId = sessionId
            do {
                try await persistence.saveProjects(projects)
            } catch {
                logger.error("Failed to save projects: \(error.localizedDescription)")
            }
        }
    }

    private func saveDraft(in window: WindowState) {
        let key = window.currentSessionId ?? "new"
        let trimmed = window.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { window.draftTexts.removeValue(forKey: key) }
        else { window.draftTexts[key] = window.inputText }
    }

    private func saveQueue(in window: WindowState) {
        let key = window.currentSessionId ?? "new"
        if window.messageQueue.isEmpty { window.draftQueues.removeValue(forKey: key) }
        else { window.draftQueues[key] = window.messageQueue }
    }

    /// Sends the next queued message for a background session (one the window is not currently displaying).
    /// Foreground session queues are handled by InputBarView via the isStreaming onChange handler.
    private func processBackgroundQueue(
        for sessionKey: String,
        projectId: UUID,
        cwd: String,
        in window: WindowState
    ) async {
        guard sessionStates[sessionKey]?.isStreaming != true else { return }
        guard var queue = window.draftQueues[sessionKey], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        if queue.isEmpty { window.draftQueues.removeValue(forKey: sessionKey) }
        else { window.draftQueues[sessionKey] = queue }

        let (resolvedAttachments, tempFilePaths) = AttachmentFactory.resolvingClipboardImages(next.attachments)
        let prompt = buildPromptWithAttachments(next.text, attachments: resolvedAttachments)
        let displayText = next.text
        let streamId = UUID()

        updateState(sessionKey) { state in
            state.messages.append(ChatMessage(role: .user, content: displayText, attachments: resolvedAttachments))
            state.isStreaming = true
            state.activeStreamId = streamId
            state.streamingStartDate = Date()
        }

        await permission.refreshRunToken()

        var hookSettingsPath: String?
        if !permissionMode.skipsHookPipeline {
            do { hookSettingsPath = try await permission.writeHookSettingsFile() }
            catch { logger.error("Failed to write hook settings for background queue: \(error.localizedDescription)") }
        }

        let currentPermissionMode = permissionMode
        let model = sessionStates[sessionKey]?.model ?? selectedModel
        let task = Task { [weak self, window] in
            guard let self else { return }
            await self.processStream(
                streamId: streamId,
                prompt: prompt,
                cwd: cwd,
                cliSessionId: sessionKey,
                internalSessionKey: sessionKey,
                model: model,
                hookSettingsPath: hookSettingsPath,
                permissionMode: currentPermissionMode,
                projectId: projectId,
                window: window
            )
            for path in tempFilePaths { try? FileManager.default.removeItem(atPath: path) }
        }
        sessionStates[sessionKey]?.streamTask = task
    }

    private func handleError(_ error: Error, in window: WindowState) {
        logger.error("AppState error: \(error.localizedDescription)")
        addErrorMessage(error.localizedDescription, in: window)
    }

    private func addErrorMessage(_ text: String, in window: WindowState) {
        let key = window.currentSessionId ?? window.newSessionKey
        let msg = ChatMessage(role: .assistant, content: text, isError: true)
        updateState(key) { $0.messages.append(msg) }
    }

    // MARK: - Claude Settings Reader

    private nonisolated static func readPermissionModeFromSettings() -> PermissionMode {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let permissions = json["permissions"] as? [String: Any],
              let mode = permissions["defaultMode"] as? String,
              let parsed = PermissionMode(rawValue: mode)
        else { return .default }
        return parsed
    }
}

// MARK: - App Errors

private enum AppError: LocalizedError {
    case noProjectSelected
    case claudeNotInstalled

    var errorDescription: String? {
        switch self {
        case .noProjectSelected:
            return "No project selected. Please select or add a project first."
        case .claudeNotInstalled:
            return "Claude CLI binary not found. Please install it first."
        }
    }
}
