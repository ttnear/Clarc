import SwiftUI
import ClarcCore

/// A single Codex-style phase card. Renders inline (not inside an
/// assistant bubble) with a status icon, title, summary, live or
/// frozen duration, and an expandable detail region.
struct TaskUpdateCard: View {
    let update: TaskUpdateMessage
    @Binding var isExpanded: Bool
    @State private var now: Date = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                if !update.details.isEmpty { detailsSection }
                if !update.filesChanged.isEmpty { filesSection }
                if !update.testResults.isEmpty { testsSection }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .onReceive(ticker) { _ in
            if update.status == .running { now = Date() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            statusIcon
                .frame(width: 16, height: 16)
            Text(update.title)
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .semibold))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !update.summary.isEmpty {
                Text(update.summary)
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(formatDuration(liveDuration))
                .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced).monospacedDigit())
                .foregroundStyle(ClaudeTheme.textTertiary)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: ClaudeTheme.messageSize(10), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var detailsSection: some View {
        Text(update.details)
            .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
            .foregroundStyle(ClaudeTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Changed Files")
            ForEach(update.filesChanged) { change in
                HStack(spacing: 6) {
                    Image(systemName: fileIcon(change.changeType))
                        .font(.system(size: 11))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    Text(change.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let adds = change.additions {
                        Text("+\(adds)")
                            .font(.system(size: 11, design: .monospaced).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if let dels = change.deletions {
                        Text("-\(dels)")
                            .font(.system(size: 11, design: .monospaced).monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var testsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Tests")
            ForEach(update.testResults) { result in
                HStack(spacing: 6) {
                    Image(systemName: testIcon(result.status))
                        .font(.system(size: 11))
                        .foregroundStyle(testColor(result.status))
                    Text(result.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let dur = result.durationSeconds {
                        Text(formatDuration(dur))
                            .font(.system(size: 11, design: .monospaced).monospacedDigit())
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ClaudeTheme.textSecondary)
    }

    // MARK: - Status icon

    @ViewBuilder
    private var statusIcon: some View {
        switch update.status {
        case .running:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ClaudeTheme.statusSuccess)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(ClaudeTheme.statusWarning)
        }
    }

    // MARK: - Live duration

    private var liveDuration: TimeInterval {
        switch update.status {
        case .running:
            return now.timeIntervalSince(update.startTime)
        case .done, .failed:
            return update.durationSeconds
                ?? update.endTime?.timeIntervalSince(update.startTime)
                ?? 0
        }
    }

    // MARK: - Icons

    private func fileIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "added": return "doc.badge.plus"
        case "deleted": return "doc.badge.minus"
        case "renamed": return "doc.badge.arrow.up"
        default: return "doc"
        }
    }

    private func testIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "passed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        default: return "minus.circle"
        }
    }

    private func testColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "passed": return ClaudeTheme.statusSuccess
        case "failed": return ClaudeTheme.statusWarning
        default: return ClaudeTheme.textSecondary
        }
    }
}
