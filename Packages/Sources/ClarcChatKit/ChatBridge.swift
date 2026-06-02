// Modifications Copyright 2026 dttxorg (MiniClarc).
// SPDX-License-Identifier: Apache-2.0
//
// Originally: Clarc (https://github.com/ttnear/Clarc), Apache License 2.0.
// See ../../NOTICE in the repository root for the full modification history.

import Foundation
import ClarcCore

/// Per-window observable bridge between chat views (ClarcChatKit) and the app-layer services.
///
/// The app target creates one `ChatBridge` per window, sets up action handlers, and keeps the
/// streaming state properties updated. Chat views consume this object via the SwiftUI environment.
@Observable
@MainActor
public final class ChatBridge {

    // MARK: - Streaming State (pushed by AppState)

    public var messages: [ChatMessage] = []
    public var isStreaming: Bool = false
    public var isThinking: Bool = false
    /// Per-turn summaries for completed assistant turns, oldest first. Pushed
    /// by AppState when `finalizeStreamSession` runs. The most recent (last
    /// element) is the "current phase" — its messages stream live and its
    /// summary is generated on completion. Older entries are auto-collapsed
    /// in the UI by default; the user can expand any one to inspect.
    public var phaseSummaries: [PhaseSummary] = []
    public var streamingStartDate: Date?
    public var lastTurnContextUsedPercentage: Double?
    public var modelDisplayName: String = ""
    public var sessionStats: ChatSessionStats = ChatSessionStats()
    public var autoPreviewSettings: AttachmentAutoPreviewSettings = AttachmentAutoPreviewSettings()

    // MARK: - Action Handlers (set up by the app target)

    public var sendHandler: (() async -> Void)?
    public var cancelStreamingHandler: (() async -> Void)?
    public var sendSlashCommandHandler: ((String) async -> Void)?
    public var runTerminalCommandHandler: ((String) async -> Void)?
    public var editAndResendHandler: ((UUID, String) async -> Void)?
    public var forkFromHereHandler: ((UUID) async -> Void)?
    public var fetchRateLimitHandler: (() async -> RateLimitUsage?)?

    // MARK: - Init

    public init() {}

    // MARK: - Action Methods

    public func send() async {
        await sendHandler?()
    }

    public func cancelStreaming() async {
        await cancelStreamingHandler?()
    }

    public func sendSlashCommand(_ command: String) async {
        await sendSlashCommandHandler?(command)
    }

    public func runTerminalCommand(_ command: String) async {
        await runTerminalCommandHandler?(command)
    }

    public func editAndResend(messageId: UUID, newContent: String) async {
        await editAndResendHandler?(messageId, newContent)
    }

    public func forkFromHere(messageId: UUID) async {
        await forkFromHereHandler?(messageId)
    }

    public func fetchRateLimit() async -> RateLimitUsage? {
        await fetchRateLimitHandler?()
    }
}
