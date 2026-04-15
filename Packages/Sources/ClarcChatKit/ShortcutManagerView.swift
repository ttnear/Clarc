import SwiftUI
import UniformTypeIdentifiers
import ClarcCore

// MARK: - Shortcut Manager View

public struct ShortcutManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editingShortcut: ChatShortcut?
    @State private var isAddingNew = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    @State private var importSuccess = false
    @State private var shortcutList: [ChatShortcut] = ChatShortcutRegistry.currentShortcuts

    public let projectName: String
    public var isEmbedded: Bool = false

    public init(projectName: String, isEmbedded: Bool = false) {
        self.projectName = projectName
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isEmbedded {
                embeddedToolbar
            } else {
                header
            }
            Divider()

            if shortcutList.isEmpty {
                emptyState
            } else {
                shortcutListView
            }
        }
        .focusable(false)
        .sheet(item: $editingShortcut) { shortcut in
            ShortcutEditView(
                shortcut: shortcut,
                onSave: { updated in
                    ChatShortcutRegistry.update(id: shortcut.id, with: updated)
                    refreshList()
                }
            )
        }
        .sheet(isPresented: $isAddingNew) {
            ShortcutEditView(
                shortcut: nil,
                onSave: { newShortcut in
                    ChatShortcutRegistry.add(newShortcut)
                    refreshList()
                }
            )
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
                Text("Shortcut Manager", bundle: .module)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text(projectName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("· \(shortcutList.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button { exportShortcuts() } label: {
                Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Export shortcuts to a JSON file")

            Button { importShortcuts() } label: {
                Label(String(localized: "Import", bundle: .module), systemImage: "square.and.arrow.down")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Import shortcuts from a JSON file")

            Button {
                isAddingNew = true
            } label: {
                Label(String(localized: "New Shortcut", bundle: .module), systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
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
            Text(String(format: String(localized: "%lld shortcuts", bundle: .module), shortcutList.count))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button { exportShortcuts() } label: {
                Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Button { importShortcuts() } label: {
                Label(String(localized: "Import", bundle: .module), systemImage: "square.and.arrow.down")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Button {
                isAddingNew = true
            } label: {
                Label(String(localized: "New Shortcut", bundle: .module), systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Shortcut List

    private var shortcutListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shortcutList) { shortcut in
                    shortcutRow(shortcut)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func shortcutRow(_ shortcut: ChatShortcut) -> some View {
        Button {
            editingShortcut = shortcut
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(shortcut.name)
                            .font(.system(size: 13, weight: .semibold))
                        if shortcut.isTerminalCommand {
                            Text("terminal", bundle: .module)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                        }
                    }

                    Text(shortcut.message)
                        .font(.system(size: 12, design: shortcut.isTerminalCommand ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    ChatShortcutRegistry.remove(id: shortcut.id)
                    refreshList()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete")

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bolt")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No shortcuts", bundle: .module)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Register frequently used messages as shortcuts", bundle: .module)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                isAddingNew = true
            } label: {
                Label(String(localized: "Add First Shortcut", bundle: .module), systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func refreshList() {
        shortcutList = ChatShortcutRegistry.currentShortcuts
    }

    private func exportShortcuts() {
        guard let data = ChatShortcutRegistry.exportShortcuts() else { return }
        let panel = NSSavePanel()
        panel.title = "Export Shortcuts"
        panel.nameFieldStringValue = "shortcuts.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func importShortcuts() {
        let panel = NSOpenPanel()
        panel.title = "Import Shortcuts"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async {
                if ChatShortcutRegistry.importShortcuts(from: data) {
                    refreshList()
                    importSuccess = true
                    importResultMessage = "Imported \(shortcutList.count) shortcuts."
                } else {
                    importSuccess = false
                    importResultMessage = "Invalid JSON format."
                }
                showImportResult = true
            }
        }
    }
}

// MARK: - Shortcut Edit View

struct ShortcutEditView: View {
    @Environment(\.dismiss) private var dismiss
    let shortcut: ChatShortcut?
    let onSave: (ChatShortcut) -> Void

    @State private var name: String = ""
    @State private var message: String = ""
    @State private var isTerminalCommand: Bool = false

    private var isEditing: Bool { shortcut != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Group {
                    if isEditing { Text("Edit Shortcut", bundle: .module) } else { Text("Add New Shortcut", bundle: .module) }
                }
                .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
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
                        TextField(String(localized: "Name shown on the button", bundle: .module), text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1))
                    }

                    // Message
                    fieldSection(isTerminalCommand ? LocalizedStringKey("Command") : LocalizedStringKey("Message")) {
                        TextEditor(text: $message)
                            .font(.system(size: 13, design: isTerminalCommand ? .monospaced : .default))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80, maxHeight: 150)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1))
                        Group {
                            if isTerminalCommand {
                                Text("This command will run in the terminal when the button is clicked", bundle: .module)
                            } else {
                                Text("This message will be sent when the button is clicked", bundle: .module)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    // Terminal command toggle
                    fieldSection("Execution Mode") {
                        Toggle(isOn: $isTerminalCommand) {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 12))
                                Text("Run as terminal command", bundle: .module)
                                    .font(.system(size: 13))
                            }
                        }
                        .toggleStyle(.switch)
                        Text("When enabled, the command runs in the terminal instead of chat", bundle: .module)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

}
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()

            // Bottom buttons
            HStack {
                Spacer()

                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                Button(isEditing ? LocalizedStringKey("Save") : LocalizedStringKey("Add")) {
                    let result = ChatShortcut(
                        id: shortcut?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        message: message.trimmingCharacters(in: .whitespaces),
                        isTerminalCommand: isTerminalCommand
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
        .frame(width: 480, height: 520)
        .focusable(false)
        .onAppear {
            if let s = shortcut {
                name = s.name
                message = s.message
                isTerminalCommand = s.isTerminalCommand
            }
        }
    }

    @ViewBuilder
    private func fieldSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
