import SwiftUI
import ClarcCore

/// Interactive UI for a Claude Code `AskUserQuestion` tool call.
struct AskUserQuestionView: View {
    let toolCall: ToolCall
    @Environment(WindowState.self) private var windowState

    private var parsed: AskUserQuestion? {
        AskUserQuestion(input: toolCall.input)
    }

    private var hasAnswer: Bool {
        toolCall.result != nil
    }

    var body: some View {
        if let question = parsed?.questions.first {
            VStack(alignment: .leading, spacing: 12) {
                header(question)
                questionText(question)

                if hasAnswer {
                    answerBadge
                } else if question.multiSelect {
                    multiSelectList(question)
                } else {
                    singleSelectList(question)
                }
            }
            .bubbleStyle(.tool)
        } else {
            // Fallback: malformed input — show raw debug card
            ToolResultView(toolCall: toolCall)
        }
    }

    @ViewBuilder
    private func header(_ question: AskUserQuestion.Question) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                .foregroundStyle(ClaudeTheme.accent)
                .frame(width: 16, height: 16)

            Text(question.header ?? String(localized: "Question", bundle: .module))
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                .foregroundStyle(ClaudeTheme.textPrimary)

            Spacer()

            if hasAnswer {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ClaudeTheme.statusSuccess)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func questionText(_ question: AskUserQuestion.Question) -> some View {
        Text(question.question)
            .font(.system(size: ClaudeTheme.messageSize(13)))
            .foregroundStyle(ClaudeTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var answerBadge: some View {
        if let answer = toolCall.result, !answer.isEmpty {
            Text(answer)
                .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                .foregroundStyle(ClaudeTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ClaudeTheme.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func singleSelectList(_ question: AskUserQuestion.Question) -> some View {
        VStack(spacing: 6) {
            ForEach(question.options) { option in
                Button {
                    windowState.answerQuestionHandler?(toolCall.id, option.label)
                } label: {
                    optionRow(label: option.label, description: option.description)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func multiSelectList(_ question: AskUserQuestion.Question) -> some View {
        MultiSelectOptionsList(
            question: question,
            onSubmit: { selectedLabels in
                windowState.answerQuestionHandler?(toolCall.id, selectedLabels.joined(separator: ", "))
            }
        )
    }

    @ViewBuilder
    private func optionRow(label: String, description: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let desc = description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: ClaudeTheme.messageSize(11)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ClaudeTheme.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ClaudeTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Multi-Select List

/// Checkbox list + Submit button. Lifted into its own view so the
/// `@State` Set<String> is local to the list (the parent re-renders
/// on every tick and would otherwise reset the selection).
private struct MultiSelectOptionsList: View {
    let question: AskUserQuestion.Question
    let onSubmit: ([String]) -> Void

    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 6) {
                ForEach(question.options) { option in
                    Button {
                        if selected.contains(option.label) {
                            selected.remove(option.label)
                        } else {
                            selected.insert(option.label)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selected.contains(option.label) ? "checkmark.square.fill" : "square")
                                .font(.system(size: ClaudeTheme.messageSize(14), weight: .medium))
                                .foregroundStyle(selected.contains(option.label) ? ClaudeTheme.accent : ClaudeTheme.textSecondary)
                                .frame(width: 16, alignment: .center)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                                    .foregroundStyle(ClaudeTheme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let desc = option.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: ClaudeTheme.messageSize(11)))
                                        .foregroundStyle(ClaudeTheme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ClaudeTheme.surfaceSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    selected.contains(option.label) ? ClaudeTheme.accent : ClaudeTheme.border,
                                    lineWidth: selected.contains(option.label) ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                // Preserve the original question.options order in the
                // submitted list (Set is unordered).
                let ordered = question.options.map(\.label).filter { selected.contains($0) }
                onSubmit(ordered)
            } label: {
                Text("Submit")
                    .font(.system(size: ClaudeTheme.messageSize(13), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected.isEmpty
                                  ? ClaudeTheme.textSecondary.opacity(0.4)
                                  : ClaudeTheme.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
        }
    }
}
