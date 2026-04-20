import SwiftUI
import UniformTypeIdentifiers
import ClarcCore
import ClarcChatKit

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var showGitHubSheet = false
    @State private var showFilePicker = false
    @Environment(\.openSettings) private var openSettings
    @State private var sidebarTab: SidebarTab = .history
    @State private var fileSearchTrigger = false
    @State private var inspectorStarted = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var projectToDelete: Project? = nil
    @State private var projectToRename: Project? = nil
    @State private var renameText: String = ""

    enum SidebarTab: String, CaseIterable {
        case history = "History"
        case files = "Files"

        var icon: String {
            switch self {
            case .files: "folder"
            case .history: "clock"
            }
        }
    }

    var body: some View {
        if !appState.onboardingCompleted {
            OnboardingView()
        } else {
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
                .overlay {
                    if windowState.showMarketplace {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        windowState.showMarketplace = false
                                    }
                                }
                            SkillMarketView()
                                .focusable(false)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .id(appState.themeRevision)
                .onChange(of: windowState.showInspector) { _, isShowing in
                    if isShowing, !inspectorStarted { inspectorStarted = true }
                }
                .onChange(of: appState.focusMode) { _, newValue in
                    windowState.focusMode = newValue
                }
                .onAppear {
                    windowState.focusMode = appState.focusMode
                }
                .navigationTitle({
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    let base = "Clarc(\(appVersion))"
                    if let cliVersion = appState.claudeVersion {
                        return "\(base) — CC \(cliVersion)"
                    }
                    return base
                }())
                .toolbar {
                    if columnVisibility != .detailOnly {
                        ToolbarItemGroup(placement: .confirmationAction) {
                            Button {
                                showGitHubSheet = true
                            } label: {
                                Image("GitHubMark")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(ClaudeTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help(appState.isLoggedIn ? "Manage GitHub Repos" : "Connect GitHub")

                            Button {
                                showFilePicker = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16))
                                    .foregroundStyle(ClaudeTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Add Project")
                            .fileImporter(
                                isPresented: $showFilePicker,
                                allowedContentTypes: [.folder],
                                allowsMultipleSelection: false
                            ) { result in
                                handleFolderSelection(result)
                            }
                        }
                    
                    }
                }

                if inspectorStarted {
                    InspectorPanel()
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            if windowState.selectedProject != nil {
                ClaudeSegmentedControl(selection: $sidebarTab)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                switch sidebarTab {
                case .files:
                    FileTreeView(projectPath: windowState.selectedProject!.path, searchTrigger: $fileSearchTrigger)
                case .history:
                    HistoryListView()
                }
            } else {
                HistoryListView()
            }

            if windowState.selectedProject != nil {
                SidebarTabShortcuts(sidebarTab: $sidebarTab, fileSearchTrigger: $fileSearchTrigger, columnVisibility: $columnVisibility)
            }

            ClaudeThemeDivider()

            if let project = windowState.selectedProject {
                GitStatusView(projectPath: project.path)
            }
        }
        .background(ClaudeTheme.sidebarBackground)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        .sheet(isPresented: $showGitHubSheet) {
            GitHubSheet()
        }
    }

    // MARK: - Chat Toolbar Area (moved from old ChatView)

    @Environment(\.openWindow) private var openWindow

    private var chatToolbarArea: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // isSelected is computed here and passed as a value so ProjectTabButton.body
                    // does not access windowState.selectedProject — only the 2 changed buttons re-render.
                    ForEach(appState.projects) { project in
                        ProjectTabButton(
                            project: project,
                            isSelected: windowState.selectedProject?.id == project.id,
                            projectToDelete: $projectToDelete,
                            projectToRename: $projectToRename,
                            renameText: $renameText
                        )
                    }
                }
            }

            Spacer()

            ChatToolbarControls()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ClaudeTheme.surfaceElevated)
        .confirmationDialog(
            "Delete \"\(projectToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    Task { await appState.deleteProject(project, in: windowState) }
                }
                projectToDelete = nil
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("This will remove the project from Clarc. The files on disk will not be deleted.")
        }
        .sheet(item: $projectToRename) { project in
            RenameProjectSheet(name: $renameText) {
                Task { await appState.renameProject(project, to: renameText) }
            }
        }
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
            } else if !windowState.isInitialized {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ClaudeTheme.background)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 48))
                        .foregroundStyle(ClaudeTheme.accent)

                    Text("Select a Project")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ClaudeTheme.textPrimary)

                    Text("Select a project from the sidebar or add a new one.")
                        .font(.subheadline)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ClaudeTheme.background)
            }
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
        .focusedValue(\.startNewChat) {
            appState.startNewChat(in: windowState)
        }
        // Toolbar is in an isolated struct so NSToolbar does not re-layout on project switches.
        .background {
            DetailToolbar()
        }
    }

    // MARK: - Folder Selection

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task { await appState.addProjectFromFolder(url, in: windowState) }
    }
}

// MARK: - Detail Toolbar (isolated struct — no selectedProject dependency, prevents NSToolbar re-layout on project switch)

struct DetailToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .toolbar {
                ToolbarItemGroup(placement: .confirmationAction) {
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

                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
    }
}

// MARK: - Project Tab Button (isolated — isSelected passed as value, body reads no @Observable properties)

struct ProjectTabButton: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.openWindow) private var openWindow

    let project: Project
    let isSelected: Bool
    @Binding var projectToDelete: Project?
    @Binding var projectToRename: Project?
    @Binding var renameText: String

    var body: some View {
        Button {
            appState.selectProject(project, in: windowState)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? ClaudeTheme.textOnAccent : ClaudeTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? ClaudeTheme.accent : ClaudeTheme.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
            )
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            openWindow(id: "project-window", value: ProjectWindowValue(projectId: project.id, instanceId: UUID()))
        }
        .contextMenu {
            Button {
                renameText = project.name
                projectToRename = project
            } label: {
                Label("Rename Project", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                projectToDelete = project
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        }
    }
}

// MARK: - Inspector Tab Control

struct InspectorTabControl: View {
    @Binding var selection: InspectorTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(LocalizedStringKey(tab.rawValue))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .foregroundStyle(selection == tab ? ClaudeTheme.textOnAccent : ClaudeTheme.textSecondary)
                        .background(
                            selection == tab ? ClaudeTheme.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
    }
}

// MARK: - Inspector Panel

struct InspectorPanel: View {
    @Environment(WindowState.self) private var windowState
    @State private var inspectorProcess = TerminalProcess()
    @State private var terminalResetID = UUID()
    @State private var memoClearID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                InspectorTabControl(selection: Bindable(windowState).inspectorTab)

                Spacer()

                if windowState.inspectorTab == .terminal {
                    InspectorIconButton(help: "Reset Terminal") {
                        inspectorProcess.terminate()
                        inspectorProcess = TerminalProcess()
                        terminalResetID = UUID()
                    }
                } else if windowState.inspectorTab == .memo {
                    InspectorIconButton(help: "Clear Memo") {
                        memoClearID = UUID()
                    }
                }

                Button {
                    windowState.showInspector = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("w", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ClaudeThemeDivider()

            EmbeddedTerminalView(
                executable: "/bin/zsh",
                arguments: ["-il"],
                currentDirectory: windowState.selectedProject?.path,
                process: inspectorProcess
            )
            .id(terminalResetID)
            .padding(8)
            .background(ClaudeTheme.codeBackground)
            .frame(maxHeight: windowState.inspectorTab == .terminal ? .infinity : 0)
            .clipped()

            InspectorMemoPanel(projectId: windowState.selectedProject?.id, clearTrigger: memoClearID)
                .frame(maxHeight: windowState.inspectorTab == .memo ? .infinity : 0)
                .clipped()
        }
        .background(ClaudeTheme.surfaceElevated)
        .frame(
            minWidth: windowState.showInspector ? 380 : 0,
            maxWidth: windowState.showInspector ? .infinity : 0
        )
        .opacity(windowState.showInspector ? 1 : 0)
        .clipped()
    }
}

private struct InspectorIconButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Claude Segmented Control

struct ClaudeSegmentedControl: View {
    @Binding var selection: MainView.SidebarTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainView.SidebarTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .foregroundStyle(selection == tab ? ClaudeTheme.textOnAccent : ClaudeTheme.textSecondary)
                    .background(
                        selection == tab ? ClaudeTheme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
    }
}

// MARK: - Sidebar Tab Shortcuts

struct SidebarTabShortcuts: View {
    @Binding var sidebarTab: MainView.SidebarTab
    @Binding var fileSearchTrigger: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background {
                Button("") {
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .files }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fileSearchTrigger.toggle() }
                }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()

                Button("") {
                    columnVisibility = .all
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .history }
                }
                .keyboardShortcut("1", modifiers: .command)
                .hidden()

                Button("") {
                    columnVisibility = .all
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .files }
                }
                .keyboardShortcut("2", modifiers: .command)
                .hidden()
            }
    }
}

// MARK: - Shared Chat UI Components

private func effortDisplayName(_ effort: String) -> String {
    switch effort {
    case "low": return "Low"
    case "medium": return "Medium"
    case "high": return "High"
    case "xhigh": return "XHigh"
    case "max": return "Max"
    default: return effort.capitalized
    }
}

struct ChatToolbarControls: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    private var effectiveMode: PermissionMode { windowState.sessionPermissionMode ?? appState.permissionMode }
    private var effectiveModel: String { windowState.sessionModel ?? appState.selectedModel }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Section("Permission Mode") {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Button {
                            appState.setSessionPermissionMode(mode, in: windowState)
                        } label: {
                            Label(LocalizedStringKey(mode.displayName), systemImage: mode.systemImage)
                            if effectiveMode == mode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                ToolbarChipLabel(
                    title: effectiveMode.displayName,
                    isModified: windowState.sessionPermissionMode != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Permission mode: \(effectiveMode.displayName)")

            Menu {
                Section("Model Picker") {
                    ForEach(AppState.availableModels, id: \.self) { model in
                        Button {
                            appState.setSessionModel(model, in: windowState)
                        } label: {
                            Text(AppState.modelDisplayName(model))
                            if effectiveModel == model { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                ToolbarChipLabel(
                    title: AppState.modelDisplayName(effectiveModel),
                    isModified: windowState.sessionModel != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Model: \(AppState.modelDisplayName(effectiveModel))")

            Menu {
                Section("Effort Picker") {
                    Button {
                        appState.setSessionEffort(nil, in: windowState)
                    } label: {
                        Text("Auto Effort")
                        if windowState.sessionEffort == nil { Image(systemName: "checkmark") }
                    }
                    Divider()
                    ForEach(AppState.availableEfforts, id: \.self) { effort in
                        Button {
                            appState.setSessionEffort(effort, in: windowState)
                        } label: {
                            Text(LocalizedStringKey(effortDisplayName(effort)))
                            if windowState.sessionEffort == effort { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                ToolbarChipLabel(
                    title: windowState.sessionEffort.map { effortDisplayName($0) } ?? "Auto Effort",
                    isModified: windowState.sessionEffort != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Effort level: \(windowState.sessionEffort.map { effortDisplayName($0) } ?? "Auto Effort")")
        }
    }
}

struct ToolbarChipLabel: View {
    let title: String
    let isModified: Bool

    @State private var isHovered = false

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isModified ? ClaudeTheme.accent : ClaudeTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isHovered
                ? (isModified ? ClaudeTheme.accent.opacity(0.12) : ClaudeTheme.surfaceTertiary)
                : (isModified ? ClaudeTheme.accent.opacity(0.08) : ClaudeTheme.surfaceSecondary),
            in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .strokeBorder(
                    isModified ? ClaudeTheme.accent.opacity(0.3) : ClaudeTheme.borderSubtle,
                    lineWidth: 0.5
                )
        )
        .onHover { isHovered = $0 }
        .pointerCursorOnHover()
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct ChatDetailModifiers: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    func body(content: Content) -> some View {
        content
            .overlay {
                if let request = windowState.pendingPermissions.first {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        PermissionModal(request: request)
                            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusLarge))
                            .shadow(color: ClaudeTheme.shadowColor, radius: 20)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: windowState.pendingPermissions.count)
                }
            }
            .sheet(isPresented: Bindable(windowState).showModelPicker) {
                ModelPickerSheet()
                    .environment(appState)
                    .environment(windowState)
            }
            .sheet(isPresented: Bindable(windowState).showEffortPicker) {
                EffortPickerSheet()
                    .environment(appState)
                    .environment(windowState)
            }
            .sheet(item: Bindable(windowState).interactiveTerminal) { terminal in
                InteractiveTerminalPopup(state: terminal)
            }
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    private var effectiveModel: String { windowState.sessionModel ?? appState.selectedModel }

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Model")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)

            VStack(spacing: 8) {
                ForEach(AppState.availableModels.indices, id: \.self) { index in
                    let model = AppState.availableModels[index]
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppState.modelDisplayName(model))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ClaudeTheme.textPrimary)
                            Text(AppState.modelDescription(model))
                                .font(.system(size: 11))
                                .foregroundStyle(ClaudeTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if effectiveModel == model {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ClaudeTheme.accent)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(index == selectedIndex ? ClaudeTheme.accentSubtle : ClaudeTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
                    .onTapGesture {
                        appState.setSessionModel(model, in: windowState)
                        dismiss()
                    }
                }
            }

            Text("↑↓ Select  ↵ Confirm  esc Cancel")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .padding(20)
        .frame(width: 380)
        .background(ClaudeTheme.background)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            selectedIndex = (selectedIndex - 1 + AppState.availableModels.count) % AppState.availableModels.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = (selectedIndex + 1) % AppState.availableModels.count
            return .handled
        }
        .onKeyPress(.return) {
            appState.setSessionModel(AppState.availableModels[selectedIndex], in: windowState)
            dismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            selectedIndex = AppState.availableModels.firstIndex(of: effectiveModel) ?? 0
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

// MARK: - Effort Picker Sheet

struct EffortPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    // 0 = Auto (nil), 1...n = availableEfforts
    private let items: [String?] = [nil] + AppState.availableEfforts.map { Optional($0) }

    private var effectiveEffort: String? { windowState.sessionEffort }

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Effort Level")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)

            VStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { index in
                    let effort = items[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(effort.map { effortDisplayName($0) } ?? "Auto")
                                .foregroundStyle(ClaudeTheme.textPrimary)
                            if effort == "max" {
                                Text("Opus 4.6 only")
                                    .font(.caption2)
                                    .foregroundStyle(ClaudeTheme.textTertiary)
                            }
                        }
                        Spacer()
                        if effectiveEffort == effort {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ClaudeTheme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(index == selectedIndex ? ClaudeTheme.accentSubtle : ClaudeTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
                    .onTapGesture {
                        windowState.sessionEffort = effort
                        dismiss()
                    }
                }
            }

            Text("↑↓ Select  ↵ Confirm  esc Cancel")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .padding(20)
        .frame(width: 300)
        .background(ClaudeTheme.background)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            selectedIndex = (selectedIndex - 1 + items.count) % items.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = (selectedIndex + 1) % items.count
            return .handled
        }
        .onKeyPress(.return) {
            windowState.sessionEffort = items[selectedIndex]
            dismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            selectedIndex = items.firstIndex(where: { $0 == effectiveEffort }) ?? 0
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

#Preview {
    MainView()
        .environment(AppState())
        .environment(WindowState())
}
