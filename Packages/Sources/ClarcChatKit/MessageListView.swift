// Modifications Copyright 2026 dttxorg (MiniClarc).
// SPDX-License-Identifier: Apache-2.0
//
// Originally: Clarc (https://github.com/ttnear/Clarc), Apache License 2.0.
// See ../../NOTICE in the repository root for the full modification history.

import SwiftUI
import Combine
import ClarcCore

/// Message scroll area — extracted from ChatView to isolate @Observable dependencies on `messages`.
struct MessageListView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    @State private var scrollPosition = ScrollPosition()
    @State private var settledItems: [ChatMessage] = []
    @State private var scrollTask: Task<Void, Never>?
    @State private var isNearBottom = true
    @State private var isOlderCollapsed = true
    @State private var isSessionReady = false

    /// Read fold threshold from the per-window mirror. 0 disables folding.
    private var foldThreshold: Int { windowState.foldThreshold }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Fold older messages when count exceeds threshold.
                // (foldThreshold == 0 disables folding entirely — show everything.)
                if windowState.foldThreshold > 0 && settledItems.count > foldThreshold {
                    let hiddenCount = settledItems.count - foldThreshold

                    // Expanded state: show older messages
                    if !isOlderCollapsed {
                        messageRows(settledItems.prefix(hiddenCount))
                    }

                    // Fold toggle button
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isOlderCollapsed.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Group {
                                if isOlderCollapsed {
                                    Text(String(format: String(localized: "Show %lld earlier messages", bundle: .module), hiddenCount))
                                } else {
                                    Text("Collapse earlier messages", bundle: .module)
                                }
                            }
                            .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                            Image(systemName: isOlderCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                        }
                        .foregroundStyle(ClaudeTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                                .fill(ClaudeTheme.surfacePrimary.opacity(0.6))
                        )
                    }
                    .buttonStyle(.plain)

                    messageRows(settledItems.suffix(foldThreshold))
                } else {
                    messageRows(settledItems[...])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Streaming view is outside VStack — text deltas don't affect settled layout
            VStack(spacing: 16) {
                // Tier 1: always render streaming content. The previous
                // `if !windowState.focusMode` guard made the screen freeze
                // when focus mode was on, because the user saw no streaming
                // updates at all. The focus-mode filter on `settledItems`
                // (see settledOnlyMessages) is the only thing focus mode
                // should affect.
                StreamingMessageView {
                    rebuildSettledItems()
                    if isNearBottom { scrollToBottomDebounced() }
                }

                if chatBridge.isStreaming {
                    HStack(alignment: .top, spacing: 0) {
                        StreamingIndicatorView(
                            isThinking: chatBridge.isThinking,
                            startDate: chatBridge.streamingStartDate
                        )
                        Spacer(minLength: 40)
                    }
                }

                if !chatBridge.isStreaming && !settledItems.isEmpty {
                    WebPreviewButton(messages: settledItems)
                        .id("web-preview")
                }
            }
            .padding(.horizontal, 20)
            // Suppress layout animations when switching sessions so the pulse indicator
            // doesn't visually jump as StreamingMessageView changes height.
            .animation(.none, value: windowState.currentSessionId)

            Color.clear.frame(height: 1)
                .padding(.bottom, 16)
        }
        .opacity(isSessionReady ? 1 : 0)
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geo in
            let distanceFromBottom = geo.contentSize.height - geo.visibleRect.maxY
            return distanceFromBottom < 120
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
        .task(id: windowState.currentSessionId) {
            isSessionReady = false
            scrollTask?.cancel()
            isOlderCollapsed = true
            scrollPosition = ScrollPosition()
            rebuildSettledItems()
            // Skip scroll/fade delay for empty sessions — appear instantly
            guard !settledItems.isEmpty else {
                isSessionReady = true
                return
            }
            try? await Task.sleep(for: .milliseconds(16))  // 1 frame: scroll after VStack layout is committed
            scrollPosition.scrollTo(edge: .bottom)
            // Pre-set isNearBottom so streaming messages that arrive before onScrollGeometryChange
            // fires still trigger scrollToBottomDebounced(), keeping the pulse pinned to the bottom.
            isNearBottom = true
            try? await Task.sleep(for: .milliseconds(32))  // 2 frames: fade-in after scroll settles
            withAnimation(.easeIn(duration: 0.15)) { isSessionReady = true }
        }
        // Tier 1 (part 2): text deltas don't change messages.count, so the
        // existing onChange-of-count trigger never fires while only text is
        // streaming. This timer drives a periodic settled-list refresh at the
        // same 50ms cadence as AppState.flushTask upstream, so settledItems
        // stays in sync with the live streaming tail.
        .task(id: chatBridge.isStreaming) {
            guard chatBridge.isStreaming else { return }
            while !Task.isCancelled && chatBridge.isStreaming {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                rebuildSettledItems()
            }
        }
        .onChange(of: chatBridge.isStreaming) { old, new in
            // Only update when streaming ends — settled list doesn't change at start, so skip
            if old && !new {
                rebuildSettledItems()
                scrollToBottomDebounced()
            }
        }
        .overlay {
            if settledItems.isEmpty && !chatBridge.isStreaming && windowState.currentSessionId == nil {
                EmptySessionView()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func messageRows(_ messages: some RandomAccessCollection<ChatMessage>) -> some View {
        let groups = groupMessages(Array(messages))
        ForEach(groups) { group in
            if group.isPhaseGroup, let phase = group.phase {
                PhaseGroupSummaryView(group: group, phase: phase)
                    .id(group.id)
            } else if group.isTransientGroup {
                TransientGroupSummaryView(messages: group.messages)
                    .id(group.id)
            } else if let message = group.messages.first {
                MessageBubble(message: message)
                    .id(message.id)
            }
        }
    }

    // MARK: - Message Grouping

    // MARK: - Settled Items

    private func rebuildSettledItems() {
        let messages = settledOnlyMessages(from: chatBridge.messages)
        var t = Transaction()
        t.animation = nil
        withTransaction(t) { settledItems = messages }
    }

    /// If streaming, returns only completed messages excluding the last consecutive (non-error) assistant sequence.
    /// If not streaming, returns all messages without the streaming flag.
    /// In focus mode, further filters to only user messages and completed assistant responses.
    private func settledOnlyMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        var settled: [ChatMessage]
        if messages.last?.isStreaming == true {
            let boundary = streamingBoundaryIndex(in: messages)
            settled = Array(messages[..<boundary]).filter { !$0.isStreaming }
        } else {
            settled = messages.filter { !$0.isStreaming }
        }
        if windowState.focusMode {
            settled = settled.filter { $0.role == .user || $0.isResponseComplete || $0.isCompactBoundary }
        }
        return settled
    }

    private func scrollToBottomDebounced() {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            scrollPosition.scrollTo(edge: .bottom)
        }
    }
}

// MARK: - Message Grouping Helpers

/// Single-pass partition of messages into (settled, streaming) without scanning the array twice.
fileprivate func partitionByStreaming(_ messages: [ChatMessage]) -> (settled: [ChatMessage], streaming: [ChatMessage]) {
    var settled: [ChatMessage] = []
    var streaming: [ChatMessage] = []
    for m in messages { if m.isStreaming { streaming.append(m) } else { settled.append(m) } }
    return (settled, streaming)
}


struct MessageGroup: Identifiable {
    let id: UUID
    let messages: [ChatMessage]
    let isTransientGroup: Bool
    /// Tier 3: when true, this group is a phase-collapsed roll-up of one or
    /// more completed assistant messages whose `completedPhase` is non-text
    /// (thinking / toolUse / toolResult). Rendered as `PhaseGroupSummaryView`
    /// instead of `MessageBubble`.
    let isPhaseGroup: Bool
    let phase: StreamPhase?
}

/// Tier 3 — returns true when the message is a completed assistant turn
/// that landed in a non-text phase and is therefore a candidate for
/// phase-based auto-collapse. Errors and still-streaming messages are
/// always exempt.
fileprivate func isPhaseCollapsible(_ message: ChatMessage) -> Bool {
    guard message.role == .assistant,
          !message.isError,
          !message.isStreaming,
          let phase = message.completedPhase else { return false }
    return phase != .text
}

/// Returns true if the message would render only a transient tool summary (no visible text or non-transient tools).
fileprivate func isPureTransientMessage(_ message: ChatMessage) -> Bool {
    guard message.role == .assistant, !message.isError, !message.isCompactBoundary else { return false }
    // Whitespace-only text is treated as invisible so it doesn't break transient grouping.
    let hasVisibleText = message.blocks.contains {
        guard let text = $0.text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if hasVisibleText { return false }
    let toolCalls = message.blocks.compactMap(\.toolCall)
    guard !toolCalls.isEmpty else { return false }
    let hasNonTransient = toolCalls.contains { !ToolCategory(toolName: $0.name).isTransient }
    if hasNonTransient { return false }
    return true
}

/// Returns true if the message has no renderable content — all tool calls were removed
/// (e.g. empty bash output stripped by setToolResult) and there is no text.
/// These messages are invisible in the UI and should not break transient-tool grouping.
fileprivate func isInvisibleMessage(_ message: ChatMessage) -> Bool {
    guard message.role == .assistant, !message.isError, !message.isCompactBoundary, !message.isStreaming else { return false }
    return message.blocks.isEmpty
}

/// Groups consecutive pure-transient assistant messages into combined groups.
/// - Parameter minGroupSize: Minimum number of transient messages required to collapse into a group.
///   Pass 1 (streaming context) to hide even a single completed tool call the moment the next message starts.
///   Pass 2 (settled list) to keep lone tool calls visible after streaming ends.
///
/// Tier 3: also groups consecutive completed assistant messages whose
/// `completedPhase` is non-text (thinking / toolUse / toolResult) into a
/// single `isPhaseGroup` roll-up. Text and error messages always emit as
/// standalone groups. The last message in the list is always emitted
/// individually so a trailing non-text phase is visible while streaming
/// continues.
fileprivate func groupMessages(_ messages: [ChatMessage], minGroupSize: Int = 2) -> [MessageGroup] {
    var result: [MessageGroup] = []
    var transientAccumulator: [ChatMessage] = []
    var phaseAccumulator: [ChatMessage] = []
    var phaseAccumulatorPhase: StreamPhase?

    func flushTransient() {
        guard !transientAccumulator.isEmpty else { return }
        if transientAccumulator.count >= minGroupSize {
            result.append(MessageGroup(
                id: transientAccumulator[0].id,
                messages: transientAccumulator,
                isTransientGroup: true,
                isPhaseGroup: false,
                phase: nil
            ))
        } else {
            for m in transientAccumulator {
                result.append(MessageGroup(
                    id: m.id,
                    messages: [m],
                    isTransientGroup: false,
                    isPhaseGroup: false,
                    phase: nil
                ))
            }
        }
        transientAccumulator = []
    }

    func flushPhase(forceExpanded: Bool = false) {
        guard !phaseAccumulator.isEmpty else { return }
        if forceExpanded || phaseAccumulator.count == 1 {
            // Emit each message individually so the trailing / lone phase
            // group stays visible inline.
            for m in phaseAccumulator {
                result.append(MessageGroup(
                    id: m.id,
                    messages: [m],
                    isTransientGroup: false,
                    isPhaseGroup: false,
                    phase: nil
                ))
            }
        } else {
            result.append(MessageGroup(
                id: phaseAccumulator[0].id,
                messages: phaseAccumulator,
                isTransientGroup: false,
                isPhaseGroup: true,
                phase: phaseAccumulatorPhase
            ))
        }
        phaseAccumulator = []
        phaseAccumulatorPhase = nil
    }

    for (index, message) in messages.enumerated() {
        let isLast = index == messages.count - 1
        if isPureTransientMessage(message) {
            flushPhase()
            transientAccumulator.append(message)
        } else if isInvisibleMessage(message) {
            // Skip invisible messages (e.g. all tool calls removed due to empty results).
            // They render nothing in the UI and must not break grouping.
            continue
        } else if isPhaseCollapsible(message), let phase = message.completedPhase {
            flushTransient()
            if phaseAccumulatorPhase == phase {
                phaseAccumulator.append(message)
            } else {
                // Phase boundary — flush old, start new accumulator
                flushPhase(forceExpanded: isLast)
                phaseAccumulator.append(message)
                phaseAccumulatorPhase = phase
            }
        } else {
            flushTransient()
            // If we're ending a phase accumulator on a non-phase message,
            // force-emit each member individually (no roll-up) so the
            // boundary is clearly visible.
            flushPhase(forceExpanded: true)
            result.append(MessageGroup(
                id: message.id,
                messages: [message],
                isTransientGroup: false,
                isPhaseGroup: false,
                phase: nil
            ))
        }

        // After processing the last message, if we left items in either
        // accumulator we still flush — but force-expand the trailing phase
        // so a final non-text phase is visible inline.
        if isLast {
            flushTransient()
            flushPhase(forceExpanded: true)
        }
    }

    // Empty input edge case
    if messages.isEmpty {
        return []
    }

    return result
}

// MARK: - Shared Helper

/// Returns the start index of the last consecutive non-error assistant sequence.
/// Used to distinguish the settled (previous) / active (streaming) boundary.
private func streamingBoundaryIndex(in messages: [ChatMessage]) -> Int {
    var idx = messages.count - 1
    while idx >= 0 && messages[idx].role == .assistant && !messages[idx].isError {
        idx -= 1
    }
    return idx + 1
}

// MARK: - Streaming Message (isolated view — chatBridge.messages dependency confined to this view)

struct StreamingMessageView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    var onStructureChanged: () -> Void

    var body: some View {
        let messages = chatBridge.messages
        let activeMessages = activeResponseMessages(from: messages)
        let (settledActive, streamingActive) = partitionByStreaming(activeMessages)
        Group {
            if !activeMessages.isEmpty {

                if !streamingActive.isEmpty {
                    // Collapse completed transient tool calls (even a single one) the moment
                    // the next streaming message begins, so only the current message stays visible.
                    let groups = groupMessages(settledActive, minGroupSize: 1)
                    ForEach(groups) { group in
                        if group.isTransientGroup {
                            TransientGroupSummaryView(messages: group.messages)
                                .id(group.id)
                        } else if let message = group.messages.first {
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                } else {
                    // Nothing streaming yet — show each settled message individually.
                    ForEach(settledActive, id: \.id) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }

                ForEach(streamingActive, id: \.id) { message in
                    MessageBubble(message: message)
                        .id(message.id)
                }
            }
        }
        .onChange(of: messages.count) { _, _ in
            onStructureChanged()
        }
    }

    /// Returns the last consecutive assistant sequence (including streaming turn) while streaming.
    /// Returns an empty array when not streaming so StreamingMessageView renders nothing.
    private func activeResponseMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        guard messages.last?.isStreaming == true else { return [] }
        return Array(messages[streamingBoundaryIndex(in: messages)...])
    }
}

// MARK: - Transient Group Summary

struct TransientGroupSummaryView: View {
    let messages: [ChatMessage]
    @State private var isExpanded = false

    private var allToolCalls: [ToolCall] {
        messages.flatMap { $0.blocks.compactMap(\.toolCall) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: ClaudeTheme.size(11)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        Text(String(format: String(localized: "%lld tools executed", bundle: .module), allToolCalls.count))
                            .font(.system(size: ClaudeTheme.size(12)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: ClaudeTheme.size(9)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(allToolCalls, id: \.id) { toolCall in
                        ToolResultView(toolCall: toolCall, isMessageStreaming: false)
                    }
                }
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Phase Group Summary (Tier 3)

/// Collapsed view for a run of completed non-text assistant messages
/// (thinking / toolUse / toolResult). Auto-collapses when the group is
/// created; clicking the header toggles expansion to inspect the full
/// per-message bubbles inside.
struct PhaseGroupSummaryView: View {
    let group: MessageGroup
    let phase: StreamPhase

    @State private var isExpanded: Bool = false

    /// SF Symbol matching the phase kind.
    private var phaseIcon: String {
        switch phase {
        case .thinking:   return "brain"
        case .text:       return "text.bubble"
        case .toolUse:    return "hammer"
        case .toolResult: return "checkmark.circle"
        }
    }

    /// Localized label. For `.toolUse` we substitute the first tool call's
    /// name so the user sees e.g. "Tool: Bash" rather than the generic label.
    private var phaseLabel: String {
        switch phase {
        case .thinking:
            return String(localized: "Phase label: thinking", bundle: .module)
        case .text:
            return String(localized: "Phase label: text", bundle: .module)
        case .toolUse:
            let firstName = group.messages.first?.toolCalls.first?.name ?? "—"
            return String(format: String(localized: "Phase label: tool use", bundle: .module), firstName)
        case .toolResult:
            return String(localized: "Phase label: tool result", bundle: .module)
        }
    }

    /// Human-readable detail suffix, e.g. " · 3 calls" for multi-message
    /// phase groups. Skipped for single-message groups to keep the header
    /// compact.
    private var countSuffix: String {
        guard group.messages.count > 1 else { return "" }
        return " · \(group.messages.count)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: phaseIcon)
                            .font(.system(size: ClaudeTheme.size(11)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        Text(phaseLabel + countSuffix)
                            .font(.system(size: ClaudeTheme.size(12)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: ClaudeTheme.size(9)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(group.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Empty Session

struct EmptySessionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: ClaudeTheme.size(36)))
                .foregroundStyle(ClaudeTheme.textTertiary)

            Text("How can I help you?", bundle: .module)
                .font(.system(size: ClaudeTheme.size(18), weight: .medium))
                .foregroundStyle(ClaudeTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicatorView: View {
    let isThinking: Bool
    var startDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            PulseRingView()
                .id("pulse")

            Group {
                if isThinking {
                    Text("Thinking...", bundle: .module)
                } else {
                    Text("Generating response...", bundle: .module)
                }
            }
            .font(.system(size: ClaudeTheme.size(13)))
            .foregroundStyle(ClaudeTheme.textSecondary)

            Spacer()

            if let startDate {
                ElapsedTimeView(startDate: startDate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ClaudeTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium))
    }
}

// MARK: - Elapsed Time

struct ElapsedTimeView: View {
    let startDate: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsed.formattedDuration)
            .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
            .foregroundStyle(ClaudeTheme.textTertiary)
            .onAppear {
                elapsed = Date().timeIntervalSince(startDate)
            }
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(startDate)
            }
    }
}
