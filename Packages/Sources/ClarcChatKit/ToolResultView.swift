import SwiftUI
import ClarcCore

struct ToolResultView: View {
    let toolCall: ToolCall
    var isMessageStreaming: Bool = false
    @State private var isExpanded: Bool
    @State private var isDiffExpanded = false
    @Environment(WindowState.self) private var windowState

    /// Lowercased tool name (avoids repeated lowercased() calls)
    private let toolNameLower: String

    init(toolCall: ToolCall, isMessageStreaming: Bool = false) {
        self.toolCall = toolCall
        self.isMessageStreaming = isMessageStreaming
        let lower = toolCall.name.lowercased()
        self.toolNameLower = lower
        let isTransient = ToolCategory(toolName: lower).isTransient
        // Edit tool is expanded by default; transient tools are expanded only while running (until result arrives)
        self._isExpanded = State(initialValue:
            lower == "edit" || lower == "multiedit"
            || (isTransient && isMessageStreaming && toolCall.result == nil)
        )
    }

    /// Description input for the Agent tool
    private var agentDescription: String? {
        guard toolNameLower == "agent" else { return nil }
        return toolCall.input["description"]?.stringValue
    }

    /// Agent header title: "type: description" format
    private var agentDisplayTitle: String {
        let agentType = toolCall.input["subagent_type"]?.stringValue
        let desc = toolCall.input["description"]?.stringValue
        if let type = agentType, let desc {
            return "\(type): \(desc)"
        }
        return desc ?? agentType ?? "Agent"
    }

    /// Skill name for the Skill tool
    private var skillName: String? {
        guard toolNameLower == "skill" else { return nil }
        return toolCall.input["skill"]?.stringValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header + Input summary (both clickable)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: sfSymbol)
                            .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                            .foregroundStyle(iconColor)
                            .frame(width: 16, height: 16)

                        if toolNameLower == "agent" {
                            Text(agentDisplayTitle)
                                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                                .foregroundStyle(ClaudeTheme.textPrimary)
                        } else if let skillName = skillName {
                            Text(skillName)
                                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                                .foregroundStyle(ClaudeTheme.textPrimary)
                        } else {
                            Text(toolCall.name)
                                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                                .foregroundStyle(ClaudeTheme.textPrimary)
                        }

                        Spacer()

                        if toolCall.isError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(ClaudeTheme.statusError)
                                .font(.caption)
                                .accessibilityLabel("Error occurred")
                        } else if toolCall.result != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ClaudeTheme.statusSuccess)
                                .font(.caption)
                                .accessibilityLabel("Completed")
                        } else if isMessageStreaming {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityLabel("Running")
                        } else {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(ClaudeTheme.textTertiary)
                                .font(.caption)
                                .accessibilityLabel("Interrupted")
                        }

                        if toolCall.result != nil || hasExpandableContent {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(ClaudeTheme.textTertiary)
                        }
                    }

                    inputSummaryView
                        .lineLimit(isExpanded ? nil : 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                if isEditTool, let oldStr = toolCall.input["old_string"]?.stringValue,
                   let newStr = toolCall.input["new_string"]?.stringValue {
                    ClaudeThemeDivider()
                    editDiffView(oldString: oldStr, newString: newStr)
                } else if let result = toolCall.result, !result.isEmpty {
                    ClaudeThemeDivider()

                    ScrollView {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(toolCall.isError ? ClaudeTheme.statusError : ClaudeTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .bubbleStyle(toolCall.isError ? .toolError : .tool)
        .onChange(of: toolCall.result) { _, newResult in
            guard ToolCategory(toolName: toolNameLower).isTransient, newResult != nil else { return }
            isExpanded = false
        }
    }

    // MARK: - Edit Diff

    private var isEditTool: Bool {
        toolNameLower == "edit" || toolNameLower == "multiedit" || toolNameLower == "multi_edit"
    }

    private var hasExpandableContent: Bool {
        isEditTool && toolCall.input["old_string"]?.stringValue != nil
            && toolCall.input["new_string"]?.stringValue != nil
    }

    private func editHunksFromToolInput() -> [PreviewFile.EditHunk] {
        if toolNameLower == "edit",
           let old = toolCall.input["old_string"]?.stringValue,
           let new = toolCall.input["new_string"]?.stringValue {
            return [PreviewFile.EditHunk(oldString: old, newString: new)]
        }
        if let edits = toolCall.input["edits"]?.arrayValue {
            return edits.compactMap { entry in
                guard let obj = entry.objectValue,
                      let old = obj["old_string"]?.stringValue,
                      let new = obj["new_string"]?.stringValue else { return nil }
                return PreviewFile.EditHunk(oldString: old, newString: new)
            }
        }
        return []
    }

    private func editDiffView(oldString: String, newString: String) -> some View {
        let (trimmedOld, trimmedNew) = stripCommonIndent(
            old: oldString.components(separatedBy: .newlines),
            new: newString.components(separatedBy: .newlines)
        )
        let removedLines = trimmedOld.map { ("-", $0, false) }
        let addedLines = trimmedNew.map { ("+", $0, true) }
        let allLines = removedLines + addedLines

        let collapseThreshold = 12
        let needsToggle = allLines.count > collapseThreshold
        let visibleLines = needsToggle && !isDiffExpanded
            ? Array(allLines.prefix(collapseThreshold))
            : allLines

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, item in
                let (prefix, text, isAdded) = item
                Text(prefix + " " + text)
                    .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                    .foregroundStyle(isAdded ? ClaudeTheme.statusSuccess : ClaudeTheme.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background((isAdded ? ClaudeTheme.statusSuccess : ClaudeTheme.statusError).opacity(0.06))
            }

            if needsToggle {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isDiffExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if isDiffExpanded {
                                Text("Show less", bundle: .module)
                            } else {
                                Text("Show more", bundle: .module)
                            }
                        }
                        .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                        Image(systemName: isDiffExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: ClaudeTheme.messageSize(10), weight: .medium))
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
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Helpers

    private var sfSymbol: String {
        switch toolNameLower {
        case "agent":      return "cpu"
        case "read":       return "doc.text"
        case "grep":       return "magnifyingglass"
        case "glob":       return "magnifyingglass"
        case "write":      return "square.and.pencil"
        case "multiedit",
             "multi_edit": return "pencil"
        case "bash":       return "terminal"
        case "notebookedit": return "book.and.wrench"
        case InteractiveTerminalState.toolName: return "apple.terminal"
        default:           return ToolCategory(toolName: toolNameLower).sfSymbol
        }
    }

    private var iconColor: Color {
        switch toolNameLower {
        case "agent", "bash",
             InteractiveTerminalState.toolName: return ClaudeTheme.accent
        case "edit", "multiedit", "multi_edit",
             "write", "notebookedit": return ClaudeTheme.statusWarning
        case "read", "grep", "glob": return ClaudeTheme.textSecondary
        default:
            switch ToolCategory(toolName: toolNameLower) {
            case .execution: return ClaudeTheme.accent
            case .fileModification: return ClaudeTheme.statusWarning
            case .readOnly: return ClaudeTheme.textSecondary
            case .mcp, .unknown: return ClaudeTheme.textTertiary
            }
        }
    }

    @ViewBuilder
    private func fileActionLink(label: String, color: Color = ClaudeTheme.textSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(color)
                .underline()
        }
        .buttonStyle(.plain)
        .pointerCursorOnHover()
    }

    @ViewBuilder
    private var inputSummaryView: some View {
        if isEditTool || toolNameLower == "write",
           let filePath = toolCall.input["file_path"]?.stringValue {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            HStack(spacing: 0) {
                Text("\(toolDescriptionPrefix) — ")
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                fileActionLink(label: fileName, color: ClaudeTheme.accent) {
                    windowState.inspectorFile = PreviewFile(path: filePath, name: fileName)
                }
                if isEditTool, toolCall.result != nil {
                    let hunks = editHunksFromToolInput()
                    if !hunks.isEmpty {
                        Text(" · ")
                            .font(.system(size: ClaudeTheme.messageSize(12)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        fileActionLink(label: "diff") {
                            windowState.diffFile = PreviewFile(
                                path: filePath,
                                name: fileName,
                                editHunks: hunks
                            )
                        }
                    }
                }
            }
        } else {
            Text(inputSummary)
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(ClaudeTheme.textSecondary)
        }
    }

    private var inputSummary: String {
        if toolNameLower == "agent" {
            if let desc = toolCall.input["description"]?.stringValue {
                return desc
            }
            if let prompt = toolCall.input["prompt"]?.stringValue {
                let truncated = prompt.count > 60 ? String(prompt.prefix(60)) + "..." : prompt
                return truncated
            }
            return toolDescriptionPrefix
        }

        if toolNameLower == "skill" {
            if let name = toolCall.input["skill"]?.stringValue {
                return "\(toolDescriptionPrefix) — \(name)"
            }
            return toolDescriptionPrefix
        }

        if let filePath = toolCall.input["file_path"]?.stringValue {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            return "\(toolDescriptionPrefix) — \(fileName)"
        }
        if let command = toolCall.input["command"]?.stringValue {
            return "\(toolDescriptionPrefix) — \(command.count > 50 ? String(command.prefix(50)) + "..." : command)"
        }
        if let pattern = toolCall.input["pattern"]?.stringValue {
            return "\(toolDescriptionPrefix) — '\(pattern)'"
        }
        if let path = toolCall.input["path"]?.stringValue {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return "\(toolDescriptionPrefix) — \(fileName)"
        }

        return toolDescriptionPrefix
    }

    private var toolDescriptionPrefix: String {
        switch toolNameLower {
        case "read": "Read file"
        case "edit": "Edit file"
        case "write": "Create new file"
        case "bash": "Run command"
        case "glob": "Find files"
        case "grep": "Search in code"
        case "multiedit": "Edit multiple locations"
        case "notebookedit": "Edit notebook"
        case "agent": "Subagent"
        case "skill": "Skill"
        case InteractiveTerminalState.toolName: "Interactive terminal"
        default: toolCall.name
        }
    }
}
