import SwiftUI
import AppKit
import ClarcCore

struct MessageBubble: View {
    @Environment(ChatBridge.self) private var chatBridge
    let message: ChatMessage
    @State private var isCopied = false
    @State private var cursorVisible = true
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isEditFocused: Bool
    @State private var isLongTextExpanded = false
    @State private var hoveredBlockId: String? = nil

    /// Threshold (character count) for collapsing long text
    private static let longTextThreshold = 500

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Show attachments
                if !message.attachmentPaths.isEmpty {
                    attachmentPreview
                }

                if message.role == .user {
                    // User message: single text bubble
                    if !message.content.isEmpty {
                        textBubble
                    }
                } else if message.isCompactBoundary {
                    compactBoundaryBubble
                } else if message.isError {
                    // Error message: warning-style bubble
                    errorBubble
                } else {
                    // Assistant message: render blocks in order
                    let hidden = message.isStreaming ? [] : message.blocks.compactMap(\.toolCall).filter { isTransientTool($0) && $0.hasNonEmptyResult }
                    // Filter to only renderable blocks — exclude hidden transient tool blocks from ForEach
                    // to prevent zero-height TupleViews from introducing VStack spacing.
                    // Adjacent text blocks made contiguous by hidden tools are merged into a single bubble
                    // (so continuous text Claude sent across turns due to tool_use appears as one bubble)
                    let visibleBlocks = Self.mergeAdjacentTextBlocks(
                        in: message.blocks.filter { block in
                            if let text = block.text { return !text.isEmpty }
                            if let toolCall = block.toolCall {
                                if message.isStreaming { return true }
                                if isTransientTool(toolCall) { return false }
                                // Agent/Edit/Write tools are always shown even without a result
                                // Agent/Edit/Write/AskUserQuestion are always shown even without a result
                                if toolCall.isKeepAlways { return true }
                                // Other non-transient tools: only show when there is a result or error (prevents empty tool bubbles)
                                return toolCall.result != nil || toolCall.isError
                            }
                            return false
                        }
                    )

                    // Hidden tool summary — shown before text (reflects tool execution → text response order)
                    if !hidden.isEmpty {
                        transientToolSummary(hidden: hidden)
                    }

                    ForEach(visibleBlocks) { block in
                        if let text = block.text, !text.isEmpty {
                            assistantTextBubble(text: text, blockId: block.id, hasHiddenTools: !hidden.isEmpty)
                        }
                        if let toolCall = block.toolCall {
                            if toolCall.name == "AskUserQuestion" {
                                AskUserQuestionView(toolCall: toolCall)
                            } else {
                                ToolResultView(toolCall: toolCall, isMessageStreaming: message.isStreaming)
                            }
                        }
                    }
                }

                // Response complete indicator + elapsed time
                if message.role == .assistant && !message.isStreaming,
                   let duration = message.duration {
                    HStack(spacing: 4) {
                        if message.isResponseComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: ClaudeTheme.messageSize(11)))
                                .foregroundStyle(ClaudeTheme.statusSuccess)
                        }
                        Text(duration.formattedDuration)
                            .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Compact Boundary Bubble

    private var compactBoundaryBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Text(message.content)
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .fill(ClaudeTheme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .strokeBorder(ClaudeTheme.border, lineWidth: BubbleStyle.borderWidth)
        )
    }

    // MARK: - Error Bubble

    private var errorBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: ClaudeTheme.messageSize(13)))
                .foregroundStyle(ClaudeTheme.statusWarning)
            Text(message.content)
                .font(.system(size: ClaudeTheme.messageSize(14)))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .textSelection(.enabled)
        }
        .bubbleStyle(.error)
    }

    // MARK: - User Text Bubble

    @ViewBuilder
    private var textBubble: some View {
        if isEditing {
            VStack(alignment: .trailing, spacing: 8) {
                TextField(String(localized: "Edit message...", bundle: .module), text: $editText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: ClaudeTheme.messageSize(14)))
                    .foregroundStyle(ClaudeTheme.userBubbleText)
                    .focused($isEditFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(ClaudeTheme.userBubble, in: bubbleShape)
                    .overlay(
                        bubbleShape
                            .strokeBorder(ClaudeTheme.accent, lineWidth: 1.5)
                    )
                    .onKeyPress(.return, phases: .down) { keyPress in
                        guard !keyPress.modifiers.contains(.shift) else { return .ignored }
                        submitEdit()
                        return .handled
                    }
                    .onKeyPress(.escape, phases: .down) { _ in
                        isEditing = false
                        return .handled
                    }

                HStack(spacing: 8) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        isEditing = false
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .foregroundStyle(ClaudeTheme.textSecondary)

                    Button(String(localized: "Send", bundle: .module)) {
                        submitEdit()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                    .foregroundStyle(ClaudeTheme.accent)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                let isLong = message.content.count > Self.longTextThreshold
                Text(message.content)
                    .font(.system(size: ClaudeTheme.messageSize(14)))
                    .foregroundStyle(ClaudeTheme.userBubbleText)
                    .textSelection(.enabled)
                    .lineLimit(isLong && !isLongTextExpanded ? 5 : nil)
                if isLong {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLongTextExpanded.toggle()
                        }
                    } label: {
                        if isLongTextExpanded {
                            Text("Collapse", bundle: .module)
                        } else {
                            Text("Show more", bundle: .module)
                        }
                    }
                    .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                    .foregroundStyle(ClaudeTheme.accent)
                    .buttonStyle(.plain)
                }
            }
            .bubbleStyle(.user)
            .contextMenu {
                Button {
                    copyToClipboard(message.content, feedback: $isCopied)
                } label: {
                    Label(isCopied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy Message", bundle: .module), systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                Button {
                    editText = message.content
                    isEditing = true
                } label: {
                    Label(String(localized: "Edit Message", bundle: .module), systemImage: "pencil")
                }
            }
                .onChange(of: isEditing) { _, editing in
                    if editing { isEditFocused = true }
                }
        }
    }

    // MARK: - Assistant Text Bubble

    private func assistantTextBubble(text: String, blockId: String, hasHiddenTools: Bool = false) -> some View {
        let isLastBlock = message.blocks.last?.isText == true
            && message.blocks.last?.text == text

        return HStack(alignment: .bottom, spacing: 0) {
            if message.isStreaming && isLastBlock {
                Text(text)
                    .font(.system(size: ClaudeTheme.messageSize(15)))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownContentView(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if message.isStreaming && isLastBlock {
                Text("|")
                    .font(.system(size: ClaudeTheme.messageSize(15), weight: .light))
                    .foregroundStyle(ClaudeTheme.accent)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                    .onAppear { cursorVisible = false }
            }
        }
        .foregroundStyle(ClaudeTheme.textPrimary)
        .bubbleStyle(.assistant)
        .overlay(alignment: .bottomTrailing) {
            if hoveredBlockId == blockId && !message.isStreaming {
                copyButton(for: text)
                    .padding(6)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .onHover { hoveredBlockId = $0 ? blockId : nil }
        .onTapGesture {
            if hasHiddenTools {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTransientTools.toggle()
                }
            }
        }
        .contextMenu {
            Button {
                copyToClipboard(text, feedback: $isCopied)
            } label: {
                Label(isCopied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy", bundle: .module), systemImage: isCopied ? "checkmark" : "doc.on.doc")
            }
        }
        .accessibilityLabel("Assistant: \(text)")
    }

    // MARK: - Copy Button

    @ViewBuilder
    private func copyButton(for text: String) -> some View {
        Button {
            copyToClipboard(text, feedback: $isCopied)
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transient Tool Helpers

    /// Read, Grep, Glob, Bash etc. are collapsed into a summary after streaming completes
    private func isTransientTool(_ toolCall: ToolCall) -> Bool {
        let cat = ToolCategory(toolName: toolCall.name)
        return cat == .readOnly || cat == .execution
    }

    /// Merges adjacent text blocks made contiguous by hidden transient tools.
    /// Displays continuous text Claude split across turns due to tool_use as a single bubble.
    ///
    /// Join rule: respects original trailing/leading whitespace; adds a single space only when
    /// neither side has whitespace. Forced paragraph breaks would split bullets mid-list,
    /// so they are avoided — even text following a complete sentence joins naturally with a single space.
    private static func mergeAdjacentTextBlocks(in blocks: [MessageBlock]) -> [MessageBlock] {
        var result: [MessageBlock] = []
        for block in blocks {
            if block.isText,
               let lastIdx = result.indices.last,
               result[lastIdx].isText {
                let prev = result[lastIdx].text ?? ""
                let curr = block.text ?? ""
                let needsSpace = !(prev.last?.isWhitespace ?? true) && !(curr.first?.isWhitespace ?? true)
                let joined = needsSpace ? prev + " " + curr : prev + curr
                // Preserve original block id to ensure ForEach diff stability
                result[lastIdx] = .text(joined, id: result[lastIdx].id)
            } else {
                result.append(block)
            }
        }
        return result
    }

    @State private var showTransientTools = false

    private func transientToolSummary(hidden: [ToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTransientTools.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: ClaudeTheme.messageSize(11)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text(String(format: String(localized: "%lld tools executed", bundle: .module), hidden.count))
                        .font(.system(size: ClaudeTheme.messageSize(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Image(systemName: showTransientTools ? "chevron.up" : "chevron.down")
                        .font(.system(size: ClaudeTheme.messageSize(9)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showTransientTools {
                ForEach(hidden, id: \.id) { toolCall in
                    ToolResultView(toolCall: toolCall, isMessageStreaming: false)
                }
            }
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: ClaudeTheme.cornerRadiusLarge,
                bottomLeadingRadius: ClaudeTheme.cornerRadiusLarge,
                bottomTrailingRadius: 4,
                topTrailingRadius: ClaudeTheme.cornerRadiusLarge
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: ClaudeTheme.cornerRadiusLarge,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: ClaudeTheme.cornerRadiusLarge,
                topTrailingRadius: ClaudeTheme.cornerRadiusLarge
            )
        }
    }

    private func submitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isEditing = false
        Task { await chatBridge.editAndResend(messageId: message.id, newContent: trimmed) }
    }

    // MARK: - Attachment Preview

    private var attachmentPreview: some View {
        HStack(spacing: 6) {
            ForEach(message.attachmentPaths, id: \.path) { info in
                HStack(spacing: 4) {
                    if info.isImage, let nsImage = NSImage(contentsOfFile: info.path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
                    } else {
                        Image(systemName: info.isImage ? "photo" : "doc")
                            .font(.system(size: ClaudeTheme.messageSize(14)))
                            .foregroundStyle(ClaudeTheme.accent)
                    }
                    Text(info.name)
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
            }
        }
    }

    /// Converts bare URLs to clickable links (without full markdown rendering)
    private func linkifiedAttributedString(_ text: String) -> AttributedString {
        let autoLinked = autoLinkURLs(text)
        return (try? AttributedString(
            markdown: autoLinked,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
