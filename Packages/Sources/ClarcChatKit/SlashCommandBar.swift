import SwiftUI
import ClarcCore

// MARK: - Slash Command Data

public struct SlashCommand: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var detailDescription: String?
    public var acceptsInput: Bool
    public var isInteractive: Bool

    public var command: String { "/\(name)" }

    public init(name: String, description: String, detailDescription: String? = nil, acceptsInput: Bool = false, isInteractive: Bool = false) {
        self.name = name
        self.description = description
        self.detailDescription = detailDescription
        self.acceptsInput = acceptsInput
        self.isInteractive = isInteractive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        detailDescription = try c.decodeIfPresent(String.self, forKey: .detailDescription)
        acceptsInput = try c.decodeIfPresent(Bool.self, forKey: .acceptsInput) ?? false
        isInteractive = try c.decodeIfPresent(Bool.self, forKey: .isInteractive) ?? false
    }
}

// MARK: - Custom Command Store

public struct CustomCommandStore: Codable {
    public var customCommands: [SlashCommand] = []
    public var modifiedDefaults: [String: SlashCommand] = [:]
    public var hiddenDefaults: Set<String> = []
    public var disabledCommands: Set<String> = []

    public init() {}
}

extension CustomCommandStore {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customCommands = try c.decodeIfPresent([SlashCommand].self, forKey: .customCommands) ?? []
        modifiedDefaults = try c.decodeIfPresent([String: SlashCommand].self, forKey: .modifiedDefaults) ?? [:]
        hiddenDefaults = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenDefaults) ?? []
        disabledCommands = try c.decodeIfPresent(Set<String>.self, forKey: .disabledCommands) ?? []
    }
}

@MainActor
public enum SlashCommandRegistry {
    private static var currentProjectPath: String?
    public static var store: CustomCommandStore = Self.loadStore()
    private static var _cachedCommands: [SlashCommand]?

    // MARK: - Project Binding

    public static func bind(to projectPath: String?) {
        guard currentProjectPath != projectPath else { return }
        currentProjectPath = projectPath
        store = loadStore()
        invalidateCache()
    }

    public static var commands: [SlashCommand] {
        if let cached = _cachedCommands { return cached }
        let result = buildCommands()
        _cachedCommands = result
        return result
    }

    private static func buildCommands() -> [SlashCommand] {
        var result: [SlashCommand] = []
        for cmd in defaultCommands {
            if store.hiddenDefaults.contains(cmd.name) { continue }
            result.append(store.modifiedDefaults[cmd.name] ?? cmd)
        }
        result.append(contentsOf: store.customCommands)
        return result.sorted { $0.name < $1.name }
    }

    private static func invalidateCache() {
        _cachedCommands = nil
    }

    public static let defaultCommands: [SlashCommand] = [
        // Custom skills
        SlashCommand(name: "deploy", description: "Deploy iOS app (dev/qa/prod)", acceptsInput: true),
        SlashCommand(name: "app-store-changelog", description: "Generate App Store release notes"),

        // CLI built-in: conversation
        SlashCommand(name: "btw", description: "Side question not added to conversation", acceptsInput: true),
        SlashCommand(name: "compact", description: "Compact conversation (focus instructions allowed)", acceptsInput: true),
        SlashCommand(name: "copy", description: "Copy last response to clipboard", acceptsInput: true),
        SlashCommand(name: "export", description: "Export conversation as text", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "branch", description: "Create a branch of current conversation", acceptsInput: true),
        SlashCommand(name: "resume", description: "Resume a previous conversation", acceptsInput: true),
        SlashCommand(name: "rewind", description: "Rewind to a previous point", isInteractive: true),
        SlashCommand(name: "rename", description: "Rename session", acceptsInput: true),
        SlashCommand(name: "diff", description: "Diff viewer for uncommitted changes", isInteractive: true),

        // CLI built-in: model & mode
        SlashCommand(name: "model", description: "Select/change AI model", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "fast", description: "Toggle fast mode", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "effort", description: "Set model effort level", acceptsInput: true, isInteractive: true),

        // CLI built-in: usage & stats
        SlashCommand(name: "cost", description: "Token usage statistics", isInteractive: true),
        SlashCommand(name: "usage", description: "Plan usage limits and rate limits", isInteractive: true),
        SlashCommand(name: "stats", description: "Daily usage and session history visualization", isInteractive: true),
        SlashCommand(name: "extra-usage", description: "Configure extra usage", isInteractive: true),

        // CLI built-in: settings
        SlashCommand(name: "config", description: "Settings interface", isInteractive: true),
        SlashCommand(name: "permissions", description: "Manage permissions", isInteractive: true),
        SlashCommand(name: "privacy-settings", description: "Privacy settings (Pro/Max)", isInteractive: true),
        SlashCommand(name: "theme", description: "Change color theme", isInteractive: true),
        SlashCommand(name: "color", description: "Set prompt bar color", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "statusline", description: "Configure status line", isInteractive: true),
        SlashCommand(name: "keybindings", description: "Configure keybindings", isInteractive: true),
        SlashCommand(name: "terminal-setup", description: "Configure terminal keybindings", isInteractive: true),
        SlashCommand(name: "vim", description: "Toggle Vim mode", isInteractive: true),
        SlashCommand(name: "sandbox", description: "Toggle sandbox mode", isInteractive: true),

        // CLI built-in: project
        SlashCommand(name: "init", description: "Initialize project with CLAUDE.md", isInteractive: true),
        SlashCommand(name: "memory", description: "Edit CLAUDE.md memory file", isInteractive: true),
        SlashCommand(name: "add-dir", description: "Add working directory to session", acceptsInput: true),
        SlashCommand(name: "context", description: "Visualize context usage"),
        SlashCommand(name: "plan", description: "Enter plan mode", acceptsInput: true),
        SlashCommand(name: "tasks", description: "Manage background tasks"),
        SlashCommand(name: "skills", description: "List available skills", isInteractive: true),
        SlashCommand(name: "insights", description: "Session analysis report"),
        SlashCommand(name: "simplify", description: "Review and fix code quality/efficiency of changes"),
        SlashCommand(name: "security-review", description: "Analyze security vulnerabilities"),
        SlashCommand(name: "pr-comments", description: "Fetch PR comments", acceptsInput: true),
        SlashCommand(name: "loop", description: "Repeat execution (e.g. /loop 5m /foo)", acceptsInput: true),
        SlashCommand(name: "schedule", description: "Manage cloud scheduled tasks", acceptsInput: true),

        // CLI built-in: extensions
        SlashCommand(name: "agents", description: "Manage agent configuration", isInteractive: true),
        SlashCommand(name: "hooks", description: "View hook configuration", isInteractive: true),
        SlashCommand(name: "plugin", description: "Manage plugins", isInteractive: true),
        SlashCommand(name: "reload-plugins", description: "Reload plugins", isInteractive: true),
        SlashCommand(name: "mcp", description: "Manage MCP servers", isInteractive: true),
        SlashCommand(name: "ide", description: "Manage IDE integration", isInteractive: true),
        SlashCommand(name: "chrome", description: "Configure Claude in Chrome", isInteractive: true),
        SlashCommand(name: "desktop", description: "Continue in Desktop app", isInteractive: true),
        SlashCommand(name: "remote-control", description: "Remote control from claude.ai", isInteractive: true),
        SlashCommand(name: "remote-env", description: "Configure remote environment", isInteractive: true),
        SlashCommand(name: "schedule-cc", description: "Manage cloud scheduled tasks", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "voice", description: "Toggle voice dictation", isInteractive: true),

        // CLI built-in: account & system
        SlashCommand(name: "login", description: "Log in to Anthropic account", isInteractive: true),
        SlashCommand(name: "logout", description: "Log out of Anthropic account", isInteractive: true),
        SlashCommand(name: "install-github-app", description: "Set up GitHub Actions app", isInteractive: true),
        SlashCommand(name: "install-slack-app", description: "Install Slack app", isInteractive: true),
        SlashCommand(name: "mobile", description: "Mobile app QR code", isInteractive: true),
        SlashCommand(name: "doctor", description: "Diagnose installation/configuration", isInteractive: true),
        SlashCommand(name: "status", description: "Version, model, and account status", isInteractive: true),
        SlashCommand(name: "help", description: "Show help", isInteractive: true),
        SlashCommand(name: "feedback", description: "Submit feedback/bug report", isInteractive: true),
        SlashCommand(name: "release-notes", description: "View changelog", isInteractive: true),
        SlashCommand(name: "upgrade", description: "Upgrade plan", isInteractive: true),
        SlashCommand(name: "stickers", description: "Order Claude Code stickers", isInteractive: true),
        SlashCommand(name: "passes", description: "Share free 1-week passes", isInteractive: true),
        SlashCommand(name: "exit", description: "Exit CLI"),
    ]


    // MARK: - Persistence

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clarcDir = appSupport.appendingPathComponent("Clarc")

        if let projectPath = currentProjectPath {
            let safeName = projectPath
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            return clarcDir
                .appendingPathComponent("projects")
                .appendingPathComponent(safeName)
                .appendingPathComponent("custom_commands.json")
        } else {
            return clarcDir.appendingPathComponent("custom_commands.json")
        }
    }

    private static func loadStore() -> CustomCommandStore {
        let url = storeURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CustomCommandStore.self, from: data)
        else { return CustomCommandStore() }
        return decoded
    }

    static func saveStore() {
        do {
            let url = storeURL
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save custom commands: \(error)")
        }
    }

    static func addCustomCommand(_ cmd: SlashCommand) {
        store.customCommands.append(cmd)
        invalidateCache()
        saveStore()
    }

    static func replaceCustomCommand(name: String, with cmd: SlashCommand) {
        store.customCommands.removeAll { $0.name == name }
        store.customCommands.append(cmd)
        invalidateCache()
        saveStore()
    }

    static func removeCustomCommand(name: String) {
        store.customCommands.removeAll { $0.name == name }
        invalidateCache()
        saveStore()
    }

    static func modifyDefault(originalName: String, modified: SlashCommand) {
        store.modifiedDefaults[originalName] = modified
        invalidateCache()
        saveStore()
    }

    static func hideDefault(name: String) {
        store.hiddenDefaults.insert(name)
        store.modifiedDefaults.removeValue(forKey: name)
        invalidateCache()
        saveStore()
    }

    static func resetAllDefaults() {
        store.hiddenDefaults.removeAll()
        store.modifiedDefaults.removeAll()
        invalidateCache()
        saveStore()
    }

    static func isDefault(name: String) -> Bool {
        defaultCommands.contains { $0.name == name }
    }

    static func isHidden(name: String) -> Bool {
        store.hiddenDefaults.contains(name)
    }

    static func isModified(name: String) -> Bool {
        store.modifiedDefaults[name] != nil
    }

    static func isEnabled(name: String) -> Bool {
        !store.disabledCommands.contains(name)
    }

    static func setEnabled(name: String, _ enabled: Bool) {
        if enabled {
            store.disabledCommands.remove(name)
        } else {
            store.disabledCommands.insert(name)
        }
        invalidateCache()
        saveStore()
    }

    static func originalDefault(name: String) -> SlashCommand? {
        defaultCommands.first { $0.name == name }
    }

    // MARK: - Export / Import

    static func exportCommands() -> Data? {
        let customOnly = commands.filter { !isDefault(name: $0.name) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if customOnly.isEmpty {
            let example = [SlashCommand(
                name: "example",
                description: "Slash command description",
                detailDescription: "Detail description (optional)",
                acceptsInput: true,
                isInteractive: false
            )]
            return try? encoder.encode(example)
        }
        return try? encoder.encode(customOnly)
    }

    static func importCommands(from data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode([SlashCommand].self, from: data) else {
            return false
        }
        let importedByName = Dictionary(imported.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })

        var newStore = CustomCommandStore()

        for def in defaultCommands {
            if let imp = importedByName[def.name] {
                if imp != def {
                    newStore.modifiedDefaults[def.name] = imp
                }
            } else {
                newStore.hiddenDefaults.insert(def.name)
            }
        }

        for imp in imported where !isDefault(name: imp.name) {
            newStore.customCommands.append(imp)
        }

        store = newStore
        invalidateCache()
        saveStore()
        return true
    }

    static var enabledCommands: [SlashCommand] {
        commands.filter { isEnabled(name: $0.name) }
    }

    static func filtered(by query: String) -> [SlashCommand] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty || q == "/" { return enabledCommands }
        let search = q.hasPrefix("/") ? String(q.dropFirst()) : q
        return enabledCommands.filter {
            $0.name.lowercased().contains(search) ||
            $0.description.lowercased().contains(search)
        }
    }
}

// MARK: - Slash Command Popup

struct SlashCommandPopup: View {
    let query: String
    let onSelect: (SlashCommand) -> Void
    @Binding var selectedIndex: Int
    @State private var detailCommand: SlashCommand?

    private var filtered: [SlashCommand] {
        SlashCommandRegistry.filtered(by: query)
    }

    func showDetailForSelected() {
        let cmds = filtered
        guard selectedIndex >= 0, selectedIndex < cmds.count else { return }
        let cmd = cmds[selectedIndex]
        if cmd.detailDescription != nil {
            detailCommand = cmd
        }
    }

    var body: some View {
        if filtered.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "command")
                        .font(.system(size: 10))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text("Slash Commands", bundle: .module)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Spacer()
                    Text("\(filtered.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()
                    .foregroundStyle(ClaudeTheme.borderSubtle)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, cmd in
                                commandRowButton(cmd, isSelected: index == selectedIndex)
                                    .id(index)
                            }
                        }
                    }
                    .id(query)
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
            .frame(height: 320)
            .background(ClaudeTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium)
                    .strokeBorder(ClaudeTheme.border, lineWidth: 1)
            )
            .shadow(color: ClaudeTheme.shadowColor, radius: 12, y: -4)
            .sheet(item: $detailCommand) { cmd in
                CommandDetailSheet(command: cmd)
            }
        }
    }

    @ViewBuilder
    private func commandRowButton(_ cmd: SlashCommand, isSelected: Bool) -> some View {
        HStack(spacing: 0) {
            // Clicking this area executes the command
            Button {
                onSelect(cmd)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(cmd.command)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(isSelected ? ClaudeTheme.accent : ClaudeTheme.textPrimary)

                            if cmd.acceptsInput {
                                Text("accepts input", bundle: .module)
                                    .font(.system(size: 9))
                                    .foregroundStyle(ClaudeTheme.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(ClaudeTheme.surfaceSecondary, in: Capsule())
                            }
                        }

                        Text(LocalizedStringKey(cmd.description), bundle: .module)
                            .font(.system(size: 11))
                            .foregroundStyle(ClaudeTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if cmd.detailDescription != nil {
                Button {
                    detailCommand = cmd
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? ClaudeTheme.accentSubtle : Color.clear)
    }

    var filteredCount: Int { filtered.count }

    func command(at index: Int) -> SlashCommand? {
        guard index >= 0 && index < filtered.count else { return nil }
        return filtered[index]
    }
}

// MARK: - Command Detail Sheet

struct CommandDetailSheet: View {
    let command: SlashCommand
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.command)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)

                    Text(LocalizedStringKey(command.description), bundle: .module)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }

                Spacer()
            }
            .padding(20)

            ClaudeThemeDivider()

            // Body
            ScrollView {
                if let detail = command.detailDescription {
                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }

            ClaudeThemeDivider()

            // Close
            HStack {
                Spacer()
                Button(String(localized: "Close", bundle: .module)) { dismiss() }
                    .buttonStyle(ClaudeSecondaryButtonStyle())
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
        .background(ClaudeTheme.background)
    }
}

// MARK: - SlashCommand + Identifiable for sheet

// SlashCommand: Hashable conformance is in the struct declaration (name-based identity)

// MARK: - Command Menu Button

struct CommandMenuButton: View {
    let messages: [ChatMessage]
    @Environment(WindowState.self) private var windowState
    @State private var isCopied = false
    @State private var showUsagePopover = false
    @State private var showCommandManager = false

    var body: some View {
        Menu {
            Button {
                copyConversation()
            } label: {
                Label(isCopied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy Conversation", bundle: .module), systemImage: isCopied ? "checkmark" : "doc.on.doc")
            }
            .disabled(messages.isEmpty)

            Button {
                showUsagePopover = true
            } label: {
                Label(String(localized: "Usage", bundle: .module), systemImage: "chart.bar")
            }

            Divider()

            Button {
                showCommandManager = true
            } label: {
                Label(String(localized: "Manage Commands", bundle: .module), systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(ClaudeTheme.textSecondary)
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .help("Commands")
        .popover(isPresented: $showUsagePopover, arrowEdge: .top) { UsagePopoverView() }
        .sheet(isPresented: $showCommandManager) {
            SlashCommandManagerView(projectName: windowState.selectedProject?.name ?? "")
                .onDisappear { windowState.registryVersion += 1 }
        }
    }

    private func copyConversation() {
        let text = messages.map { msg in
            let role = msg.role == .user ? "Me" : "Claude"
            return "[\(role)] \(msg.content)"
        }.joined(separator: "\n\n")

        copyToClipboard(text, feedback: $isCopied)
    }
}

// MARK: - Usage Popover

struct UsagePopoverView: View {
    @Environment(ChatBridge.self) private var chatBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Usage", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ClaudeTheme.textPrimary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                usageRow(icon: "dollarsign.circle", label: "Cost", value: formatCost(chatBridge.sessionStats.costUsd))
                usageRow(icon: "arrow.down.circle", label: "Input tokens", value: formatTokens(chatBridge.sessionStats.inputTokens))
                usageRow(icon: "arrow.up.circle", label: "Output tokens", value: formatTokens(chatBridge.sessionStats.outputTokens))
                usageRow(icon: "square.stack", label: "Cache creation", value: formatTokens(chatBridge.sessionStats.cacheCreationTokens))
                usageRow(icon: "square.stack.fill", label: "Cache read", value: formatTokens(chatBridge.sessionStats.cacheReadTokens))
                usageRow(icon: "clock", label: "Duration", value: formatDuration(chatBridge.sessionStats.durationMs))
                usageRow(icon: "arrow.triangle.2.circlepath", label: "Turns", value: "\(chatBridge.sessionStats.turns)")
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    @ViewBuilder
    private func usageRow(icon: String, label: String, value: String) -> some View {
        GridRow {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ClaudeTheme.textPrimary)
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "—" }
        return String(format: "$%.4f", cost)
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens == 0 { return "—" }
        if tokens >= 1_000_000 {
            return String(format: "%.1fm", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fk", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    private func formatDuration(_ ms: Double) -> String {
        if ms == 0 { return "—" }
        let seconds = Int(ms / 1_000)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }
}

// MARK: - @ File Search Popup

struct AtFilePopup: View {
    let entries: [AtFileEntry]
    let onSelect: (String) -> Void
    @Binding var selectedIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Text("File Search", bundle: .module)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()
                .foregroundStyle(ClaudeTheme.borderSubtle)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            fileRowButton(entry, isSelected: index == selectedIndex)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 320)
        .background(ClaudeTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium)
                .strokeBorder(ClaudeTheme.border, lineWidth: 1)
        )
        .shadow(color: ClaudeTheme.shadowColor, radius: 12, y: -4)
    }

    @ViewBuilder
    private func fileRowButton(_ entry: AtFileEntry, isSelected: Bool) -> some View {
        Button {
            onSelect(entry.relativePath)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? ClaudeTheme.accent : entry.iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? ClaudeTheme.accent : ClaudeTheme.textPrimary)

                    if !entry.directory.isEmpty {
                        Text(entry.directory)
                            .font(.system(size: 11))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? ClaudeTheme.accentSubtle : Color.clear)
    }

}

// MARK: - AtFileEntry

struct AtFileEntry: Identifiable {
    let id: String          // relativePath
    let name: String        // file name
    let directory: String   // parent directory path
    let relativePath: String

    var icon: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "md", "txt": return "doc.text"
        case "png", "jpg", "jpeg", "svg", "pdf": return "photo"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        case "yaml", "yml", "toml": return "gearshape"
        default: return "doc"
        }
    }

    var iconColor: Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "json": return ClaudeTheme.statusSuccess
        case "css", "scss": return .pink
        case "html": return ClaudeTheme.statusError
        case "png", "jpg", "jpeg", "svg", "pdf": return .purple
        default: return ClaudeTheme.textTertiary
        }
    }
}

// MARK: - AtFileSearch

enum AtFileSearch {
    private static let ignoredNames: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData",
        "node_modules", ".DS_Store", "Pods",
        "xcuserdata", ".xcodeproj", ".xcworkspace",
    ]

    static func search(query: String, projectPath: String, maxResults: Int = 20) -> [AtFileEntry] {
        let allFiles = collectFiles(at: projectPath, basePath: projectPath, maxDepth: 6)

        let q = query.lowercased()
        guard !q.isEmpty else {
            return Array(allFiles.prefix(maxResults))
        }

        // Filename match takes priority, path match is secondary
        var nameMatches: [AtFileEntry] = []
        var pathMatches: [AtFileEntry] = []

        for entry in allFiles {
            if entry.name.lowercased().contains(q) {
                nameMatches.append(entry)
            } else if entry.relativePath.lowercased().contains(q) {
                pathMatches.append(entry)
            }
        }

        let combined = nameMatches + pathMatches
        return Array(combined.prefix(maxResults))
    }

    private static func collectFiles(
        at path: String,
        basePath: String,
        maxDepth: Int,
        currentDepth: Int = 0
    ) -> [AtFileEntry] {
        guard currentDepth <= maxDepth else { return [] }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [AtFileEntry] = []

        for url in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = url.lastPathComponent
            if ignoredNames.contains(name) { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                results += collectFiles(
                    at: url.path,
                    basePath: basePath,
                    maxDepth: maxDepth,
                    currentDepth: currentDepth + 1
                )
            } else {
                let relativePath = String(url.path.dropFirst(basePath.count + 1))
                let directory = (relativePath as NSString).deletingLastPathComponent
                results.append(AtFileEntry(
                    id: relativePath,
                    name: name,
                    directory: directory,
                    relativePath: relativePath
                ))
            }
        }

        return results
    }
}
