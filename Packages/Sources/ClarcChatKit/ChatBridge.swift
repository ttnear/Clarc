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
    /// The phase of the in-flight content block (e.g. thinking / toolUse /
    /// toolResult / text). Pushed by AppState at each `content_block_start`
    /// event so the UI can label and auto-collapse completed non-text phases.
    public var currentPhase: StreamPhase?
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
