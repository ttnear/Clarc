import SwiftUI
import ClarcCore
import ClarcChatKit

/// Dedicated project window — shares AppState, WindowState.isProjectWindow = true
struct ProjectWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var sidebarTab: MainView.SidebarTab = .history
    @State private var fileSearchTrigger = false
    @State private var inspectorStarted = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if windowState.isInitialized {
                HSplitView {
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        sidebarContent
                    } detail: {
                        detailContent
                    }
                    .background {
                        Button("") {
                            columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
                        }
                        .keyboardShortcut("3", modifiers: .command)
                        .hidden()
                    }
                    .id(appState.themeRevision)
                    .navigationTitle(windowState.selectedProject?.name ?? "Project")
                    .onChange(of: windowState.showInspector) { _, isShowing in
                        if isShowing, !inspectorStarted { inspectorStarted = true }
                    }

                    if inspectorStarted {
                        InspectorPanel()
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ClaudeTheme.background)
            }
        }
        .onAppear {
            windowState.isProjectWindow = true
        }
        .sheet(item: Bindable(windowState).inspectorFile) { file in
            FileInspectorView(filePath: file.path, fileName: file.name)
                .frame(minWidth: 1000, idealWidth: 1400, maxWidth: 1920,
                       minHeight: 600, idealHeight: 1000, maxHeight: 1200)
        }
        .sheet(item: Bindable(windowState).diffFile) { file in
            FileDiffView(filePath: file.path, fileName: file.name)
                .frame(minWidth: 1000, idealWidth: 1400, maxWidth: 1920,
                       minHeight: 600, idealHeight: 1000, maxHeight: 1200)
        }
        .alert("Error", isPresented: Bindable(windowState).showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(windowState.errorMessage ?? ""))
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Sidebar tabs (History/Files)
            ClaudeSegmentedControl(selection: $sidebarTab)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            ClaudeThemeDivider()

            switch sidebarTab {
            case .files:
                if let project = windowState.selectedProject {
                    FileTreeView(projectPath: project.path, searchTrigger: $fileSearchTrigger)
                }
            case .history:
                HistoryListView()
            }

            SidebarTabShortcuts(sidebarTab: $sidebarTab, fileSearchTrigger: $fileSearchTrigger, columnVisibility: $columnVisibility)

            ClaudeThemeDivider()

            if let project = windowState.selectedProject {
                GitStatusView(projectPath: project.path)
            }
        }
        .background(ClaudeTheme.sidebarBackground)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
    }

    // MARK: - Chat Toolbar Area

    private var chatToolbarArea: some View {
        HStack(spacing: 12) {
            if let project = windowState.selectedProject {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(ClaudeTheme.textOnAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(ClaudeTheme.accent, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
            }

            Spacer()

            ChatToolbarControls()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ClaudeTheme.surfaceElevated)
    }

    // MARK: - Detail

    private var detailContent: some View {
        Group {
            if windowState.selectedProject != nil {
                VStack(spacing: 0) {
                    chatToolbarArea
                    ClaudeThemeDivider()
                    ChatView()
                }
                .modifier(ChatDetailModifiers())
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ClaudeTheme.background)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    appState.startNewChat(in: windowState)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Chat")

                Button {
                    windowState.showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle Inspector")
                .keyboardShortcut("4", modifiers: .command)
            }
        }
        .focusedValue(\.startNewChat) {
            appState.startNewChat(in: windowState)
        }
    }

}
