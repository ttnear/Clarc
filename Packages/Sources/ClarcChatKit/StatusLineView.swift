import SwiftUI
import ClarcCore

struct StatusLineView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    @State private var rateLimit: RateLimitUsage?

    private var modelDisplayName: String {
        chatBridge.modelDisplayName
    }

    private var totalResponseDuration: Double {
        chatBridge.messages
            .filter { $0.role == .assistant }
            .compactMap { $0.duration }
            .reduce(0, +)
    }

    private var contextPercentage: Double? {
        guard let pct = chatBridge.lastTurnContextUsedPercentage else { return nil }
        return min(pct, 100)
    }

    var body: some View {
        HStack(spacing: 10) {
            if let project = windowState.selectedProject {
                segment(icon: "folder.fill", text: abbreviatePath(project.path), color: ClaudeTheme.statusWarning)
            }

            segment(icon: "cpu", text: modelDisplayName, color: ClaudeTheme.statusSuccess)

            Divider().frame(height: 12)

            rateLimitSegment(label: String(localized: "5h", bundle: .module), icon: "clock", percent: rateLimit?.fiveHourPercent, resetsAt: rateLimit?.fiveHourResetsAt)
            rateLimitSegment(label: String(localized: "7d", bundle: .module), icon: "calendar", percent: rateLimit?.sevenDayPercent, resetsAt: rateLimit?.sevenDayResetsAt)

            Divider().frame(height: 12)

            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.system(size: ClaudeTheme.size(10)))
                Text("context", bundle: .module)
                if let ctxPct = contextPercentage {
                    miniBar(percent: ctxPct)
                    Text("\(Int(ctxPct))%")
                        .foregroundStyle(colorForPercent(ctxPct))
                } else {
                    Text("--")
                }
            }
            .foregroundStyle(ClaudeTheme.textTertiary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "stopwatch")
                    .font(.system(size: ClaudeTheme.size(10)))
                Text(formatTotalDuration(totalResponseDuration))
            }
            .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .font(.system(size: ClaudeTheme.size(12), weight: .medium, design: .monospaced))
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: 28)
        .padding(.bottom, 4)
        .background(ClaudeTheme.surfacePrimary)
        .overlay(alignment: .top) {
            ClaudeTheme.borderSubtle.frame(height: 0.5)
        }
        .task {
            await refreshRateLimit()
            // Retry after 5 seconds if initial load fails
            if rateLimit == nil {
                try? await Task.sleep(for: .seconds(5))
                await refreshRateLimit()
            }
        }
        .onChange(of: chatBridge.isStreaming) { old, new in
            if old && !new {
                Task { await refreshRateLimit() }
            }
        }
    }

    // MARK: - Segment

    private func segment(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: ClaudeTheme.size(10)))
            Text(text)
        }
        .foregroundStyle(color)
    }

    // MARK: - Rate Limit Segment

    @ViewBuilder
    private func rateLimitSegment(label: String, icon: String, percent: Double?, resetsAt: Date?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: ClaudeTheme.size(10)))
            Text(label)
                .foregroundStyle(ClaudeTheme.textTertiary)
            if let pct = percent {
                miniBar(percent: pct)
                Text("\(Int(pct))%")
                    .foregroundStyle(colorForPercent(pct))
                if let resets = resetsAt {
                    Text(shortCountdown(until: resets))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                }
            } else {
                Text("--")
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
        }
    }

    // MARK: - Mini Progress Bar

    private func miniBar(percent: Double, width: Int = 5) -> some View {
        let filled = max(0, min(width, Int((percent / 100.0) * Double(width))))
        let empty = width - filled
        let color = colorForPercent(percent)

        return HStack(spacing: 1) {
            ForEach(0..<filled, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 4, height: 10)
            }
            ForEach(0..<empty, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(ClaudeTheme.borderSubtle)
                    .frame(width: 4, height: 10)
            }
        }
    }

    // MARK: - Helpers

    private func colorForPercent(_ pct: Double) -> Color {
        if pct >= 90 { return ClaudeTheme.statusError }
        if pct >= 70 { return ClaudeTheme.statusWarning }
        return ClaudeTheme.statusSuccess
    }

    private func makeCountdownFormatter() -> DateComponentsFormatter {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = [.day, .hour, .minute]
        f.calendar = Calendar.current
        return f
    }

    private func shortCountdown(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "" }
        return makeCountdownFormatter().string(from: remaining) ?? ""
    }

    private func formatTotalDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = [.hour, .minute, .second]
        return f.string(from: seconds) ?? "—"
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func refreshRateLimit() async {
        rateLimit = await chatBridge.fetchRateLimit()
    }
}
