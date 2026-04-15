import SwiftUI
import UniformTypeIdentifiers
import ClarcCore
import ClarcChatKit

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var showGitHubSheet = false
    @State private var showFilePicker = false
    @State private var showCommandManager = false
    @State private var showShortcutManager = false
    @Environment(\.openSettings) private var openSettings
    @State private var sidebarTab: SidebarTab = .history
    @State private var fileSearchTrigger = false
    @State private var inspectorStarted = false
    @State private var inspectorProcess = TerminalProcess()

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
                NavigationSplitView {
                    sidebarContent
                } detail: {
                    detailContent
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
                .navigationTitle({
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    let base = "Clarc(\(appVersion))"
                    if let cliVersion = appState.claudeVersion {
                        return "\(base) — CC \(cliVersion)"
                    }
                    return base
                }())
                .toolbar {
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

                if inspectorStarted {
                    inspectorPanel
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
                SidebarTabShortcuts(sidebarTab: $sidebarTab, fileSearchTrigger: $fileSearchTrigger)
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
        .sheet(isPresented: $showCommandManager) {
            SlashCommandManagerView(projectName: windowState.selectedProject?.name ?? "")
                .onDisappear { windowState.registryVersion += 1 }
        }
        .sheet(isPresented: $showShortcutManager) {
            ShortcutManagerView(projectName: windowState.selectedProject?.name ?? "")
                .onDisappear { windowState.registryVersion += 1 }
        }
    }

    // MARK: - Chat Toolbar Area (moved from old ChatView)

    @Environment(\.openWindow) private var openWindow

    private var chatToolbarArea: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(appState.projects) { project in
                        let isSelected = windowState.selectedProject?.id == project.id
                        Button {
                            Task { await appState.selectProject(project, in: windowState) }
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
                            openWindow(id: "project-window", value: project.id)
                        }
                    }
                }
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
        .toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                ControlGroup {
                    Button {
                        appState.startNewChat(in: windowState)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New Chat")
                    Button {
                        showCommandManager = true
                    } label: {
                        Text("/")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
                    .help("Manage Slash Commands")


                    if windowState.selectedProject != nil {
                        Button {
                            showShortcutManager = true
                        } label: {
                            Image(systemName: "bolt.fill")
                        }
                        .help("Manage Shortcuts")
                    }
                }


                Button {
                    windowState.showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle Inspector")

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }


        }

    }

    // MARK: - Inspector Panel (Terminal + Memo with tabs)

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            // Header: icon + tab control + close button
            HStack(spacing: 8) {
                InspectorTabControl(selection: Bindable(windowState).inspectorTab)

                Spacer()

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

            // Terminal content — kept in hierarchy to preserve process
            EmbeddedTerminalView(
                executable: "/bin/zsh",
                arguments: ["-il"],
                currentDirectory: windowState.selectedProject?.path,
                process: inspectorProcess
            )
            .padding(8)
            .background(ClaudeTheme.codeBackground)
            .frame(maxHeight: windowState.inspectorTab == .terminal ? .infinity : 0)
            .clipped()

            // Memo content
            InspectorMemoPanel()
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

    // MARK: - Folder Selection

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task { await appState.addProjectFromFolder(url, in: windowState) }
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
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .history }
                }
                .keyboardShortcut("1", modifiers: .command)
                .hidden()

                Button("") {
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .files }
                }
                .keyboardShortcut("2", modifiers: .command)
                .hidden()
            }
    }
}

// MARK: - Shared Chat UI Components

struct ChatToolbarControls: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appState.dangerouslySkipPermissions.toggle()
            } label: {
                Image(systemName: appState.dangerouslySkipPermissions ? "bolt.shield.fill" : "bolt.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(appState.dangerouslySkipPermissions ? .red : .green)
            }
            .buttonStyle(.plain)
            .help(appState.dangerouslySkipPermissions ? "Skip Permissions: ON" : "Skip Permissions: OFF")

            Picker("", selection: Bindable(appState).selectedModel) {
                ForEach(AppState.availableModels, id: \.self) { model in
                    Text(model.capitalized).tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
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
            }
            .sheet(item: Bindable(windowState).interactiveTerminal) { terminal in
                InteractiveTerminalPopup(state: terminal)
            }
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Model")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)

            VStack(spacing: 8) {
                ForEach(AppState.availableModels.indices, id: \.self) { index in
                    let model = AppState.availableModels[index]
                    HStack {
                        Text(model.capitalized)
                            .foregroundStyle(ClaudeTheme.textPrimary)
                        Spacer()
                        if appState.selectedModel == model {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ClaudeTheme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(index == selectedIndex ? ClaudeTheme.accentSubtle : ClaudeTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
                    .onTapGesture {
                        appState.selectedModel = model
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
            selectedIndex = (selectedIndex - 1 + AppState.availableModels.count) % AppState.availableModels.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = (selectedIndex + 1) % AppState.availableModels.count
            return .handled
        }
        .onKeyPress(.return) {
            appState.selectedModel = AppState.availableModels[selectedIndex]
            dismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            selectedIndex = AppState.availableModels.firstIndex(of: appState.selectedModel) ?? 0
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

#Preview {
    MainView()
        .environment(AppState())
        .environment(WindowState())
}
