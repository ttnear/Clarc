import Foundation
import ClarcCore
import SwiftUI
import os
import ClarcChatKit

// MARK: - Per-Session Stream State

/// Cache key for reloadCommittedFromDisk: both size and mtime must match to skip a parse.
/// Using size alone misses shrink/rewrite (e.g. `claude --resume` compaction).
nonisolated private struct ReloadCacheKey: Equatable {
    let size: UInt64
    let mtime: Date
}

/// Encapsulates all independent state per session.
/// Stored in the `AppState.sessionStates` dictionary keyed by session ID.
struct SessionStreamState {
    // Two-tier message storage: disk truth + live tail
    var committedMessages: [ChatMessage] = []
    var streamingTail: StreamingTail?

    /// UI-only messages that are never written to jsonl (errors, compact markers,
    /// terminal transcript). Survives disk reloads — disk only owns committedMessages.
    var localAddendum: [ChatMessage] = []

    /// The full message list for rendering and saving.
    var allMessages: [ChatMessage] {
        committedMessages + (streamingTail?.messages ?? []) + localAddendum
    }

    // Streaming lifecycle
    var isStreaming = false
    var isThinking = false
    var activeStreamId: UUID?
    var streamingStartDate: Date?
    var streamTask: Task<Void, Never>?
    var flushTask: Task<Void, Never>?

    // Per-session overrides (persisted in memory across session switches)
    var model: String?
    var effort: String?
    var permissionMode: PermissionMode?

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

/// Holds the in-flight messages and delta buffers for the currently active streaming turn.
/// Created when streaming starts; discarded after the turn ends and disk is reloaded.
struct StreamingTail {
    var messages: [ChatMessage] = []
    var textDeltaBuffer: String = ""
    var pendingToolResults: [(toolUseId: String, content: String, isError: Bool)] = []
    var needsNewMessage: Bool = false
    var activeToolId: String?
    var activeToolInputBuffer: String = ""
    var activeThinkingId: String?
    var thinkingDeltaBuffer: String = ""
    var thinkingStartDate: Date?
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

    /// Last (size, mtime) seen by reloadCommittedFromDisk. Skips parse only when
    /// both attributes match, so shrink/rewrite always triggers a fresh parse.
    private var lastCommittedReloadKey: [String: ReloadCacheKey] = [:]

    /// Retained token for the NSApplication.didBecomeActiveNotification observer.
    /// Stored so we can remove it in deinit.
    private var didBecomeActiveObserverToken: NSObjectProtocol?

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

    // MARK: - Font Size

    var fontSizeAdjustment: Int = (UserDefaults.standard.object(forKey: "fontSizeAdjustment") as? Int) ?? 0 {
        didSet {
            UserDefaults.standard.set(fontSizeAdjustment, forKey: "fontSizeAdjustment")
            ThemeStore.shared.fontSizeAdjustment = fontSizeAdjustment
            themeRevision += 1
        }
    }

    func increaseFontSize() {
        guard fontSizeAdjustment < ThemeStore.maxFontSizeAdjustment else { return }
        fontSizeAdjustment += 1
    }

    func decreaseFontSize() {
        guard fontSizeAdjustment > ThemeStore.minFontSizeAdjustment else { return }
        fontSizeAdjustment -= 1
    }

    var messageFontSizeAdjustment: Int = (UserDefaults.standard.object(forKey: "messageFontSizeAdjustment") as? Int) ?? 0 {
        didSet {
            UserDefaults.standard.set(messageFontSizeAdjustment, forKey: "messageFontSizeAdjustment")
            ThemeStore.shared.messageFontSizeAdjustment = messageFontSizeAdjustment
            themeRevision += 1
        }
    }

    func increaseMessageFontSize() {
        guard messageFontSizeAdjustment < ThemeStore.maxFontSizeAdjustment else { return }
        messageFontSizeAdjustment += 1
    }

    func decreaseMessageFontSize() {
        guard messageFontSizeAdjustment > ThemeStore.minFontSizeAdjustment else { return }
        messageFontSizeAdjustment -= 1
    }

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

    static func permissionModeDescription(_ mode: PermissionMode) -> String {
        let key: String
        switch mode {
        case .default:           key = "perm.desc.default"
        case .acceptEdits:       key = "perm.desc.acceptEdits"
        case .plan:              key = "perm.desc.plan"
        case .auto:              key = "perm.desc.auto"
        case .bypassPermissions: key = "perm.desc.bypassPermissions"
        }
        return NSLocalizedString(key, comment: "")
    }

    static func effortDescription(_ effort: String) -> String {
        let key: String
        switch effort {
        case "auto":   key = "effort.desc.auto"
        case "low":    key = "effort.desc.low"
        case "medium": key = "effort.desc.medium"
        case "high":   key = "effort.desc.high"
        case "xhigh":  key = "effort.desc.xhigh"
        case "max":    key = "effort.desc.max"
        default: return ""
        }
        return NSLocalizedString(key, comment: "")
    }

    var selectedModel: String = UserDefaults.standard.string(forKey: "selectedModel") ?? "opus" {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    var selectedEffort: String = UserDefaults.standard.string(forKey: "selectedEffort") ?? "auto" {
        didSet { UserDefaults.standard.set(selectedEffort, forKey: "selectedEffort") }
    }

    // MARK: - Notifications

    var notificationsEnabled: Bool = (UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    // MARK: - Focus Mode

    var focusMode: Bool = (UserDefaults.standard.object(forKey: "focusMode") as? Bool) ?? false {
        didSet { UserDefaults.standard.set(focusMode, forKey: "focusMode") }
    }

    // MARK: - Inspector Layout

    /// Where the memo / terminal inspector panel is docked. Defaults to the right side.
    var inspectorPosition: InspectorPosition = InspectorPosition(rawValue: UserDefaults.standard.string(forKey: "inspectorPosition") ?? "") ?? .right {
        didSet { UserDefaults.standard.set(inspectorPosition.rawValue, forKey: "inspectorPosition") }
    }

    /// When true, memo and terminal are shown together (split) instead of one tab at a time.
    var inspectorShowBoth: Bool = (UserDefaults.standard.object(forKey: "inspectorShowBoth") as? Bool) ?? false {
        didSet { UserDefaults.standard.set(inspectorShowBoth, forKey: "inspectorShowBoth") }
    }

    // MARK: - Attachment Auto-Preview Settings

    private static let autoPreviewSettingsKey = "attachmentAutoPreviewSettings"

    var autoPreviewSettings: AttachmentAutoPreviewSettings = {
        guard let data = UserDefaults.standard.data(forKey: AppState.autoPreviewSettingsKey),
              let settings = try? JSONDecoder().decode(AttachmentAutoPreviewSettings.self, from: data) else {
            return AttachmentAutoPreviewSettings()
        }
        return settings
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(autoPreviewSettings) {
                UserDefaults.standard.set(data, forKey: AppState.autoPreviewSettingsKey)
            }
        }
    }

    /// Pending session to navigate to when a project window opens or is already open.
    /// Keyed by projectId; consumed once applied.
    var pendingNotificationSession: [UUID: String] = [:]

    /// Ref-counted set of projectIds with at least one open dedicated project window.
    /// Used to decide whether a notification tap should route to the main window or
    /// hand off to an existing project window via `pendingNotificationSession`.
    @ObservationIgnored
    var openProjectWindowCounts: [UUID: Int] = [:]

    func registerOpenProjectWindow(_ projectId: UUID) {
        openProjectWindowCounts[projectId, default: 0] += 1
    }

    func unregisterOpenProjectWindow(_ projectId: UUID) {
        guard let count = openProjectWindowCounts[projectId] else { return }
        if count <= 1 {
            openProjectWindowCounts.removeValue(forKey: projectId)
        } else {
            openProjectWindowCounts[projectId] = count - 1
        }
    }

    func hasOpenProjectWindow(for projectId: UUID) -> Bool {
        (openProjectWindowCounts[projectId] ?? 0) > 0
    }

    /// Routes a notification tap to the right window without spawning a new one.
    /// Hands off to an existing project window if one is open for that project;
    /// otherwise navigates the supplied main window in place.
    func handleNotificationTap(projectId: UUID, sessionId: String, mainWindow: WindowState) {
        if hasOpenProjectWindow(for: projectId) {
            pendingNotificationSession[projectId] = sessionId
            return
        }
        if mainWindow.selectedProject?.id == projectId {
            guard mainWindow.currentSessionId != sessionId else { return }
            mainWindow.currentSessionId = sessionId
        } else {
            selectSession(id: sessionId, in: mainWindow)
        }
    }

    /// Sets the model for the current session and persists it in the session state.
    func setSessionModel(_ model: String, in window: WindowState) {
        window.sessionModel = model
        let key = window.currentSessionId ?? window.newSessionKey
        updateState(key) { state in
            state.model = model
            // Drop the cached CLI-reported name so the status line reflects the
            // user's choice immediately; the next system event will refill it.
            state.activeModelName = nil
        }
    }

    /// Sets the effort for the current session and persists it in the session state.
    func setSessionEffort(_ effort: String?, in window: WindowState) {
        window.sessionEffort = effort
        let key = window.currentSessionId ?? window.newSessionKey
        updateState(key) { $0.effort = effort }
    }

    /// Sets the permission mode for the current session and persists it in the session state.
    func setSessionPermissionMode(_ mode: PermissionMode, in window: WindowState) {
        window.sessionPermissionMode = mode
        let key = window.currentSessionId ?? window.newSessionKey
        updateState(key) { $0.permissionMode = mode }
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

    var permissionMode: PermissionMode = .default {
        didSet { UserDefaults.standard.set(permissionMode.rawValue, forKey: "selectedPermissionMode") }
    }

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

    let github = GitHubService()
    let permission = PermissionServer()
    let metaStore = SessionMetaStore()
    let cliStore: CLISessionStore
    let claude: ClaudeService
    let persistence: PersistenceService
    let marketplace = MarketplaceService()
    let directoryWatcher = DirectoryWatcher()

    init() {
        let metaStore = self.metaStore
        let cliStore = CLISessionStore(metaStore: metaStore)
        self.cliStore = cliStore
        self.claude = ClaudeService(cliStore: cliStore)
        self.persistence = PersistenceService(metaStore: metaStore, cliStore: cliStore)

        self.didBecomeActiveObserverToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Build project lookup once instead of nested first(where:) per session
                let projectLookup = Dictionary(uniqueKeysWithValues: self.projects.map { ($0.id, $0.path) })
                for (sid, state) in self.sessionStates where !state.isStreaming {
                    guard let summary = self.allSessionSummaries.first(where: { $0.id == sid }),
                          let cwd = projectLookup[summary.projectId] else { continue }
                    self.reloadCommittedFromDisk(sessionId: sid, projectId: summary.projectId, cwd: cwd)
                }
            }
        }
    }

    isolated deinit {
        if let token = didBecomeActiveObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Private State

    // MARK: - Window-Scoped Session State Accessors

    func streamState(in window: WindowState) -> SessionStreamState {
        sessionStates[window.currentSessionId ?? window.newSessionKey] ?? SessionStreamState()
    }

    func messages(in window: WindowState) -> [ChatMessage] {
        streamState(in: window).allMessages
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
        ThemeStore.shared.fontSizeAdjustment = fontSizeAdjustment
        ThemeStore.shared.messageFontSizeAdjustment = messageFontSizeAdjustment

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
        var seenPaths = Set<String>()
        let deduplicated = projects.filter { seenPaths.insert($0.path).inserted }
        if deduplicated.count != projects.count {
            projects = deduplicated
            try? await persistence.saveProjects(projects)
        }

        if let cachedUser = await persistence.loadGitHubUser() {
            gitHubUser = cachedUser
            isLoggedIn = true
            _ = await github.loadToken()
        }

        // Load all session summaries (excluding message bodies). Merges
        // CLI-backed sessions (~/.claude/projects/...) with the legacy
        // Clarc-owned JSON store, preferring CLI-backed when both exist for
        // the same session id.
        allSessionSummaries = await mergedSummariesAcrossProjects()

        for project in projects {
            watchProjectDirectory(project)
        }

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

        // Migrate legacy Clarc JSON sessions to CLI-compatible jsonl so they can
        // be resumed with `claude --resume`. Runs in the background; already-migrated
        // sessions (.json.migrated suffix) are skipped automatically.
        let legacySummaries = allSessionSummaries.filter { $0.origin == .legacyClarc }
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.migrateLegacySessions(legacySummaries)
        }
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

        // Install the AskUserQuestion answer handler. When the user taps an option in the
        // chat UI, this closure delivers the response to the currently streaming CLI.
        window.answerQuestionHandler = { [weak self, weak window] toolUseId, optionLabel in
            guard let self, let window else { return }
            Task { await self.respondToAskUserQuestion(toolUseId: toolUseId, optionLabel: optionLabel, in: window) }
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
        bridge.forkFromHereHandler = { [weak self, weak window] messageId in
            guard let self, let window else { return }
            await self.forkFromHere(messageId: messageId, in: window)
        }
        bridge.fetchRateLimitHandler = {
            await RateLimitService.shared.fetchUsage()
        }

        startBridgeObservation(bridge, for: window)
    }

    /// Runs a reactive observation loop: reads AppState + WindowState properties into the bridge,
    /// then re-registers after each change. Stops when the bridge or window is deallocated.
    private func startBridgeObservation(_ bridge: ChatBridge, for window: WindowState) {
        // Streaming state and global settings are observed in separate loops so that frequent
        // streaming updates don't trigger settings re-pushes (and vice versa).
        func observeStream() {
            withObservationTracking {
                let state = streamState(in: window)
                bridge.messages = state.allMessages
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
                Task { @MainActor in observeStream() }
            }
        }
        func observeSettings() {
            withObservationTracking {
                bridge.autoPreviewSettings = self.autoPreviewSettings
            } onChange: {
                Task { @MainActor in observeSettings() }
            }
        }
        Task { @MainActor in observeStream() }
        Task { @MainActor in observeSettings() }
    }

    // MARK: - Edit & Resend

    func editAndResend(messageId: UUID, newContent: String, in window: WindowState) async {
        let key = window.currentSessionId ?? window.newSessionKey
        var snapshot = sessionStates[key]?.allMessages ?? []
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
        lastCommittedReloadKey.removeValue(forKey: window.newSessionKey)
        await sendPrompt(trimmed, skipAppendingUserMessage: true, initialMessages: snapshot, in: window)
    }

    // MARK: - Fork

    /// Branch the current session at the selected message. Copies the CLI jsonl up
    /// to (and including) the matching line into a fresh sid so the resumed
    /// conversation keeps full prior context — the original session is left
    /// untouched, and the window switches to the new branch.
    func forkFromHere(messageId: UUID, in window: WindowState) async {
        guard let sid = window.currentSessionId,
              !window.pendingPlaceholderIds.contains(sid) else {
            logger.warning("forkFromHere: no committed session to fork")
            return
        }
        guard let project = window.selectedProject else { return }

        let snapshot = sessionStates[sid]?.allMessages ?? []
        guard let message = snapshot.first(where: { $0.id == messageId }) else { return }

        if isStreaming(in: window) {
            await cancelStreaming(in: window)
        }

        guard let newSid = await cliStore.forkSession(
            fromSid: sid,
            cwd: project.path,
            atMessageTimestamp: message.timestamp,
            role: message.role
        ) else {
            logger.error("forkFromHere: cliStore.forkSession returned nil")
            return
        }

        // Normalize the copied jsonl so the branch shows up in the external
        // `claude --resume` picker, matching how Clarc-spawned sessions are exposed.
        await cliStore.exposeToPicker(sid: newSid, cwd: project.path)

        guard let forked = await cliStore.loadFullSession(
            sid: newSid,
            cwd: project.path,
            projectId: project.id
        ) else {
            logger.error("forkFromHere: failed to load forked session \(newSid)")
            return
        }

        allSessionSummaries.removeAll { $0.id == newSid }
        allSessionSummaries.insert(forked.summary, at: 0)
        switchToSession(forked, messages: forked.messages, in: window)
        window.requestInputFocus = true
    }

    // MARK: - Send Message

    func send(in window: WindowState) async {
        let prompt = window.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentAttachments = window.attachments
        guard !prompt.isEmpty || !currentAttachments.isEmpty else { return }

        // First send into a project may be the moment its CLI directory is
        // created. Re-attempt the watch (no-op if already active).
        if let project = window.selectedProject {
            watchProjectDirectory(project)
        }

        // S2: warn (in logs) if another process touched the same jsonl very
        // recently — likely a `claude` running in the terminal on the same
        // session. We don't block, but the operator can spot it after the fact.
        if let sid = window.currentSessionId,
           let cwd = window.selectedProject?.path,
           cliStore.detectExternalActivity(sid: sid, cwd: cwd, withinSeconds: 5) {
            logger.warning("Session \(sid, privacy: .public) jsonl was modified within 5s — another claude process may be active")
        }

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
        case "clear", "reset", "new":
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
                setSessionEffort(Self.availableEfforts.contains(arg) ? arg : nil, in: window)
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
            .first { $0.name == baseName || $0.aliases.contains(baseName) }?.isInteractive ?? false

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
            state.localAddendum.append(ChatMessage(role: .user, content: terminal.title))
            let result = exitCode == 0 ? "Done" : "exit code: \(exitCode)"
            let toolCall = ToolCall(
                id: UUID().uuidString,
                name: InteractiveTerminalState.toolName,
                input: ["command": .string(terminal.title)],
                result: result,
                isError: exitCode != 0
            )
            state.localAddendum.append(ChatMessage(role: .assistant, blocks: [.toolCall(toolCall)]))
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
            let snapModel = window.sessionModel
            let snapEffort = window.sessionEffort
            let snapPermission = window.sessionPermissionMode
            updateState(tempId) { state in
                state.model = snapModel
                state.effort = snapEffort
                state.permissionMode = snapPermission
            }
        }

        let sessionKey = window.currentSessionId!

        // Apply initialMessages if provided
        if let initial = initialMessages {
            updateState(sessionKey) { $0.committedMessages = initial }
        }

        if !skipAppendingUserMessage {
            updateState(sessionKey) { state in
                state.committedMessages.append(ChatMessage(
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
            state.streamingTail = StreamingTail()
        }
        await permission.refreshRunToken()

        let currentPermissionMode = window.sessionPermissionMode ?? permissionMode
        // Always register a hook file — even in bypassPermissions mode, AskUserQuestion
        // needs the hook to deliver the user's answer. The matcher narrows accordingly.
        var hookSettingsPath: String?
        do {
            hookSettingsPath = try await permission.writeHookSettingsFile(permissionMode: currentPermissionMode)
        } catch {
            logger.error("Failed to write hook settings: \(error.localizedDescription)")
        }

        // Resume already has the sid; new sessions register on first system event.
        if let sid = cliSessionId {
            await permission.registerSession(sid: sid, projectKey: project.path, mode: currentPermissionMode)
        }

        if isNewSession {
            let titleText = prompt.count > 50 ? String(prompt.prefix(50)) + "..." : prompt
            let placeholder = ChatSession(id: sessionKey, projectId: project.id, title: titleText, messages: [], origin: .cliBacked)
            allSessionSummaries.insert(placeholder.summary, at: 0)
        } else {
            await saveCurrentSession(in: window)
        }

        let task = Task { [weak self, window] in
            guard let self else { return }
            await self.processStream(
                streamId: streamId,
                prompt: prompt,
                cwd: project.path,
                cliSessionId: cliSessionId,
                internalSessionKey: sessionKey,
                model: window.sessionModel ?? self.selectedModel,
                effort: window.sessionEffort ?? (self.selectedEffort == "auto" ? nil : self.selectedEffort),
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

    /// Promote any in-flight `streamingTail.messages` into `committedMessages` (with
    /// `isStreaming` cleared) and drop the tail. No-op when no tail is present.
    private func promoteTailToCommitted(for key: String) {
        guard var s = sessionStates[key], let tail = s.streamingTail else { return }
        s.committedMessages += tail.messages.map { msg in
            var m = msg
            m.isStreaming = false
            return m
        }
        s.streamingTail = nil
        sessionStates[key] = s
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
            state.activeStreamId = nil
            state.streamTask = nil

            if state.streamingTail != nil {
                state.streamingTail!.needsNewMessage = false
                state.streamingTail!.activeToolId = nil
                state.streamingTail!.activeToolInputBuffer = ""
                state.streamingTail!.textDeltaBuffer = ""
                state.streamingTail!.pendingToolResults.removeAll()
                state.streamingTail!.activeThinkingId = nil
                state.streamingTail!.thinkingDeltaBuffer = ""
                state.streamingTail!.thinkingStartDate = nil

                if let idx = state.streamingTail!.messages.indices.reversed().first(where: {
                    state.streamingTail!.messages[$0].role == .assistant && state.streamingTail!.messages[$0].isStreaming
                }) {
                    state.streamingTail!.messages[idx].isStreaming = false
                    state.streamingTail!.messages[idx].isResponseComplete = true
                    state.streamingTail!.messages[idx].finalizeToolCalls()
                    if let start = state.streamingStartDate {
                        state.streamingTail!.messages[idx].duration = Date().timeIntervalSince(start)
                    }
                    Self.stripNoOpText(at: idx, in: &state.streamingTail!.messages)
                }
            }

            extraMutations?(&state)

            state.streamingStartDate = nil
        }
    }

    /// Drop "No response requested." text blocks from the assistant message
    /// at `idx`. If the message has no blocks left after the strip, remove
    /// it entirely. Called at turn-finalization sites — the marker is the
    /// model's response when a turn arrives without a user prompt
    /// (ScheduleWakeup, hook re-entry) and reads as noise in the chat UI.
    private static func stripNoOpText(at idx: Int, in messages: inout [ChatMessage]) {
        guard messages.indices.contains(idx) else { return }
        messages[idx].blocks.removeAll { block in
            guard let text = block.text else { return false }
            return CLIMetaEnvelope.isNoResponseRequested(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if messages[idx].blocks.isEmpty {
            messages.remove(at: idx)
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
                        await claude.closeStdin(streamId: streamId)
                        if sessionKey != resultEvent.sessionId {
                            if let state = sessionStates.removeValue(forKey: sessionKey) {
                                sessionStates[resultEvent.sessionId] = state
                            }
                            lastCommittedReloadKey.removeValue(forKey: sessionKey)
                            sessionKey = resultEvent.sessionId
                        }
                        let msgs = stateForSession(sessionKey).allMessages
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
                    // Only the `init` event carries the authoritative conversation session id.
                    // Hook lifecycle events (hook_started/hook_response) are emitted with the
                    // SessionStart hook's own session id — treating those as the conversation
                    // would re-key state to a bogus id and insert a phantom history entry that
                    // vanishes when the turn ends and the list is rebuilt from disk.
                    if systemEvent.subtype == "init", let sid = systemEvent.sessionId {
                        await permission.registerSession(sid: sid, projectKey: cwd, mode: permissionMode)
                        if sessionKey != sid {
                            let oldKey = sessionKey
                            if let state = sessionStates.removeValue(forKey: oldKey) {
                                sessionStates[sid] = state
                            }
                            lastCommittedReloadKey.removeValue(forKey: oldKey)
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
                                updatedAt: Date(),
                                origin: old.origin
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
                                let msgs = stateForSession(sessionKey).allMessages
                                let firstUserContent = msgs.first(where: { $0.role == .user })?.content
                                let title: String
                                if let content = firstUserContent {
                                    title = content.count > 50 ? String(content.prefix(50)) + "..." : content
                                } else {
                                    title = "New Session"
                                }
                                let newSession = ChatSession(id: sid, projectId: project.id, title: title, messages: [], updatedAt: Date(), origin: .cliBacked)
                                allSessionSummaries.insert(newSession.summary, at: 0)
                            }
                        }
                    }

                    if systemEvent.subtype == "compact_boundary" {
                        updateState(sessionKey) { state in
                            state.localAddendum.append(ChatMessage(role: .assistant, content: "Previous conversation has been compacted", isCompactBoundary: true))
                        }
                    }

                case .assistant(let assistantMessage):
                    logger.debug("[Stream:UI] event #\(eventCount) .assistant (gap=\(String(format: "%.1f", gap))s, blocks=\(assistantMessage.content.count))")
                    // Extract text only when no text_delta has been received in the current turn.
                    // Normally content_block_delta(text_delta) is the primary path, so this branch rarely executes.
                    updateState(sessionKey) { state in
                        guard state.streamingTail!.textDeltaBuffer.isEmpty else { return }
                        let allMsgs = state.allMessages
                        let afterLastUser = (allMsgs.lastIndex(where: { $0.role == .user }).map { $0 + 1 }) ?? 0
                        let hasStreamedText = allMsgs.suffix(from: afterLastUser).contains {
                            $0.role == .assistant && $0.blocks.contains(where: { $0.isText || $0.isThinking })
                        }
                        guard !hasStreamedText else { return }
                        for block in assistantMessage.content {
                            if case .text(let text) = block, !text.isEmpty {
                                state.streamingTail!.textDeltaBuffer += text
                            }
                        }
                    }

                case .user(let userMessage):
                    logger.debug("[Stream:UI] event #\(eventCount) .user (gap=\(String(format: "%.1f", gap))s, toolUseId=\(userMessage.toolUseId ?? "none"))")
                    updateState(sessionKey) { state in
                        guard let toolUseId = userMessage.toolUseId else { return }
                        state.streamingTail!.pendingToolResults.append((toolUseId, userMessage.content, userMessage.isError))
                        state.streamingTail!.needsNewMessage = true
                    }

                case .result(let resultEvent):
                    logger.info("[Stream:UI] event #\(eventCount) .result (gap=\(String(format: "%.1f", gap))s, isError=\(resultEvent.isError), session=\(resultEvent.sessionId))")

                    // With `--input-format stream-json` the CLI stays alive waiting for more
                    // input. Close stdin on `result` so it exits cleanly.
                    await claude.closeStdin(streamId: streamId)

                    if sessionKey != resultEvent.sessionId {
                        if let state = sessionStates.removeValue(forKey: sessionKey) {
                            sessionStates[resultEvent.sessionId] = state
                        }
                        lastCommittedReloadKey.removeValue(forKey: sessionKey)
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

                    // Promote in-flight tail into committed before disk reload
                    promoteTailToCommitted(for: resultEvent.sessionId)

                    let isFg = (window.currentSessionId ?? window.newSessionKey) == sessionKey
                    if isFg {
                        window.currentSessionId = resultEvent.sessionId
                        if resultEvent.isError {
                            let errText = await claude.consumeStderr(for: streamId) ?? "Claude returned an error."
                            addErrorMessage(errText, in: window)
                        }
                    }

                    await saveSession(
                        sessionId: resultEvent.sessionId,
                        projectId: projectId,
                        messages: stateForSession(sessionKey).allMessages
                    )

                    reloadCommittedFromDisk(sessionId: resultEvent.sessionId, projectId: projectId, cwd: cwd)

                    if !resultEvent.isError {
                        let sid = resultEvent.sessionId
                        let key = sessionKey
                        let cwdCapture = cwd
                        Task { [weak self] in
                            guard let self else { return }
                            if let pct = await claude.fetchContextPercentage(sessionId: sid, cwd: cwdCapture) {
                                updateState(key) { $0.lastTurnContextUsedPercentage = pct }
                                await persistence.updateContextPercent(sessionId: sid, percent: pct)
                            }
                        }

                        if notificationsEnabled && !NSApp.isActive {
                            let title = allSessionSummaries.first(where: { $0.id == resultEvent.sessionId })?.title ?? "New Session"
                            let firstSentence = stateForSession(sessionKey).allMessages
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

            // Consume any remaining stderr — used as error message content below.
            // If already consumed at result.isError time, this returns nil.
            let stderrOutput = await claude.consumeStderr(for: streamId)

            if eventCount == 0 {
                // User cancellation revokes activeStreamId or cancels the task — distinguish
                // that from a real "CLI died with no output" failure.
                let wasCancelled = Task.isCancelled || stateForSession(sessionKey).activeStreamId != streamId
                if !wasCancelled {
                    let errorMsg = stderrOutput ?? "No response received"
                    addErrorMessage(errorMsg, in: window)
                    logger.error("[Stream:UI] no events received — appending error bubble. stderr=\(stderrOutput ?? "nil")")
                } else {
                    logger.debug("[Stream:UI] no events received — suppressed (cancelled). stderr=\(stderrOutput ?? "nil")")
                }
            }

            let isStillOwner = stateForSession(sessionKey).activeStreamId == streamId
            let stillStreaming = stateForSession(sessionKey).isStreaming
            if stillStreaming && isStillOwner {
                logger.warning("[Stream:UI] isStreaming was still true at stream end — forcing cleanup")
                finalizeStreamSession(for: sessionKey)
                // Promote partial tail on forced cleanup
                promoteTailToCommitted(for: sessionKey)

                // If the last assistant message is invisible after cleanup (blocks=[] because
                // all tool calls had empty/nil results), show an error bubble so the user
                // understands what happened rather than seeing no response at all.
                let lastMsg = stateForSession(sessionKey).allMessages.last
                if lastMsg.map({ $0.role == .assistant && $0.blocks.isEmpty }) == true {
                    let errorMsg = stderrOutput ?? "Response was interrupted"
                    updateState(sessionKey) { state in
                        state.localAddendum.append(ChatMessage(role: .assistant, content: errorMsg, isError: true))
                    }
                }

                let msgs = stateForSession(sessionKey).allMessages
                if !msgs.isEmpty {
                    await saveSession(sessionId: sessionKey, projectId: projectId, messages: msgs)
                }
            } else if stillStreaming && !isStillOwner {
                let currentOwner = stateForSession(sessionKey).activeStreamId
                if currentOwner == nil {
                    logger.warning("[Stream:UI] stream \(streamId) ended — no active owner for session, forcing cleanup")
                    finalizeStreamSession(for: sessionKey)
                    // Promote partial tail on forced cleanup
                    promoteTailToCommitted(for: sessionKey)
                    let msgs = stateForSession(sessionKey).allMessages
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

    /// Flush the in-flight thinking-delta buffer into its MessageBlock so the UI
    /// reflects the latest thinking text. Called from the 50ms timer (via
    /// flushPendingUpdates) and on content_block_stop.
    private func flushPendingThinking(for key: String) {
        guard var state = sessionStates[key],
              var tail = state.streamingTail,
              let thinkingId = tail.activeThinkingId,
              !tail.thinkingDeltaBuffer.isEmpty else { return }

        let delta = tail.thinkingDeltaBuffer
        tail.thinkingDeltaBuffer = ""

        if let idx = tail.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            tail.messages[idx].appendThinkingDelta(delta, blockId: thinkingId)
        } else {
            var msg = ChatMessage(role: .assistant, isStreaming: true)
            msg.appendThinkingDelta(delta, blockId: thinkingId)
            tail.messages.append(msg)
        }

        state.streamingTail = tail
        sessionStates[key] = state
    }

    private func flushPendingUpdates(for key: String) {
        flushPendingThinking(for: key)

        guard var state = sessionStates[key] else { return }
        guard var tail = state.streamingTail else { return }

        let hasText = !tail.textDeltaBuffer.isEmpty
        let hasToolResults = !tail.pendingToolResults.isEmpty
        guard hasText || hasToolResults else { return }

        // Phase 1: Apply pending tool results to the last assistant message in tail
        if hasToolResults {
            let results = tail.pendingToolResults
            tail.pendingToolResults = []
            if let idx = tail.messages.indices.last(where: { tail.messages[$0].role == .assistant }) {
                for (toolUseId, content, isError) in results {
                    tail.messages[idx].setToolResult(id: toolUseId, result: content, isError: isError)
                }
            }
        }

        // Phase 2: Flush text delta buffer
        if hasText {
            let buffered = tail.textDeltaBuffer
            tail.textDeltaBuffer = ""

            if tail.needsNewMessage {
                if let idx = tail.messages.indices.last(where: { tail.messages[$0].isStreaming }) {
                    tail.messages[idx].isStreaming = false
                    tail.messages[idx].finalizeToolCalls()
                    Self.stripNoOpText(at: idx, in: &tail.messages)
                }
                tail.needsNewMessage = false
                tail.messages.append(ChatMessage(role: .assistant, content: buffered, isStreaming: true))
            } else if let idx = tail.messages.indices.last(where: { tail.messages[$0].isStreaming && tail.messages[$0].role == .assistant }) {
                tail.messages[idx].appendText(buffered)
            } else {
                tail.messages.append(ChatMessage(role: .assistant, content: buffered, isStreaming: true))
            }
        }

        state.streamingTail = tail
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
                    if state.streamingTail!.needsNewMessage {
                        if let idx = state.streamingTail!.messages.indices.reversed().first(where: { state.streamingTail!.messages[$0].role == .assistant && state.streamingTail!.messages[$0].isStreaming }) {
                            state.streamingTail!.messages[idx].isStreaming = false
                            state.streamingTail!.messages[idx].finalizeToolCalls()
                            Self.stripNoOpText(at: idx, in: &state.streamingTail!.messages)
                        }
                        state.streamingTail!.messages.append(ChatMessage(role: .assistant, isStreaming: true))
                        state.streamingTail!.needsNewMessage = false
                    } else if state.streamingTail!.messages.last?.role != .assistant || !(state.streamingTail!.messages.last?.isStreaming ?? false) {
                        state.streamingTail!.messages.append(ChatMessage(role: .assistant, isStreaming: true))
                    }
                    if let lastIndex = state.streamingTail!.messages.indices.last,
                       state.streamingTail!.messages[lastIndex].role == .assistant {
                        state.streamingTail!.messages[lastIndex].appendToolCall(toolCall)
                    }
                    // Ready to receive input_json_delta
                    state.streamingTail!.activeToolId = id
                    state.streamingTail!.activeToolInputBuffer = ""
                }
            } else if blockType == "text" {
                // New text block started — if needsNewMessage, prepare a new ChatMessage
                updateState(sessionKey) { state in
                    if state.streamingTail!.needsNewMessage {
                        // Keep the flag so a new message is created on the next text_delta flush
                        // (needsNewMessage is handled inside flush)
                    }
                    state.isThinking = false
                    state.streamingTail!.activeToolId = nil
                    state.streamingTail!.activeToolInputBuffer = ""
                }
            } else if blockType == "thinking" || blockType == "redacted_thinking" {
                // Flush any pending text first so thinking blocks land in order.
                flushPendingUpdates(for: sessionKey)
                let thinkingId = (contentBlock["id"] as? String) ?? UUID().uuidString
                updateState(sessionKey) { state in
                    state.streamingTail!.activeToolId = nil
                    state.streamingTail!.activeToolInputBuffer = ""
                    state.isThinking = true
                    // needsNewMessage: opening a new Claude turn after a tool result.
                    if state.streamingTail!.needsNewMessage {
                        if let idx = state.streamingTail!.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                            state.streamingTail!.messages[idx].isStreaming = false
                            state.streamingTail!.messages[idx].finalizeToolCalls()
                            Self.stripNoOpText(at: idx, in: &state.streamingTail!.messages)
                        }
                        state.streamingTail!.messages.append(ChatMessage(role: .assistant, isStreaming: true))
                        state.streamingTail!.needsNewMessage = false
                    } else if state.streamingTail!.messages.last?.role != .assistant || !(state.streamingTail!.messages.last?.isStreaming ?? false) {
                        state.streamingTail!.messages.append(ChatMessage(role: .assistant, isStreaming: true))
                    }
                    state.streamingTail!.activeThinkingId = thinkingId
                    state.streamingTail!.thinkingDeltaBuffer = ""
                    state.streamingTail!.thinkingStartDate = Date()
                    if blockType == "redacted_thinking",
                       let lastIndex = state.streamingTail!.messages.indices.last,
                       state.streamingTail!.messages[lastIndex].role == .assistant {
                        state.streamingTail!.messages[lastIndex].blocks.append(.redactedThinking(id: thinkingId))
                    }
                }
            }

        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return }

            if deltaType == "text_delta", let text = delta["text"] as? String {
                updateState(sessionKey) { state in
                    state.isThinking = false
                    state.streamingTail!.textDeltaBuffer += text
                }
            } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                updateState(sessionKey) { state in
                    state.streamingTail!.activeToolInputBuffer += partial
                }
            } else if deltaType == "thinking_delta", let text = delta["thinking"] as? String {
                updateState(sessionKey) { state in
                    state.isThinking = true
                    state.streamingTail!.thinkingDeltaBuffer += text
                }
            } else if deltaType == "signature_delta" {
                // Cryptographic signature for the thinking block — opaque, never displayed.
                return
            }

        case "content_block_stop":
            // Finalize whichever block just closed — thinking or tool_use.
            flushPendingThinking(for: sessionKey)
            updateState(sessionKey) { state in
                if let thinkingId = state.streamingTail!.activeThinkingId {
                    let duration = state.streamingTail!.thinkingStartDate.map { Date().timeIntervalSince($0) }
                    if let msgIdx = state.streamingTail!.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                        state.streamingTail!.messages[msgIdx].finalizeThinking(blockId: thinkingId, duration: duration)
                    }
                    state.streamingTail!.activeThinkingId = nil
                    state.streamingTail!.thinkingStartDate = nil
                    state.streamingTail!.thinkingDeltaBuffer = ""
                    state.isThinking = false
                    return
                }

                guard let toolId = state.streamingTail!.activeToolId, !state.streamingTail!.activeToolInputBuffer.isEmpty else {
                    state.streamingTail!.activeToolId = nil
                    return
                }
                let buffer = state.streamingTail!.activeToolInputBuffer
                state.streamingTail!.activeToolId = nil
                state.streamingTail!.activeToolInputBuffer = ""

                guard let inputData = buffer.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode([String: JSONValue].self, from: inputData) else { return }

                if let msgIdx = state.streamingTail!.messages.indices.reversed().first(where: { state.streamingTail!.messages[$0].role == .assistant && state.streamingTail!.messages[$0].isStreaming }),
                   let blockIdx = state.streamingTail!.messages[msgIdx].toolCallIndex(id: toolId) {
                    state.streamingTail!.messages[msgIdx].blocks[blockIdx].toolCall?.input = parsed
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
        // Promote partial tail on cancel
        promoteTailToCommitted(for: key)
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
            state.activeStreamId = nil
            state.streamTask = nil
            state.streamingStartDate = nil
            // Drop the in-progress assistant bubble so it doesn't reappear on the next turn.
            if let lastIndex = state.committedMessages.indices.last,
               state.committedMessages[lastIndex].role == .assistant,
               !state.committedMessages[lastIndex].isError,
               !state.committedMessages[lastIndex].isCompactBoundary {
                state.committedMessages.remove(at: lastIndex)
            }
            // Restore the user message that triggered this stream into the input field.
            if let lastIndex = state.committedMessages.indices.last,
               state.committedMessages[lastIndex].role == .user,
               !state.committedMessages[lastIndex].isCompactBoundary {
                let userText = state.committedMessages[lastIndex].blocks.compactMap(\.text).joined()
                state.committedMessages.remove(at: lastIndex)
                window.inputText = userText
            }
        }

        window.showError = false
        window.errorMessage = nil

        // Save messages accumulated up to the point of cancellation to disk (prevent data loss)
        if let project = window.selectedProject {
            let messages = stateForSession(key).allMessages
            if !messages.isEmpty {
                await saveSession(sessionId: key, projectId: project.id, messages: messages)
            }
        }

        // Clean up placeholder session on cancellation
        if let sid = window.currentSessionId, window.pendingPlaceholderIds.contains(sid) {
            allSessionSummaries.removeAll { $0.id == sid }
            window.removePendingPlaceholder(sid)
            sessionStates.removeValue(forKey: sid)
            lastCommittedReloadKey.removeValue(forKey: sid)
            window.currentSessionId = nil
        }
    }

    private func recordStreamingDuration(for key: String) {
        guard let start = sessionStates[key]?.streamingStartDate else { return }
        let duration = Date().timeIntervalSince(start)
        updateState(key) { state in
            state.streamingStartDate = nil
            if var tail = state.streamingTail,
               let idx = tail.messages.indices.reversed().first(where: { tail.messages[$0].role == .assistant }) {
                tail.messages[idx].duration = duration
                state.streamingTail = tail
            } else if let idx = state.committedMessages.indices.reversed().first(where: { state.committedMessages[$0].role == .assistant }) {
                state.committedMessages[idx].duration = duration
            }
        }
    }

    // MARK: - Permission Response

    func respondToPermission(_ request: PermissionRequest, decision: PermissionDecision, in window: WindowState) async {
        await permission.respond(toolUseId: request.id, decision: decision)
        window.pendingPermissions.removeAll { $0.id == request.id }
    }

    // MARK: - AskUserQuestion Response

    /// Deliver the user's answer for an AskUserQuestion tool call via the PreToolUse hook.
    ///
    /// AskUserQuestion is handled like any other PreToolUse hook: the PermissionServer is
    /// holding the HTTP connection open waiting for a decision. We resolve it with `allow` +
    /// `updatedInput: {questions, answers: {questionText: selectedLabel}}` so the CLI injects
    /// the answer into the tool input and proceeds.
    func respondToAskUserQuestion(toolUseId: String, optionLabel: String, in window: WindowState) async {
        let key = window.currentSessionId ?? window.newSessionKey

        // Build updatedInput from the tool call's original input, and reflect the answer
        // locally in one pass so the UI updates immediately. The CLI will emit its own
        // tool_result shortly, overwriting the optimistic value.
        var updatedInput = JSONValue.object([
            "questions": .array([]),
            "answers": .object([:]),
        ])
        updateState(key) { state in
            // Tool call is in the streaming tail during an active session.
            if var tail = state.streamingTail {
                for i in tail.messages.indices.reversed() {
                    guard let idx = tail.messages[i].toolCallIndex(id: toolUseId),
                          let toolInput = tail.messages[i].blocks[idx].toolCall?.input else { continue }
                    let questionText = AskUserQuestion(input: toolInput)?.questions.first?.question ?? "question"
                    updatedInput = .object([
                        "questions": toolInput["questions"] ?? .array([]),
                        "answers": .object([questionText: .string(optionLabel)]),
                    ])
                    tail.messages[i].setToolResult(id: toolUseId, result: optionLabel, isError: false)
                    state.streamingTail = tail
                    return
                }
            }
            for i in state.committedMessages.indices.reversed() {
                guard let idx = state.committedMessages[i].toolCallIndex(id: toolUseId),
                      let toolInput = state.committedMessages[i].blocks[idx].toolCall?.input else { continue }
                let questionText = AskUserQuestion(input: toolInput)?.questions.first?.question ?? "question"
                updatedInput = .object([
                    "questions": toolInput["questions"] ?? .array([]),
                    "answers": .object([questionText: .string(optionLabel)]),
                ])
                state.committedMessages[i].setToolResult(id: toolUseId, result: optionLabel, isError: false)
                return
            }
        }

        await permission.respondAskUserQuestion(toolUseId: toolUseId, updatedInput: updatedInput)
    }

    // MARK: - Project Management

    func addProject(name: String, path: String, gitHubRepo: String?) async {
        guard !projects.contains(where: { $0.path == path }) else { return }
        let project = Project(name: name, path: path, gitHubRepo: gitHubRepo)
        projects.append(project)
        watchProjectDirectory(project)
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
           !state.allMessages.isEmpty {
            let existing = allSessionSummaries.first(where: { $0.id == currentId })
            let title = existing?.title ?? "Session"
            let session = ChatSession(id: currentId, projectId: currentProject.id, title: title, messages: state.allMessages, updatedAt: lastResponseDate(from: state.allMessages), isCompleted: existing?.isCompleted ?? false)
            Task {
                do { try await self.persistence.saveSession(session) }
                catch { self.logger.error("Failed to save current session before project switch: \(error.localizedDescription)") }
            }
        }

        // animation: nil — all mutations land in the same frame; sessionStates.filter fires
        // one @Observable notification instead of N removeValue calls.
        withAnimation(nil) {
            window.selectedProject = project
            sessionStates = sessionStates.filter { $0.value.isStreaming }
            window.currentSessionId = nil
            startNewChat(in: window)
        }

        UserDefaults.standard.set(project.id.uuidString, forKey: "selectedProjectId")

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

    private func addAndSelectProject(name: String, path: String, gitHubRepo: String? = nil, in window: WindowState) async {
        if let existing = projects.first(where: { $0.path == path }) {
            selectProject(existing, in: window)
            return
        }
        await addProject(name: name, path: path, gitHubRepo: gitHubRepo)
        if let project = projects.last {
            selectProject(project, in: window)
        }
    }

    // MARK: - Session Management

    /// One-time migration: converts legacy Clarc JSON sessions to CLI-compatible jsonl files.
    /// Skips sessions whose jsonl already exists in ~/.claude/projects/{enc(cwd)}/.
    /// Renames successfully converted .json → .json.migrated so they are not re-processed.
    private func migrateLegacySessions(_ legacySummaries: [ChatSession.Summary]) async {
        guard !legacySummaries.isEmpty else { return }

        let projectsSnapshot = await MainActor.run { self.projects }
        let projectMap = Dictionary(uniqueKeysWithValues: projectsSnapshot.map { ($0.id, $0) })

        let fm = FileManager.default
        var cwdDirCache: [String: URL] = [:]

        for summary in legacySummaries {
            guard let project = projectMap[summary.projectId] else { continue }
            let cwd = project.path

            if cwdDirCache[cwd] == nil {
                cwdDirCache[cwd] = await cliStore.directory(forCwd: cwd)
            }
            let destDir = cwdDirCache[cwd]!
            let destURL = destDir.appendingPathComponent("\(summary.id).jsonl")
            guard !fm.fileExists(atPath: destURL.path) else { continue }

            guard let session = persistence.loadLegacySessionSync(projectId: summary.projectId, sessionId: summary.id) else { continue }

            do {
                let jsonlData = try LegacyMigrator.toJSONL(session: session, cwd: cwd)
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                try jsonlData.write(to: destURL, options: .atomic)

                await metaStore.save(
                    sessionId: summary.id,
                    meta: SessionMetaStore.Meta(
                        title: summary.title == ChatSession.defaultTitle ? nil : summary.title,
                        isPinned: summary.isPinned,
                        isCompleted: summary.isCompleted,
                        model: summary.model,
                        effort: summary.effort,
                        permissionMode: summary.permissionMode,
                        updatedAt: summary.updatedAt
                    )
                )

                let sourceURL = persistence.legacySessionURL(projectId: summary.projectId, sessionId: summary.id)
                let migratedURL = sourceURL.deletingPathExtension().appendingPathExtension("json.migrated")
                try fm.moveItem(at: sourceURL, to: migratedURL)
                logger.info("Migrated legacy session \(summary.id, privacy: .public) to CLI jsonl")
            } catch {
                logger.error("Failed to migrate session \(summary.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// CLI-backed summaries for one project, with any not-yet-migrated legacy sessions merged in.
    /// CLI wins on duplicate id. Legacy sessions disappear once migrated to jsonl.
    private func mergedSummaries(for project: Project) async -> [ChatSession.Summary] {
        async let legacy = persistence.loadLegacySessions(for: project.id)
        async let cli = cliStore.loadSummaries(cwd: project.path, projectId: project.id)
        let (cliResult, legacyResult) = await (cli, legacy)
        let cliIDs = Set(cliResult.map { $0.id })
        return (cliResult + legacyResult.filter { !cliIDs.contains($0.id) })
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// CLI-backed summaries across all projects, with any not-yet-migrated legacy sessions merged in.
    private func mergedSummariesAcrossProjects() async -> [ChatSession.Summary] {
        async let legacyAcrossAll = persistence.loadAllLegacySessionSummaries()
        async let metaCache = cliStore.loadMetaCache()
        let (legacy, meta) = await (legacyAcrossAll, metaCache)

        let snapshot = projects
        let cli: [ChatSession.Summary] = await withTaskGroup(of: [ChatSession.Summary].self) { group in
            for project in snapshot {
                group.addTask {
                    await self.cliStore.loadSummaries(cwd: project.path, projectId: project.id, metaCache: meta)
                }
            }
            var collected: [ChatSession.Summary] = []
            for await batch in group { collected.append(contentsOf: batch) }
            return collected
        }

        let cliIDs = Set(cli.map { $0.id })
        return (cli + legacy.filter { !cliIDs.contains($0.id) })
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Load/refresh the project's session list into allSessionSummaries
    func loadSessionHistory(in window: WindowState) async {
        guard let project = window.selectedProject else { return }
        await reloadSessionSummaries(for: project)
    }

    /// Window-independent reload — used by the FS watcher when the CLI (or
    /// another process) modifies a project's jsonl directory out-of-band.
    /// Bails without touching `allSessionSummaries` if the disk view matches
    /// the in-memory slice; otherwise SwiftUI would re-render on every
    /// self-write event.
    private func reloadSessionSummaries(for project: Project) async {
        let loaded = await mergedSummaries(for: project)

        // The sidecar fields (pin/complete/model/effort/permissionMode) are
        // owned solely by Clarc, so for a session already in memory the
        // in-memory value is never staler than disk. This reload only exists to
        // pick up CLI-side jsonl changes, so carry those Clarc-owned fields over
        // from memory — otherwise a watcher reload that races a just-issued
        // toggle (e.g. mark-complete) re-reads the sidecar before its write has
        // flushed and clobbers the correct in-memory state with stale disk data.
        let inMemory = Dictionary(
            allSessionSummaries.lazy.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let summaries = loaded.map { summary -> ChatSession.Summary in
            guard let mem = inMemory[summary.id] else { return summary }
            var merged = summary
            merged.isPinned = mem.isPinned
            merged.isCompleted = mem.isCompleted
            merged.model = mem.model
            merged.effort = mem.effort
            merged.permissionMode = mem.permissionMode
            return merged
        }

        let existing = allSessionSummaries
            .filter { $0.projectId == project.id }
            .sorted { $0.updatedAt > $1.updatedAt }
        if existing == summaries { return }
        allSessionSummaries.removeAll { $0.projectId == project.id }
        allSessionSummaries.append(contentsOf: summaries)
    }

    // MARK: - CLI directory watch

    /// Subscribe to filesystem changes in a project's CLI jsonl directory.
    /// Idempotent — safe to call repeatedly. Silent no-op if the directory
    /// hasn't been created yet; `send()` re-attempts after that point.
    private func watchProjectDirectory(_ project: Project) {
        let projectId = project.id
        let cwd = project.path
        Task { [weak self] in
            guard let self else { return }
            // cliStore.directory consults the cwd-index that survives the
            // lossy slash/dot encoding — required for cwds containing dots.
            let dir = await self.cliStore.directory(forCwd: cwd)
            await self.directoryWatcher.watch(url: dir) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          let p = self.projects.first(where: { $0.id == projectId }) else { return }
                    await self.reloadSessionSummaries(for: p)
                    self.reloadActiveSessionsForProject(projectId: projectId, cwd: cwd)
                }
            }
        }
    }

    private func reloadActiveSessionsForProject(projectId: UUID, cwd: String) {
        // Only reload sessions actually loaded into memory (a window has touched them).
        for (sid, state) in sessionStates {
            guard !state.isStreaming else { continue }
            guard let summary = allSessionSummaries.first(where: { $0.id == sid }),
                  summary.projectId == projectId else { continue }
            reloadCommittedFromDisk(sessionId: sid, projectId: projectId, cwd: cwd)
        }
    }

    private func unwatchProjectDirectory(_ project: Project) {
        let cwd = project.path
        Task { [weak self] in
            guard let self else { return }
            let dir = await self.cliStore.directory(forCwd: cwd)
            await self.directoryWatcher.unwatch(url: dir)
        }
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
            state.effort = session.effort
            state.permissionMode = session.permissionMode
            // Restore persisted status-bar stats so they show immediately on open,
            // before any new response. The context % falls through to the CLI
            // fetch below only when it was never persisted.
            state.lastTurnContextUsedPercentage = session.contextPercent
            state.durationMs = session.totalDurationMs ?? 0
            if let msgs = loadedMessages {
                state.committedMessages = cleanLoadedMessages(msgs)
            }
            sessionStates[session.id] = state
            // Stale reload cache would cause reloadCommittedFromDisk to skip parsing when messages are empty.
            lastCommittedReloadKey.removeValue(forKey: session.id)
        } else {
            if var state = sessionStates[session.id] {
                if state.model == nil { state.model = session.model }
                if state.effort == nil { state.effort = session.effort }
                if state.permissionMode == nil { state.permissionMode = session.permissionMode }
                sessionStates[session.id] = state
            }
        }

        // Always reload from disk — disk is the source of truth.
        // reloadCommittedFromDisk is a no-op when the session is actively streaming.
        if let project = window.selectedProject {
            reloadCommittedFromDisk(sessionId: session.id, projectId: project.id, cwd: project.path)
        }

        if sessionStates[session.id]?.isStreaming == true {
            flushPendingUpdates(for: session.id)
        }

        window.currentSessionId = session.id

        // The context % lives only in memory, so a session opened from history
        // shows no value until its next response. Fetch it once on switch (CLI
        // resume) so the status bar fills in immediately, mirroring the
        // post-response path. Skip empty placeholders and legacy sessions, which
        // have nothing to resume.
        if session.origin == .cliBacked,
           !window.pendingPlaceholderIds.contains(session.id),
           sessionStates[session.id]?.lastTurnContextUsedPercentage == nil,
           let cwd = window.selectedProject?.path {
            let sid = session.id
            Task { [weak self] in
                guard let self else { return }
                if let pct = await self.claude.fetchContextPercentage(sessionId: sid, cwd: cwd) {
                    self.updateState(sid) { $0.lastTurnContextUsedPercentage = pct }
                    await self.persistence.updateContextPercent(sessionId: sid, percent: pct)
                }
            }
        }

        window.sessionModel = sessionStates[session.id]?.model ?? session.model
        window.sessionEffort = sessionStates[session.id]?.effort ?? session.effort
        window.sessionPermissionMode = sessionStates[session.id]?.permissionMode ?? session.permissionMode
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
        let outgoingState = sessionStates[outgoingId]
        let outgoingMessages = outgoingState?.allMessages ?? []
        Task { [weak self] in
            guard let self else { return }
            if !outgoingMessages.isEmpty, let project = window.selectedProject {
                let existing = allSessionSummaries.first(where: { $0.id == outgoingId })
                let title = existing?.title ?? "Session"
                // Carry over the Clarc-owned sidecar fields and status-bar stats so
                // leaving a session doesn't clobber them — saveSession overwrites the
                // whole meta file, so omitting these would persist nil and wipe the
                // cumulative duration / context % on the next reload.
                let outgoing = ChatSession(
                    id: outgoingId,
                    projectId: project.id,
                    title: title,
                    messages: outgoingMessages,
                    updatedAt: lastResponseDate(from: outgoingMessages),
                    isCompleted: existing?.isCompleted ?? false,
                    model: outgoingState?.model ?? existing?.model,
                    effort: outgoingState?.effort ?? existing?.effort,
                    permissionMode: outgoingState?.permissionMode ?? existing?.permissionMode,
                    origin: existing?.origin ?? .cliBacked,
                    contextPercent: outgoingState?.lastTurnContextUsedPercentage ?? existing?.contextPercent,
                    totalDurationMs: [outgoingState?.durationMs, existing?.totalDurationMs].compactMap { $0 }.max()
                )
                do { try await persistence.saveSession(outgoing) }
                catch { logger.error("Failed to save outgoing session: \(error.localizedDescription)") }
            }
            if window.currentSessionId != outgoingId {
                sessionStates.removeValue(forKey: outgoingId)
                lastCommittedReloadKey.removeValue(forKey: outgoingId)
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
        window.sessionEffort = nil
        window.sessionPermissionMode = nil
        sessionStates.removeValue(forKey: window.newSessionKey)
        lastCommittedReloadKey.removeValue(forKey: window.newSessionKey)
        window.inputText = window.draftTexts["new"] ?? ""
        window.messageQueue = window.draftQueues["new"] ?? []
        window.requestInputFocus = true
    }

    func renameSession(_ session: ChatSession, to newTitle: String) async {
        if let si = allSessionSummaries.firstIndex(where: { $0.id == session.id }) {
            allSessionSummaries[si].title = newTitle
        }
        await updateSessionMetadata(session, persistTitle: true) { $0.title = newTitle }
    }

    func togglePinSession(_ session: ChatSession) async {
        guard let si = allSessionSummaries.firstIndex(where: { $0.id == session.id }) else { return }
        allSessionSummaries[si].isPinned.toggle()
        let newIsPinned = allSessionSummaries[si].isPinned
        await updateSessionMetadata(session) { $0.isPinned = newIsPinned }
    }

    func toggleCompleteSession(id: String) async {
        guard let si = allSessionSummaries.firstIndex(where: { $0.id == id }) else { return }
        allSessionSummaries[si].isCompleted.toggle()
        let updated = allSessionSummaries[si]
        await updateSessionMetadata(updated.makeSession()) { $0.isCompleted = updated.isCompleted }
    }

    /// Persist a metadata-only edit (title, pin, etc.) routing by session
    /// origin. cliBacked sessions go to the sidecar; legacy sessions need the
    /// full message log to be re-saved alongside the change.
    /// `persistTitle` should be true only for explicit user renames; pin and
    /// other non-title edits leave the sidecar title untouched so it stays
    /// in sync with the CLI's first-message-derived label.
    private func updateSessionMetadata(
        _ session: ChatSession,
        persistTitle: Bool = false,
        mutate: (inout ChatSession) -> Void
    ) async {
        let summary = allSessionSummaries.first(where: { $0.id == session.id }) ?? session.summary
        var updated: ChatSession = switch summary.origin {
        case .cliBacked:
            summary.makeSession()
        case .legacyClarc:
            persistence.loadLegacySessionSync(projectId: session.projectId, sessionId: session.id) ?? session
        }
        mutate(&updated)
        do { try await persistence.saveSession(updated, persistTitle: persistTitle) }
        catch { logger.error("Failed to save session metadata: \(error.localizedDescription)") }
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

        unwatchProjectDirectory(project)

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
            detachCurrentStream(in: window)
            startNewChat(in: window)
        }
        let origin = allSessionSummaries.first(where: { $0.id == session.id })?.origin ?? session.origin
        let cwd = projects.first(where: { $0.id == session.projectId })?.path
        do {
            try await persistence.deleteSession(projectId: session.projectId, sessionId: session.id, origin: origin, cwd: cwd)
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription)")
        }
        allSessionSummaries.removeAll { $0.id == session.id }
        sessionStates.removeValue(forKey: session.id)
        lastCommittedReloadKey.removeValue(forKey: session.id)
    }

    func deleteAllSessions(projectId: UUID? = nil, in window: WindowState) async {
        let toDelete: [ChatSession.Summary]
        if let projectId {
            toDelete = allSessionSummaries.filter { $0.projectId == projectId }
        } else {
            toDelete = allSessionSummaries
        }
        let ids = Set(toDelete.map(\.id))

        // Only disrupt the current window's stream if its session is actually
        // being deleted — otherwise a project-scoped delete would clobber an
        // unrelated streaming session.
        if let currentId = window.currentSessionId, ids.contains(currentId) {
            detachCurrentStream(in: window)
            startNewChat(in: window)
        }

        for summary in toDelete {
            let cwd = projects.first(where: { $0.id == summary.projectId })?.path
            do {
                try await persistence.deleteSession(
                    projectId: summary.projectId,
                    sessionId: summary.id,
                    origin: summary.origin,
                    cwd: cwd
                )
            } catch {
                logger.error("Failed to delete session \(summary.id): \(error.localizedDescription)")
            }
        }

        allSessionSummaries.removeAll { ids.contains($0.id) }
        for id in ids {
            sessionStates.removeValue(forKey: id)
            lastCommittedReloadKey.removeValue(forKey: id)
        }
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
                let session = s.makeSession()
                if sessionStates[session.id] == nil,
                   let full = await persistence.loadFullSession(summary: s, cwd: project.path) {
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
        guard !projects.contains(where: { $0.path == project.path }) else { return }
        projects.append(project)
        watchProjectDirectory(project)
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

    /// Build the routing summary for `persistence.loadFullSession`. Falls back
    /// to a synthesized `.cliBacked` summary when the session hasn't been
    /// indexed yet (e.g. brand-new session whose `.result` arrived before the
    /// summary list refresh).
    private func summaryFor(sessionId: String, projectId: UUID) -> ChatSession.Summary {
        allSessionSummaries.first(where: { $0.id == sessionId })
            ?? ChatSession.Summary(
                id: sessionId, projectId: projectId, title: "",
                createdAt: Date(), updatedAt: Date(), isPinned: false,
                origin: .cliBacked
            )
    }

    /// Reloads committed messages from the CLI's jsonl, unconditionally replacing
    /// `committedMessages`. Skipped only when the session is actively streaming
    /// (tail holds the in-progress turn). Safe to call from any trigger.
    private func reloadCommittedFromDisk(sessionId: String, projectId: UUID, cwd: String) {
        let summary = summaryFor(sessionId: sessionId, projectId: projectId)
        let lastKey = lastCommittedReloadKey[sessionId]

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let url = await self.cliStore.directory(forCwd: cwd)
                .appendingPathComponent("\(sessionId).jsonl")
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let currentSize: UInt64? = (attrs?[.size] as? Int).flatMap(UInt64.init(exactly:))
            let currentMtime = attrs?[.modificationDate] as? Date

            // Skip parse only when file is byte-for-byte unchanged (size AND mtime match).
            // Any change — including shrink — triggers a fresh parse.
            if let lastKey, let currentSize, let currentMtime,
               ReloadCacheKey(size: currentSize, mtime: currentMtime) == lastKey {
                return
            }

            guard let full = await self.persistence.loadFullSession(summary: summary, cwd: cwd) else { return }
            let cleaned = await self.cleanLoadedMessages(full.messages)
            await MainActor.run {
                guard var state = self.sessionStates[sessionId],
                      !state.isStreaming else { return }
                if let currentSize, let currentMtime {
                    self.lastCommittedReloadKey[sessionId] = ReloadCacheKey(size: currentSize, mtime: currentMtime)
                }
                // Common no-op reload (disk unchanged from what we show): skip the
                // reconcile + rebuild entirely.
                guard cleaned != state.committedMessages else { return }
                // Disk owns the content; carry over the prior render's ids so a
                // live stream's random ids don't get swapped for CLI-derived ones,
                // which would re-key every row and flicker the chat.
                let reconciled = ChatMessage.reconcilingIdentity(cleaned, from: state.committedMessages)
                guard reconciled != state.committedMessages else { return }
                state.committedMessages = reconciled
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
            messages: stateForSession(sessionId).allMessages
        )
    }

    private func saveSession(sessionId: String, projectId: UUID, messages: [ChatMessage]) async {
        guard !messages.isEmpty else { return }

        let existing = allSessionSummaries.first(where: { $0.id == sessionId })

        // Preserve the existing title (which may have been renamed by the user).
        // Only auto-generate a title when no summary exists yet for this session.
        let title: String
        if let existing, !existing.title.isEmpty {
            title = existing.title
        } else {
            let firstUserContent = messages.first(where: { $0.role == .user })?.content
            title = firstUserContent.map { $0.count > 50 ? String($0.prefix(50)) + "..." : $0 } ?? "New Session"
        }

        let sessionModel = sessionStates[sessionId]?.model
        let sessionEffort = sessionStates[sessionId]?.effort
        let sessionPermissionMode = sessionStates[sessionId]?.permissionMode
        let origin = existing?.origin ?? .cliBacked
        let isCompleted = existing?.isCompleted ?? false
        // Persist the status-bar stats so they survive session switches and app
        // restarts. The context % may still be nil here (it arrives async after a
        // response) and is patched in separately via updateContextPercent.
        let contextPercent = sessionStates[sessionId]?.lastTurnContextUsedPercentage ?? existing?.contextPercent
        // Cumulative duration grows monotonically across a session. The in-memory
        // state.durationMs can transiently read 0 — e.g. right after a session switch
        // recreates the stream state, or before a restored value lands — and a save in
        // that window must not clobber the larger persisted total. Take the max of the
        // live value and the previously persisted summary value.
        let totalDurationMs = [sessionStates[sessionId]?.durationMs, existing?.totalDurationMs]
            .compactMap { $0 }
            .max()
        let session = ChatSession(id: sessionId, projectId: projectId, title: title, messages: messages, updatedAt: lastResponseDate(from: messages), isCompleted: isCompleted, model: sessionModel, effort: sessionEffort, permissionMode: sessionPermissionMode, origin: origin, contextPercent: contextPercent, totalDurationMs: totalDurationMs)

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
            state.committedMessages.append(ChatMessage(role: .user, content: displayText, attachments: resolvedAttachments))
            state.isStreaming = true
            state.activeStreamId = streamId
            state.streamingStartDate = Date()
            state.streamingTail = StreamingTail()
        }

        await permission.refreshRunToken()

        let currentPermissionMode = sessionStates[sessionKey]?.permissionMode ?? permissionMode
        // Always register the hook file: bypassPermissions still needs it for AskUserQuestion.
        var hookSettingsPath: String?
        do { hookSettingsPath = try await permission.writeHookSettingsFile(permissionMode: currentPermissionMode) }
        catch { logger.error("Failed to write hook settings for background queue: \(error.localizedDescription)") }

        await permission.registerSession(sid: sessionKey, projectKey: cwd, mode: currentPermissionMode)

        let model = sessionStates[sessionKey]?.model ?? selectedModel
        let effort = sessionStates[sessionKey]?.effort ?? (selectedEffort == "auto" ? nil : selectedEffort)
        let task = Task { [weak self, window] in
            guard let self else { return }
            await self.processStream(
                streamId: streamId,
                prompt: prompt,
                cwd: cwd,
                cliSessionId: sessionKey,
                internalSessionKey: sessionKey,
                model: model,
                effort: effort,
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
        updateState(key) { $0.localAddendum.append(msg) }
    }

    // MARK: - Claude Settings Reader

    private nonisolated static func readPermissionModeFromSettings() -> PermissionMode {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let permissions = json["permissions"] as? [String: Any],
           let mode = permissions["defaultMode"] as? String,
           let parsed = PermissionMode(rawValue: mode) {
            return parsed
        }
        if let saved = UserDefaults.standard.string(forKey: "selectedPermissionMode"),
           let parsed = PermissionMode(rawValue: saved) {
            return parsed
        }
        return .default
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
