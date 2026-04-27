import SwiftUI
import UniformTypeIdentifiers
import ClarcCore

// MARK: - Slash Command Manager View

public struct SlashCommandManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var editingCommand: SlashCommand?
    @State private var isAddingNew = false
    @State private var showResetAlert = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    @State private var importSuccess = false
    @State private var commandList: [SlashCommand] = SlashCommandRegistry.commands

    public var isEmbedded: Bool = false

    public init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }

    private var filteredCommands: [SlashCommand] {
        if searchText.isEmpty { return commandList }
        let q = searchText.lowercased()
        return commandList.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isEmbedded {
                embeddedToolbar
            } else {
                header
            }
            Divider()
            searchBar

            if filteredCommands.isEmpty {
                emptyState
            } else {
                commandListView
            }
        }
        .focusable(false)
        .sheet(item: $editingCommand) { cmd in
            SlashCommandEditView(
                command: cmd,
                isDefault: SlashCommandRegistry.isDefault(name: cmd.name),
                onSave: { updated in
                    saveCommand(original: cmd, updated: updated)
                },
                onDelete: {
                    deleteCommand(cmd)
                }
            )
        }
        .sheet(isPresented: $isAddingNew) {
            SlashCommandEditView(
                command: nil,
                isDefault: false,
                onSave: { newCmd in
                    addCommand(newCmd)
                }
            )
        }
        .alert("Reset Default Commands", isPresented: $showResetAlert) {
            Button(String(localized: "Reset", bundle: .module), role: .destructive) { resetDefaults() }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text("All modified or deleted default commands will be restored to their original state.", bundle: .module)
        }
        .alert(importSuccess ? "Import Succeeded" : "Import Failed", isPresented: $showImportResult) {
            Button("OK") {}
        } message: {
            Text(importResultMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Slash Command Manager", bundle: .module)
                    .font(.system(size: ClaudeTheme.size(15), weight: .semibold))
                Text(String(format: String(localized: "%lld commands", bundle: .module), commandList.count))
                    .font(.system(size: ClaudeTheme.size(12)))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showResetAlert = true
            } label: {
                Label(String(localized: "Reset Defaults", bundle: .module), systemImage: "arrow.counterclockwise")
                    .font(.system(size: ClaudeTheme.size(12)))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Restore modified/deleted default commands to their original state")

            Button { exportCommands() } label: {
                Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up")
                    .font(.system(size: ClaudeTheme.size(12)))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Export custom commands to a JSON file")

            Button { importCommands() } label: {
                Label(String(localized: "Import", bundle: .module), systemImage: "square.and.arrow.down")
                    .font(.system(size: ClaudeTheme.size(12)))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Import commands from a JSON file")

            Button {
                isAddingNew = true
            } label: {
                Label(String(localized: "New Command", bundle: .module), systemImage: "plus")
                    .font(.system(size: ClaudeTheme.size(12), weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: ClaudeTheme.size(16)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Embedded Toolbar

    private var embeddedToolbar: some View {
        HStack(spacing: 12) {
            Text(String(format: String(localized: "%lld commands", bundle: .module), commandList.count))
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showResetAlert = true
            } label: {
                Label(String(localized: "Reset Defaults", bundle: .module), systemImage: "arrow.counterclockwise")
                    .font(.system(size: ClaudeTheme.size(12)))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Button { exportCommands() } label: {
                Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up")
                    .font(.system(size: ClaudeTheme.size(12)))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Button { importCommands() } label: {
                Label(String(localized: "Import", bundle: .module), systemImage: "square.and.arrow.down")
                    .font(.system(size: ClaudeTheme.size(12)))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Button {
                isAddingNew = true
            } label: {
                Label(String(localized: "New Command", bundle: .module), systemImage: "plus")
                    .font(.system(size: ClaudeTheme.size(12), weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search commands...", bundle: .module), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: ClaudeTheme.size(13)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Command List

    private var commandListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredCommands) { cmd in
                    commandRow(cmd)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func commandRow(_ cmd: SlashCommand) -> some View {
        let isEnabled = SlashCommandRegistry.isEnabled(name: cmd.name)
        let isDefaultCmd = SlashCommandRegistry.isDefault(name: cmd.name)

        return Button {
            editingCommand = cmd
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cmd.command)
                            .font(.system(size: ClaudeTheme.size(13), weight: .semibold, design: .monospaced))
                            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)

                        if isDefaultCmd {
                            Text("default", bundle: .module)
                                .font(.system(size: ClaudeTheme.size(9)))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                        }

                        if cmd.acceptsInput {
                            Text("accepts input", bundle: .module)
                                .font(.system(size: ClaudeTheme.size(9)))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                        }

                        if cmd.isInteractive {
                            Text("terminal", bundle: .module)
                                .font(.system(size: ClaudeTheme.size(9)))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.08), in: Capsule())
                        }
                    }

                    Text(LocalizedStringKey(cmd.description), bundle: .module)
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle(isOn: Binding(
                    get: { SlashCommandRegistry.isEnabled(name: cmd.name) },
                    set: { newValue in
                        SlashCommandRegistry.setEnabled(name: cmd.name, newValue)
                        refreshList()
                    }
                )) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
                .help(isEnabled ? "Disable" : "Enable")

                Image(systemName: "chevron.right")
                    .font(.system(size: ClaudeTheme.size(10)))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "command")
                .font(.system(size: ClaudeTheme.size(32)))
                .foregroundStyle(.secondary)
            Text("No results found", bundle: .module)
                .font(.system(size: ClaudeTheme.size(14), weight: .medium))
                .foregroundStyle(.secondary)
            Text("Try a different keyword", bundle: .module)
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func refreshList() {
        commandList = SlashCommandRegistry.commands
    }

    private func addCommand(_ cmd: SlashCommand) {
        SlashCommandRegistry.addCustomCommand(cmd)
        refreshList()
    }

    private func saveCommand(original: SlashCommand, updated: SlashCommand) {
        if SlashCommandRegistry.isDefault(name: original.name) {
            SlashCommandRegistry.modifyDefault(originalName: original.name, modified: updated)
        } else {
            SlashCommandRegistry.replaceCustomCommand(name: original.name, with: updated)
        }
        refreshList()
    }

    private func deleteCommand(_ cmd: SlashCommand) {
        if SlashCommandRegistry.isDefault(name: cmd.name) {
            SlashCommandRegistry.hideDefault(name: cmd.name)
        } else {
            SlashCommandRegistry.removeCustomCommand(name: cmd.name)
        }
        refreshList()
    }

    private func resetDefaults() {
        SlashCommandRegistry.resetAllDefaults()
        refreshList()
    }

    private func exportCommands() {
        guard let data = SlashCommandRegistry.exportCommands() else { return }
        let panel = NSSavePanel()
        panel.title = "Export Slash Commands"
        panel.nameFieldStringValue = "slash_commands.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func importCommands() {
        let panel = NSOpenPanel()
        panel.title = "Import Slash Commands"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async {
                if SlashCommandRegistry.importCommands(from: data) {
                    refreshList()
                    importSuccess = true
                    importResultMessage = "Imported \(commandList.count) commands."
                } else {
                    importSuccess = false
                    importResultMessage = "Invalid JSON format."
                }
                showImportResult = true
            }
        }
    }
}

// MARK: - Slash Command Edit View

struct SlashCommandEditView: View {
    @Environment(\.dismiss) private var dismiss
    let command: SlashCommand?
    let isDefault: Bool
    let onSave: (SlashCommand) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var desc: String = ""
    @State private var detailDesc: String = ""
    @State private var acceptsInput: Bool = false
    @State private var isInteractive: Bool = false

    private var isEditing: Bool { command != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !desc.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Group {
                    if isEditing { Text("Edit Command", bundle: .module) } else { Text("Add New Command", bundle: .module) }
                }
                    .font(.system(size: ClaudeTheme.size(15), weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: ClaudeTheme.size(16)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    fieldSection("Name") {
                        HStack(spacing: 4) {
                            Text("/")
                                .font(.system(size: ClaudeTheme.size(14), weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            TextField(String(localized: "Command name (e.g. my-command)", bundle: .module), text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: ClaudeTheme.size(14), design: .monospaced))
                                .disabled(isDefault)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isDefault ? Color(NSColor.controlBackgroundColor) : Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1))
                    }

                    // Description
                    fieldSection("Description") {
                        TextField(String(localized: "Short description", bundle: .module), text: $desc)
                            .textFieldStyle(.plain)
                            .font(.system(size: ClaudeTheme.size(14)))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1))
                    }

                    // Detail description
                    fieldSection("Detail Description (optional)") {
                        TextEditor(text: $detailDesc)
                            .font(.system(size: ClaudeTheme.size(13)))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80, maxHeight: 150)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1))
                    }

                    // Option toggles
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accepts Input", bundle: .module)
                                    .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                                Text("Allows additional text to be entered after the command", bundle: .module)
                                    .font(.system(size: ClaudeTheme.size(11)))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $acceptsInput)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Interactive (Terminal)", bundle: .module)
                                    .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                                Text("Commands requiring TUI will run in the inline terminal", bundle: .module)
                                    .font(.system(size: ClaudeTheme.size(11)))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $isInteractive)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()

            // Bottom buttons
            HStack {
                if isEditing && isDefault {
                    Button {
                        if let original = SlashCommandRegistry.originalDefault(name: command!.name) {
                            onSave(original)
                        }
                        dismiss()
                    } label: {
                        Text("Restore Default", bundle: .module)
                            .font(.system(size: ClaudeTheme.size(13)))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                if isEditing && !isDefault {
                    Button(role: .destructive) {
                        onDelete?()
                        dismiss()
                    } label: {
                        Text("Delete", bundle: .module)
                            .font(.system(size: ClaudeTheme.size(13)))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }

                Spacer()

                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                Button(isEditing ? String(localized: "Save", bundle: .module) : String(localized: "Add", bundle: .module)) {
                    let result = SlashCommand(
                        name: name.trimmingCharacters(in: .whitespaces),
                        description: desc.trimmingCharacters(in: .whitespaces),
                        detailDescription: detailDesc.trimmingCharacters(in: .whitespaces).isEmpty ? nil : detailDesc.trimmingCharacters(in: .whitespaces),
                        acceptsInput: acceptsInput,
                        isInteractive: isInteractive
                    )
                    onSave(result)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 520)
        .focusable(false)
        .onAppear {
            if let cmd = command {
                name = cmd.name
                desc = cmd.description
                detailDesc = cmd.detailDescription ?? ""
                acceptsInput = cmd.acceptsInput
                isInteractive = cmd.isInteractive
            }
        }
    }

    @ViewBuilder
    private func fieldSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title, bundle: .module)
                .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
