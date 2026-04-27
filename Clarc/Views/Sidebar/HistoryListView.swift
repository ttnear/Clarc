import SwiftUI
import ClarcCore

struct HistoryListView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var renamingSession: ChatSession?
    @State private var renameText = ""
    @State private var showAllProjects = true
    @State private var showDeleteAllAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .alert("Delete All", isPresented: $showDeleteAllAlert) {
            Button("Delete", role: .destructive) {
                let projectId: UUID?
                if windowState.isProjectWindow {
                    projectId = windowState.selectedProject?.id
                } else {
                    projectId = showAllProjects ? nil : windowState.selectedProject?.id
                }
                Task { await appState.deleteAllSessions(projectId: projectId, in: windowState) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let isCurrentOnly = windowState.isProjectWindow || !showAllProjects
            if isCurrentOnly {
                Text("All sessions in the current project will be deleted. This action cannot be undone.")
            } else {
                Text("All sessions will be deleted. This action cannot be undone.")
            }
        }
        .alert("Rename Session", isPresented: isRenamingBinding) {
            TextField("Session name", text: $renameText)
            Button("Rename") {
                if let session = renamingSession, !renameText.isEmpty {
                    Task { await appState.renameSession(session, to: renameText) }
                }
                renamingSession = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSession = nil
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("History")
                .font(.system(size: ClaudeTheme.size(12), weight: .semibold))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .textCase(.uppercase)

            Spacer()

            // No need to toggle all/current in the project window
            if !windowState.isProjectWindow {
                Button {
                    showAllProjects.toggle()
                } label: {
                    Image(systemName: showAllProjects ? "tray.2" : "tray")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(showAllProjects ? ClaudeTheme.accent : ClaudeTheme.textTertiary)
                }
                .buttonStyle(.borderless)
                .help(showAllProjects ? "Show current project only" : "Show all projects")
            }

            Button {
                showDeleteAllAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
            .buttonStyle(.borderless)
            .help("Delete All")
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List(sessions, selection: selectedSessionBinding) { session in
            sessionRow(session)
                .tag(session.id)
        }
        .listStyle(.sidebar)
        .animation(.default, value: sessions)
    }

    private var selectedSessionBinding: Binding<String?> {
        Binding<String?>(
            get: { appState.currentSession(in: windowState)?.id },
            set: { id in
                if let id {
                    appState.selectSession(id: id, in: windowState)
                }
            }
        )
    }

    private func sessionRow(_ session: DisplaySession) -> some View {
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: ClaudeTheme.size(13)))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if showAllProjects && !windowState.isProjectWindow, let projectName = session.projectName {
                        Text(projectName)
                            .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                            .foregroundStyle(ClaudeTheme.accent.opacity(0.8))
                            .lineLimit(1)

                        Text("·")
                            .font(.system(size: ClaudeTheme.size(10)))
                            .foregroundStyle(.tertiary)
                    }

                    Text(formattedDate(session.updatedAt))
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if session.isBackgroundStreaming {
                ProgressView()
                    .controlSize(.mini)
                    .help("Response in progress in the background")
            }

            if session.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: ClaudeTheme.size(9)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 10, pressing: { pressing in
            if pressing {
                appState.selectSession(id: session.id, in: windowState)
            }
        }, perform: {})
        .contextMenu {
            if let summary = appState.allSessionSummaries.first(where: { $0.id == session.id }) {
                let chatSession = summary.makeSession()

                Button {
                    renameText = session.title
                    renamingSession = chatSession
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    Task { await appState.togglePinSession(chatSession) }
                } label: {
                    if session.isPinned {
                        Label("Unpin", systemImage: "pin.slash")
                    } else {
                        Label("Pin", systemImage: "pin")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    Task { await appState.deleteSession(chatSession, in: windowState) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: ClaudeTheme.size(20)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Text("No chat history")
                .font(.system(size: ClaudeTheme.size(13)))
                .foregroundStyle(ClaudeTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Display Model

    private struct DisplaySession: Identifiable, Equatable {
        let id: String
        let projectId: UUID
        let title: String
        let updatedAt: Date
        let isPinned: Bool
        let isBackgroundStreaming: Bool
        let projectName: String?
    }

    private var sessions: [DisplaySession] {
        if windowState.isProjectWindow || !showAllProjects {
            return currentProjectSessions
        } else {
            return allProjectSessions
        }
    }

    private static func sessionOrder(
        _ a: ChatSession.Summary, _ b: ChatSession.Summary
    ) -> Bool {
        if a.isPinned != b.isPinned { return a.isPinned }
        return a.updatedAt > b.updatedAt
    }

    private var currentProjectSessions: [DisplaySession] {
        guard let projectId = windowState.selectedProject?.id else { return [] }
        let streamingIds = appState.backgroundStreamingSessionIds(in: windowState)
        return appState.allSessionSummaries
            .filter { $0.projectId == projectId }
            .sorted { Self.sessionOrder($0, $1) }
            .map { summary in
                DisplaySession(
                    id: summary.id,
                    projectId: summary.projectId,
                    title: summary.title,
                    updatedAt: summary.updatedAt,
                    isPinned: summary.isPinned,
                    isBackgroundStreaming: streamingIds.contains(summary.id),
                    projectName: nil
                )
            }
    }

    private var allProjectSessions: [DisplaySession] {
        let projectNames = Dictionary(
            uniqueKeysWithValues: appState.projects.map { ($0.id, $0.name) }
        )
        let streamingIds = appState.backgroundStreamingSessionIds(in: windowState)
        var seen = Set<String>()
        return appState.allSessionSummaries
            .sorted { Self.sessionOrder($0, $1) }
            .filter { seen.insert($0.id).inserted }
            .map { summary in
                DisplaySession(
                    id: summary.id,
                    projectId: summary.projectId,
                    title: summary.title,
                    updatedAt: summary.updatedAt,
                    isPinned: summary.isPinned,
                    isBackgroundStreaming: streamingIds.contains(summary.id),
                    projectName: projectNames[summary.projectId]
                )
            }
    }

    // MARK: - Helpers

    private var isRenamingBinding: Binding<Bool> {
        Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = .current
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    HistoryListView()
        .environment(AppState())
        .environment(WindowState())
        .frame(width: 260)
}
