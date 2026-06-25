import SwiftUI
import ClarcCore

// MARK: - Slash Command Data

public struct SlashCommand: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var detailDescription: String?
    public var aliases: [String]
    public var acceptsInput: Bool
    public var isInteractive: Bool

    public var command: String { "/\(name)" }

    public init(name: String, description: String, detailDescription: String? = nil, aliases: [String] = [], acceptsInput: Bool = false, isInteractive: Bool = false) {
        self.name = name
        self.description = description
        self.detailDescription = detailDescription
        self.aliases = aliases
        self.acceptsInput = acceptsInput
        self.isInteractive = isInteractive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        detailDescription = try c.decodeIfPresent(String.self, forKey: .detailDescription)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
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
    public static var store: CustomCommandStore = Self.loadStore()
    private static var _cachedCommands: [SlashCommand]?

    public static var commands: [SlashCommand] {
        if let cached = _cachedCommands { return cached }
        let result = buildCommands()
        _cachedCommands = result
        return result
    }

    private static func buildCommands() -> [SlashCommand] {
        let modifiedDefaults = sanitizedModifiedDefaults(from: store.modifiedDefaults)
        var result: [SlashCommand] = []
        for command in defaultCommands {
            result.append(modifiedDefaults[command.name] ?? command)
        }
        result.append(contentsOf: sanitizedCustomCommands(from: store.customCommands))
        return result.sorted { $0.name < $1.name }
    }

    private static func invalidateCache() {
        _cachedCommands = nil
    }

    public static let defaultCommands: [SlashCommand] = [
        // CLI built-in: conversation
        SlashCommand(name: "clear", description: "Start a new conversation", aliases: ["reset", "new"]),
        SlashCommand(name: "btw", description: "Side question not added to conversation", acceptsInput: true),
        SlashCommand(name: "compact", description: "Compact conversation (focus instructions allowed)", acceptsInput: true),
        SlashCommand(name: "copy", description: "Copy last response to clipboard", acceptsInput: true),
        SlashCommand(name: "export", description: "Export conversation as text", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "branch", description: "Create a branch of current conversation", acceptsInput: true),
        SlashCommand(name: "fork", description: "Fork conversation to a background subagent", acceptsInput: true),
        SlashCommand(name: "rewind", description: "Rewind to a previous point", aliases: ["checkpoint", "undo"], isInteractive: true),
        SlashCommand(name: "rename", description: "Rename session", acceptsInput: true),
        SlashCommand(name: "diff", description: "Diff viewer for uncommitted changes", isInteractive: true),
        SlashCommand(name: "recap", description: "Generate a one-line session summary"),

        // CLI built-in: model & mode
        SlashCommand(name: "model", description: "Select/change AI model", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "fast", description: "Toggle fast mode", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "effort", description: "Set model effort level", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "advisor", description: "Enable/disable the advisor model", acceptsInput: true, isInteractive: true),

        // CLI built-in: usage & stats
        SlashCommand(name: "cost", description: "Session cost and usage (alias for /usage)", isInteractive: true),
        SlashCommand(name: "usage", description: "Plan usage limits and rate limits", isInteractive: true),
        SlashCommand(name: "stats", description: "Usage stats and history (alias for /usage)", isInteractive: true),
        SlashCommand(name: "usage-credits", description: "Configure usage credits for when you hit a limit", aliases: ["extra-usage"], isInteractive: true),

        // CLI built-in: settings
        SlashCommand(name: "config", description: "Settings interface", aliases: ["settings"], isInteractive: true),
        SlashCommand(name: "permissions", description: "Manage permissions", aliases: ["allowed-tools"], isInteractive: true),
        SlashCommand(name: "privacy-settings", description: "Privacy settings (Pro/Max)", isInteractive: true),
        SlashCommand(name: "theme", description: "Change color theme", isInteractive: true),
        SlashCommand(name: "color", description: "Set prompt bar color", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "statusline", description: "Configure status line", isInteractive: true),
        SlashCommand(name: "keybindings", description: "Configure keybindings", isInteractive: true),
        SlashCommand(name: "terminal-setup", description: "Configure terminal keybindings", isInteractive: true),
        SlashCommand(name: "sandbox", description: "Toggle sandbox mode", isInteractive: true),

        // CLI built-in: project
        SlashCommand(name: "init", description: "Initialize project with CLAUDE.md", isInteractive: true),
        SlashCommand(name: "memory", description: "Edit CLAUDE.md memory file", isInteractive: true),
        SlashCommand(name: "add-dir", description: "Add working directory to session", acceptsInput: true),
        SlashCommand(name: "cd", description: "Change the session working directory", acceptsInput: true),
        SlashCommand(name: "context", description: "Visualize context usage"),
        SlashCommand(name: "plan", description: "Enter plan mode", acceptsInput: true),
        SlashCommand(name: "goal", description: "Keep working until a condition is met", acceptsInput: true),
        SlashCommand(name: "tasks", description: "Manage background tasks", aliases: ["bashes"]),
        SlashCommand(name: "background", description: "Detach session to run as a background agent", aliases: ["bg"], acceptsInput: true),
        SlashCommand(name: "workflows", description: "Watch running and completed workflows", isInteractive: true),
        SlashCommand(name: "skills", description: "List available skills", isInteractive: true),
        SlashCommand(name: "insights", description: "Session analysis report"),
        SlashCommand(name: "code-review", description: "Review the diff for bugs and cleanups", acceptsInput: true),
        SlashCommand(name: "simplify", description: "Review and fix code quality/efficiency of changes"),
        SlashCommand(name: "security-review", description: "Analyze security vulnerabilities"),
        SlashCommand(name: "loop", description: "Repeat execution (e.g. /loop 5m /foo)", aliases: ["proactive"], acceptsInput: true),
        SlashCommand(name: "schedule", description: "Manage cloud scheduled tasks", aliases: ["routines"], acceptsInput: true),
        SlashCommand(name: "autofix-pr", description: "Auto-fix PR CI failures and review comments", acceptsInput: true),
        SlashCommand(name: "batch", description: "Orchestrate large-scale parallel changes", acceptsInput: true),
        SlashCommand(name: "claude-api", description: "Load Claude API reference for current project"),
        SlashCommand(name: "debug", description: "Enable debug logging and diagnose issues", acceptsInput: true),
        SlashCommand(name: "fewer-permission-prompts", description: "Reduce permission prompts by scanning transcripts"),
        SlashCommand(name: "review", description: "Review a pull request locally", acceptsInput: true),
        SlashCommand(name: "deep-research", description: "Research a question into a cited report", acceptsInput: true),
        SlashCommand(name: "run", description: "Launch and drive your app to verify a change"),
        SlashCommand(name: "verify", description: "Build and run the app to confirm a change works"),
        SlashCommand(name: "run-skill-generator", description: "Generate a per-project run/verify skill"),
        SlashCommand(name: "team-onboarding", description: "Generate a team onboarding guide"),

        // CLI built-in: extensions
        SlashCommand(name: "agents", description: "Manage agent configuration", isInteractive: true),
        SlashCommand(name: "hooks", description: "View hook configuration", isInteractive: true),
        SlashCommand(name: "plugin", description: "Manage plugins", isInteractive: true),
        SlashCommand(name: "reload-plugins", description: "Reload plugins", isInteractive: true),
        SlashCommand(name: "reload-skills", description: "Re-scan skills and command directories", isInteractive: true),
        SlashCommand(name: "mcp", description: "Manage MCP servers", isInteractive: true),
        SlashCommand(name: "ide", description: "Manage IDE integration", isInteractive: true),
        SlashCommand(name: "chrome", description: "Configure Claude in Chrome", isInteractive: true),
        SlashCommand(name: "desktop", description: "Continue in Desktop app", aliases: ["app"], isInteractive: true),
        SlashCommand(name: "remote-control", description: "Remote control from claude.ai", aliases: ["rc"], isInteractive: true),
        SlashCommand(name: "remote-env", description: "Configure remote environment", isInteractive: true),
        SlashCommand(name: "voice", description: "Toggle voice dictation", isInteractive: true),
        SlashCommand(name: "powerup", description: "Interactive feature lessons with demos"),
        SlashCommand(name: "teleport", description: "Pull a web session into this terminal", aliases: ["tp"], isInteractive: true),
        SlashCommand(name: "tui", description: "Set terminal UI renderer", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "ultraplan", description: "Draft a plan in an ultraplan session", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "ultrareview", description: "Deep multi-agent cloud code review", acceptsInput: true, isInteractive: true),
        SlashCommand(name: "web-setup", description: "Connect GitHub account to Claude Code on the web"),

        // CLI built-in: account & system
        SlashCommand(name: "login", description: "Log in to Anthropic account", isInteractive: true),
        SlashCommand(name: "logout", description: "Log out of Anthropic account", isInteractive: true),
        SlashCommand(name: "install-github-app", description: "Set up GitHub Actions app", isInteractive: true),
        SlashCommand(name: "install-slack-app", description: "Install Slack app", isInteractive: true),
        SlashCommand(name: "mobile", description: "Mobile app QR code", aliases: ["ios", "android"], isInteractive: true),
        SlashCommand(name: "heapdump", description: "Write heap snapshot for memory diagnostics"),
        SlashCommand(name: "doctor", description: "Diagnose installation/configuration", isInteractive: true),
        SlashCommand(name: "status", description: "Version, model, and account status", isInteractive: true),
        SlashCommand(name: "help", description: "Show help", isInteractive: true),
        SlashCommand(name: "feedback", description: "Submit feedback/bug report", aliases: ["bug", "share"], isInteractive: true),
        SlashCommand(name: "release-notes", description: "View changelog", isInteractive: true),
        SlashCommand(name: "upgrade", description: "Upgrade plan", isInteractive: true),
        SlashCommand(name: "stickers", description: "Order Claude Code stickers", isInteractive: true),
        SlashCommand(name: "passes", description: "Share free 1-week passes", isInteractive: true),
        SlashCommand(name: "exit", description: "Exit CLI", aliases: ["quit"]),
    ]

    private static var defaultCommandKeys: Set<String> {
        Set(defaultCommands.map { commandKey($0.name) })
    }

    static func normalizedNameForInput(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.drop { $0 == "/" })
    }

    private static func commandKey(_ name: String) -> String {
        normalizedNameForInput(name).lowercased()
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        commandKey(lhs) == commandKey(rhs)
    }

    private static func sanitizedCustomCommands(from commands: [SlashCommand]) -> [SlashCommand] {
        var result: [SlashCommand] = []
        for command in commands {
            var sanitized = command
            sanitized.name = normalizedNameForInput(command.name)
            let key = commandKey(sanitized.name)
            guard !sanitized.name.isEmpty, !defaultCommandKeys.contains(key) else { continue }
            result.removeAll { commandKey($0.name) == key }
            result.append(sanitized)
        }
        return result
    }

    private static func sanitizedModifiedDefaults(from commands: [String: SlashCommand]) -> [String: SlashCommand] {
        let byKey = Dictionary(commands.map { (commandKey($0.key), $0.value) }, uniquingKeysWith: { _, last in last })
        var result: [String: SlashCommand] = [:]
        for defaultCommand in defaultCommands {
            guard var modified = byKey[commandKey(defaultCommand.name)] else { continue }
            modified.name = defaultCommand.name
            if modified != defaultCommand {
                result[defaultCommand.name] = modified
            }
        }
        return result
    }

    private static func normalizedStore(_ store: CustomCommandStore) -> CustomCommandStore {
        var normalized = store
        normalized.customCommands = sanitizedCustomCommands(from: store.customCommands)
        normalized.modifiedDefaults = sanitizedModifiedDefaults(from: store.modifiedDefaults)
        normalized.hiddenDefaults.removeAll()

        let customKeys = Set(normalized.customCommands.map { commandKey($0.name) })
        let validKeys = defaultCommandKeys.union(customKeys)
        normalized.disabledCommands = Set(normalized.disabledCommands.map(commandKey).filter { validKeys.contains($0) })
        return normalized
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Clarc")
            .appendingPathComponent("custom_commands.json")
    }

    private static func loadStore() -> CustomCommandStore {
        let url = storeURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CustomCommandStore.self, from: data)
        else { return CustomCommandStore() }
        return normalizedStore(decoded)
    }

    static func saveStore() {
        do {
            store = normalizedStore(store)
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
        let custom = sanitizedCustomCommands(from: [cmd])
        guard let cmd = custom.first else { return }
        store.customCommands.removeAll { namesMatch($0.name, cmd.name) }
        store.customCommands.append(cmd)
        invalidateCache()
        saveStore()
    }

    static func replaceCustomCommand(name: String, with cmd: SlashCommand) {
        let custom = sanitizedCustomCommands(from: [cmd])
        guard let cmd = custom.first else { return }
        store.customCommands.removeAll { namesMatch($0.name, name) || namesMatch($0.name, cmd.name) }
        store.customCommands.append(cmd)
        invalidateCache()
        saveStore()
    }

    static func removeCustomCommand(name: String) {
        store.customCommands.removeAll { namesMatch($0.name, name) }
        store.disabledCommands.remove(commandKey(name))
        invalidateCache()
        saveStore()
    }

    static func modifyDefault(originalName: String, modified: SlashCommand) {
        guard let original = originalDefault(name: originalName) else { return }
        var modified = modified
        modified.name = original.name
        if modified == original {
            store.modifiedDefaults.removeValue(forKey: original.name)
        } else {
            store.modifiedDefaults[original.name] = modified
        }
        invalidateCache()
        saveStore()
    }

    static func hideDefault(name: String) {
        // Default commands cannot be deleted or hidden. Use setEnabled for visibility in the picker.
    }

    static func resetAllDefaults() {
        store.hiddenDefaults.removeAll()
        store.modifiedDefaults.removeAll()
        invalidateCache()
        saveStore()
    }

    static func isDefault(name: String) -> Bool {
        defaultCommandKeys.contains(commandKey(name))
    }

    static func isHidden(name: String) -> Bool {
        false
    }

    static func isModified(name: String) -> Bool {
        guard let original = originalDefault(name: name) else { return false }
        return store.modifiedDefaults[original.name] != nil
    }

    static func isEnabled(name: String) -> Bool {
        !store.disabledCommands.contains(commandKey(name))
    }

    static func setEnabled(name: String, _ enabled: Bool) {
        let key = commandKey(name)
        if enabled {
            store.disabledCommands.remove(key)
        } else {
            store.disabledCommands.insert(key)
        }
        invalidateCache()
        saveStore()
    }

    static func originalDefault(name: String) -> SlashCommand? {
        defaultCommands.first { namesMatch($0.name, name) }
    }

    static func customCommandExists(name: String, excluding excludedName: String? = nil) -> Bool {
        store.customCommands.contains { command in
            guard namesMatch(command.name, name) else { return false }
            if let excludedName, namesMatch(command.name, excludedName) { return false }
            return true
        }
    }

    static var customCommandCount: Int {
        sanitizedCustomCommands(from: store.customCommands).count
    }

    // MARK: - Export / Import

    static func exportCommands() -> Data? {
        let customOnly = sanitizedCustomCommands(from: store.customCommands)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(customOnly),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return Data((exportCommentHeader() + json + "\n").utf8)
    }

    static func importCommands(from data: Data) -> Bool {
        let jsonData = data.removingJSONComments()
        guard let imported = try? JSONDecoder().decode([SlashCommand].self, from: jsonData) else {
            return false
        }
        var newStore = CustomCommandStore()
        newStore.customCommands = sanitizedCustomCommands(from: imported)

        let customKeys = Set(newStore.customCommands.map { commandKey($0.name) })
        let validKeys = defaultCommandKeys.union(customKeys)
        newStore.disabledCommands = Set(store.disabledCommands.map(commandKey).filter { validKeys.contains($0) })

        store = normalizedStore(newStore)
        invalidateCache()
        saveStore()
        return true
    }

    private static func exportCommentHeader() -> String {
        let commentLines = [
            String(localized: "Clarc slash command export file.", bundle: .module),
            String(localized: "Usage:", bundle: .module),
            String(localized: "Edit the array below to add, remove, or change custom slash commands.", bundle: .module),
            String(localized: "The leading slash is optional while editing names; Clarc saves names without it.", bundle: .module),
            String(localized: "Built-in command names are ignored on import and are never exported.", bundle: .module),
            String(localized: "Each custom command supports these properties:", bundle: .module),
            String(localized: "name: command name without the leading slash.", bundle: .module),
            String(localized: "description: short text shown in the command picker.", bundle: .module),
            String(localized: "detailDescription: optional longer text shown in command details. Use null or omit it when empty.", bundle: .module),
            String(localized: "acceptsInput: true lets users type additional text after the command.", bundle: .module),
            String(localized: "isInteractive: true runs the command in the interactive terminal.", bundle: .module),
            "",
            String(localized: "All properties example:", bundle: .module),
            "{",
            "  \"acceptsInput\": true,",
            "  \"description\": \"\(String(localized: "Short description shown in the command picker", bundle: .module))\",",
            "  \"detailDescription\": \"\(String(localized: "Optional longer description shown in command details", bundle: .module))\",",
            "  \"isInteractive\": false,",
            "  \"name\": \"example-command\"",
            "}",
            "",
        ]
        return commentLines.map { line in
            line.isEmpty ? "//" : "// \(line)"
        }.joined(separator: "\n") + "\n"
    }

    static var enabledCommands: [SlashCommand] {
        commands.filter { isEnabled(name: $0.name) }
    }

    static func filtered(by query: String) -> [SlashCommand] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty || q == "/" { return enabledCommands }
        let search = q.hasPrefix("/") ? String(q.dropFirst()) : q

        var nameMatches: [SlashCommand] = []
        var descriptionMatches: [SlashCommand] = []
        for cmd in enabledCommands {
            if cmd.name.lowercased().contains(search)
                || cmd.aliases.contains(where: { $0.lowercased().contains(search) }) {
                nameMatches.append(cmd)
            } else if cmd.description.lowercased().contains(search) {
                descriptionMatches.append(cmd)
            }
        }
        return nameMatches + descriptionMatches
    }
}

extension Data {
    func removingJSONComments() -> Data {
        let bytes = Array(self)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)

        var index = 0
        var isInString = false
        var isEscaped = false
        var isInLineComment = false
        var isInBlockComment = false

        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : nil

            if isInLineComment {
                if byte == 0x0A || byte == 0x0D {
                    isInLineComment = false
                    output.append(byte)
                }
                index += 1
                continue
            }

            if isInBlockComment {
                if byte == 0x2A, next == 0x2F {
                    isInBlockComment = false
                    index += 2
                } else {
                    if byte == 0x0A || byte == 0x0D {
                        output.append(byte)
                    }
                    index += 1
                }
                continue
            }

            if isInString {
                output.append(byte)
                if isEscaped {
                    isEscaped = false
                } else if byte == 0x5C {
                    isEscaped = true
                } else if byte == 0x22 {
                    isInString = false
                }
                index += 1
                continue
            }

            if byte == 0x22 {
                isInString = true
                output.append(byte)
                index += 1
            } else if byte == 0x2F, next == 0x2F {
                isInLineComment = true
                index += 2
            } else if byte == 0x2F, next == 0x2A {
                isInBlockComment = true
                index += 2
            } else {
                output.append(byte)
                index += 1
            }
        }

        return Data(output)
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
                        .font(.system(size: ClaudeTheme.size(10)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text("Slash Commands", bundle: .module)
                        .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Spacer()
                    Text("\(filtered.count)")
                        .font(.system(size: ClaudeTheme.size(10)))
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
                                .font(.system(size: ClaudeTheme.size(13), weight: .semibold, design: .monospaced))
                                .foregroundStyle(isSelected ? ClaudeTheme.accent : ClaudeTheme.textPrimary)

                            if cmd.acceptsInput {
                                Text("accepts input", bundle: .module)
                                    .font(.system(size: ClaudeTheme.size(9)))
                                    .foregroundStyle(ClaudeTheme.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(ClaudeTheme.surfaceSecondary, in: Capsule())
                            }
                        }

                        Text(LocalizedStringKey(cmd.description), bundle: .module)
                            .font(.system(size: ClaudeTheme.size(11)))
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
                        .font(.system(size: ClaudeTheme.size(13)))
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
                        .font(.system(size: ClaudeTheme.size(16), weight: .bold, design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)

                    Text(LocalizedStringKey(command.description), bundle: .module)
                        .font(.system(size: ClaudeTheme.size(13)))
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
                        .font(.system(size: ClaudeTheme.size(13)))
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
                .font(.system(size: ClaudeTheme.size(14)))
                .foregroundStyle(ClaudeTheme.textSecondary)
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .help("Commands")
        .popover(isPresented: $showUsagePopover, arrowEdge: .top) { UsagePopoverView() }
        .sheet(isPresented: $showCommandManager) {
            SlashCommandManagerView()
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
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))
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
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: ClaudeTheme.size(12)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            Text(value)
                .font(.system(size: ClaudeTheme.size(12), weight: .medium, design: .monospaced))
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
                    .font(.system(size: ClaudeTheme.size(10)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Text("File Search", bundle: .module)
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: ClaudeTheme.size(10)))
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
                    .font(.system(size: ClaudeTheme.size(13)))
                    .foregroundStyle(isSelected ? ClaudeTheme.accent : entry.iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                        .foregroundStyle(isSelected ? ClaudeTheme.accent : ClaudeTheme.textPrimary)

                    if !entry.directory.isEmpty {
                        Text(entry.directory)
                            .font(.system(size: ClaudeTheme.size(11)))
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
    private nonisolated static let ignoredNames: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData",
        "node_modules", ".DS_Store", "Pods",
        "xcuserdata", ".xcodeproj", ".xcworkspace",
    ]

    // File list cache keyed by project path. Populated once per project on first use
    // or proactively via prefetch(projectPath:). Filtering against the cached list is
    // cheap (in-memory), so typing after the first @ character is fast.
    private static var fileListCache: [String: [AtFileEntry]] = [:]
    private static var prefetchingPaths: Set<String> = []

    /// Pre-warms the file cache for a project in the background.
    /// Call when a project is selected so the cache is ready when the user types @.
    static func prefetch(projectPath: String) {
        guard fileListCache[projectPath] == nil, !prefetchingPaths.contains(projectPath) else { return }
        prefetchingPaths.insert(projectPath)
        Task {
            let files = await Task.detached(priority: .utility) {
                AtFileSearch.collectFiles(at: projectPath, basePath: projectPath, maxDepth: 6)
            }.value
            fileListCache[projectPath] = files
            prefetchingPaths.remove(projectPath)
        }
    }

    /// Invalidates the cached file list for a project (e.g. after file-tree changes).
    static func invalidate(for projectPath: String) {
        fileListCache.removeValue(forKey: projectPath)
    }

    static func search(query: String, projectPath: String, maxResults: Int = 20) -> [AtFileEntry] {
        // Use the cached file list; fall back to a synchronous scan only if the
        // prefetch hasn't finished yet (should be rare after the first project open).
        let allFiles: [AtFileEntry]
        if let cached = fileListCache[projectPath] {
            allFiles = cached
        } else {
            allFiles = collectFiles(at: projectPath, basePath: projectPath, maxDepth: 6)
            fileListCache[projectPath] = allFiles
        }

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

    private nonisolated static func collectFiles(
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
