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
                } else {
                    optionsList(question)
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
    private func optionsList(_ question: AskUserQuestion.Question) -> some View {
        VStack(spacing: 6) {
            ForEach(question.options) { option in
                Button {
                    windowState.answerQuestionHandler?(toolCall.id, option.label)
                } label: {
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
                .buttonStyle(.plain)
            }
        }
    }
}
