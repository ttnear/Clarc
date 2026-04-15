import SwiftUI

struct UserManualView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: ManualTopic = .overview

    var body: some View {
        NavigationSplitView {
            topicList
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            ScrollView {
                topicDetail(selectedTopic)
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(12)
            }
        }
        .frame(width: 900, height: 680)
    }

    // MARK: - Topic List

    private var topicList: some View {
        List(ManualTopic.allCases, selection: $selectedTopic) { topic in
            Label(LocalizedStringKey(topic.title), systemImage: topic.icon)
                .tag(topic)
        }
        .listStyle(.sidebar)
        .navigationTitle("User Guide")
    }

    // MARK: - Topic Detail

    @ViewBuilder
    private func topicDetail(_ topic: ManualTopic) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: topic.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                Text(LocalizedStringKey(topic.title))
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Divider()

            ForEach(Array(topic.sections.enumerated()), id: \.offset) { _, section in
                sectionView(section)
            }
        }
    }

    private func sectionView(_ section: ManualSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = section.title {
                Text(LocalizedStringKey(title))
                    .font(.headline)
            }

            Text(LocalizedStringKey(section.body))
                .font(.body)
                .foregroundStyle(.secondary)

            if !section.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(section.items, id: \.key) { item in
                        ManualKeyValueRow(key: item.key, value: item.value, symbolName: item.symbolName, symbolColor: item.symbolColor)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let note = section.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                    Text(LocalizedStringKey(note))
                        .font(.callout)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
                )
            }
        }
    }
}

// MARK: - Key-Value Row

private struct ManualKeyValueRow: View {
    let key: String
    let value: String
    var symbolName: String? = nil
    var symbolColor: Color? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(symbolColor ?? .primary)
                    .frame(width: 28, height: 20)
            } else {
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
            }
            Text(LocalizedStringKey(value))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Data Models

struct ManualSection {
    let title: String?
    let body: String
    let items: [KeyValueItem]
    let note: String?

    init(title: String? = nil, body: String = "", items: [KeyValueItem] = [], note: String? = nil) {
        self.title = title
        self.body = body
        self.items = items
        self.note = note
    }
}

struct KeyValueItem {
    let key: String
    let value: String
    var symbolName: String? = nil
    var symbolColor: Color? = nil
}

// MARK: - Topics

enum ManualTopic: String, CaseIterable, Identifiable {
    case overview
    case projects
    case chat
    case shortcuts
    case slashCommands
    case attachments
    case customShortcuts
    case inspectorPanel
    case github
    case marketplace
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:        "About Clarc"
        case .projects:        "Project Management"
        case .chat:            "Chat Basics"
        case .shortcuts:       "Keyboard Shortcuts"
        case .slashCommands:   "Slash Commands"
        case .attachments:     "File & Image Attachments"
        case .customShortcuts: "Shortcut Buttons"
        case .inspectorPanel:  "Inspector Panel"
        case .github:          "GitHub Integration"
        case .marketplace:     "Skill Marketplace"
        case .permissions:     "Permission Requests"
        }
    }

    var icon: String {
        switch self {
        case .overview:        "sparkle"
        case .projects:        "folder.fill"
        case .chat:            "bubble.left.and.bubble.right"
        case .shortcuts:       "keyboard"
        case .slashCommands:   "terminal.fill"
        case .attachments:     "paperclip"
        case .customShortcuts: "bolt.fill"
        case .inspectorPanel:  "sidebar.trailing"
        case .github:          "building.columns"
        case .marketplace:     "brain.head.profile"
        case .permissions:     "checkmark.shield"
        }
    }

    var sections: [ManualSection] {
        switch self {
        case .overview:
            [
                ManualSection(
                    title: "What is Clarc?",
                    body: "A native macOS desktop client for the Claude Code CLI. Use all Claude Code features via a polished GUI without needing a terminal."
                ),
                ManualSection(
                    title: "Main Layout",
                    body: "The left sidebar has History and Files tabs. Project tabs appear at the top of the chat area — click to switch projects. The right inspector panel contains the Terminal and Memo tabs.",
                    note: "Chat is disabled when no project is selected."
                ),
                ManualSection(
                    title: "Top Toolbar",
                    body: "The toolbar contains: New Chat, Manage Slash Commands, Manage Shortcut Buttons, Skip Permissions toggle, Model picker, Inspector panel toggle, Settings, and the GitHub integration button."
                ),
            ]

        case .projects:
            [
                ManualSection(
                    title: "Adding a Project",
                    body: "Click the + button at the top of the sidebar or drag a folder from Finder. Claude Code uses that folder as its working directory."
                ),
                ManualSection(
                    title: "Project Tabs",
                    body: "Project tabs appear at the top of the chat area. Click a tab to switch projects. You can switch even while Claude is streaming — the active stream continues in the background."
                ),
                ManualSection(
                    title: "Dedicated Project Window",
                    body: "Double-click a project tab to open it in its own independent window. Each window manages its own sessions independently, allowing you to work on multiple projects at once.",
                    note: "In a dedicated project window, only the project name is shown — there are no project tabs."
                ),
                ManualSection(
                    title: "Sidebar Tabs",
                    body: "History tab: shows previous conversations\nFiles tab: browse the project file tree",
                    items: [
                        KeyValueItem(key: "⌘1", value: "Go to History tab"),
                        KeyValueItem(key: "⌘2", value: "Go to Files tab"),
                        KeyValueItem(key: "⌘F", value: "Files tab + activate search"),
                    ]
                ),
                ManualSection(
                    title: "History Management",
                    body: "Right-click a session in the History tab for context menu options.",
                    items: [
                        KeyValueItem(key: "pin", value: "Pin / Unpin — pinned sessions stay at the top of the list", symbolName: "pin.fill", symbolColor: .orange),
                        KeyValueItem(key: "rename", value: "Rename — change the session title", symbolName: "pencil", symbolColor: .secondary),
                        KeyValueItem(key: "delete", value: "Delete — remove the session", symbolName: "trash", symbolColor: .red),
                    ],
                    note: "Use the trash icon in the History header to delete all sessions at once."
                ),
                ManualSection(
                    title: "File Inspector",
                    body: "Click any file in the Files tab to preview it with syntax highlighting. Press the pencil button to enter edit mode and modify the file directly.",
                    items: [
                        KeyValueItem(key: "⌘S", value: "Save file changes"),
                        KeyValueItem(key: "Escape", value: "Exit edit mode"),
                    ],
                    note: "Files larger than 1 MB cannot be previewed."
                ),
                ManualSection(
                    title: "Git Status",
                    body: "The number of changed files is shown at the bottom of the sidebar."
                ),
            ]

        case .chat:
            [
                ManualSection(
                    title: "Sending Messages",
                    body: "Type a message in the input field and press Return or the send button.",
                    items: [
                        KeyValueItem(key: "Return", value: "Send message"),
                        KeyValueItem(key: "⌘Return", value: "Send message (alternative)"),
                        KeyValueItem(key: "⇧Return", value: "Insert line break"),
                        KeyValueItem(key: "Escape", value: "Stop streaming (cancel response generation)"),
                    ]
                ),
                ManualSection(
                    title: "Message Queue",
                    body: "You can send messages even while Claude is responding. New messages are queued automatically and sent once the current response finishes. Queued messages appear as a badge above the input field — click the × on each item to remove it from the queue."
                ),
                ManualSection(
                    title: "Recalling Previous Messages",
                    body: "When the input field is empty, use ↑/↓ to navigate your message history.",
                    items: [
                        KeyValueItem(key: "↑", value: "Recall previous message"),
                        KeyValueItem(key: "↓", value: "Next message / clear input"),
                    ]
                ),
                ManualSection(
                    title: "Changing the Model",
                    body: "Use the model dropdown at the top of the chat area to switch Claude models."
                ),
                ManualSection(
                    title: "Skip Permissions",
                    body: "Toggle the shield icon at the top of the chat to auto-approve all permission prompts. Use with caution.",
                    items: [
                        KeyValueItem(key: "bolt.shield", value: "Normal mode — permission prompts appear as usual", symbolName: "bolt.shield", symbolColor: .green),
                        KeyValueItem(key: "bolt.shield.fill", value: "Skip mode — all permissions auto-approved", symbolName: "bolt.shield.fill", symbolColor: .red),
                    ],
                    note: "Only enable Skip Permissions on projects you fully trust."
                ),
            ]

        case .shortcuts:
            [
                ManualSection(
                    title: "Global Shortcuts",
                    body: "",
                    items: [
                        KeyValueItem(key: "⌘N", value: "Start new chat"),
                        KeyValueItem(key: "⌘W", value: "Close current window"),
                        KeyValueItem(key: "⌘1", value: "Sidebar — History tab"),
                        KeyValueItem(key: "⌘2", value: "Sidebar — Files tab"),
                        KeyValueItem(key: "⌘F", value: "Sidebar — Files tab + search"),
                        KeyValueItem(key: "Double-click", value: "Project tab — open in dedicated window"),
                    ]
                ),
                ManualSection(
                    title: "Input Field Shortcuts",
                    body: "",
                    items: [
                        KeyValueItem(key: "Return", value: "Send message"),
                        KeyValueItem(key: "⌘Return", value: "Send message (alternative)"),
                        KeyValueItem(key: "⇧Return", value: "Line break"),
                        KeyValueItem(key: "Escape", value: "Close popup / stop streaming"),
                        KeyValueItem(key: "↑ / ↓", value: "Select popup item or navigate message history"),
                        KeyValueItem(key: "Tab", value: "Autocomplete slash command / @ file"),
                    ]
                ),
                ManualSection(
                    title: "Slash Command Popup",
                    body: "",
                    items: [
                        KeyValueItem(key: "↑ / ↓", value: "Select item"),
                        KeyValueItem(key: "Return", value: "Execute command"),
                        KeyValueItem(key: "⌘Return", value: "View command details"),
                        KeyValueItem(key: "Tab", value: "Autocomplete command"),
                        KeyValueItem(key: "Escape", value: "Close popup"),
                    ]
                ),
                ManualSection(
                    title: "@ File Popup",
                    body: "",
                    items: [
                        KeyValueItem(key: "↑ / ↓", value: "Select item"),
                        KeyValueItem(key: "Return / Tab", value: "Insert file path"),
                        KeyValueItem(key: "Escape", value: "Close popup"),
                    ]
                ),
            ]

        case .slashCommands:
            [
                ManualSection(
                    title: "What are Slash Commands?",
                    body: "Type / in the input field to open a popup list of available commands. Slash commands let you quickly trigger Claude Code CLI operations without typing them manually."
                ),
                ManualSection(
                    title: "How to Use",
                    body: "Type / to open the popup, then continue typing to filter results. Use ↑/↓ to navigate.",
                    items: [
                        KeyValueItem(key: "Return", value: "Execute selected command"),
                        KeyValueItem(key: "⌘Return", value: "View command details"),
                        KeyValueItem(key: "Tab", value: "Autocomplete command"),
                        KeyValueItem(key: "Escape", value: "Close popup"),
                    ]
                ),
                ManualSection(
                    title: "Interactive Commands",
                    body: "Some commands (such as /config, /permissions, /model) open in a full interactive terminal popup sheet, where you can use the interactive CLI interface. The popup closes automatically when the command finishes."
                ),
                ManualSection(
                    title: "Managing Commands",
                    body: "Click the / button in the toolbar, or open Settings → Slash Commands to add, edit, hide, or disable commands. Custom commands and changes to built-in commands are saved per project.",
                    note: "JSON import/export is supported for backing up or sharing your command set."
                ),
            ]

        case .attachments:
            [
                ManualSection(
                    title: "Attaching Files",
                    body: "Click the clip icon to the left of the input field, or drag and drop files onto the input field. When dragging, the input field border highlights in the accent color to show the drop zone."
                ),
                ManualSection(
                    title: "Clipboard Detection",
                    body: "Pasting (⌘V) is smart — Clarc detects what's in the clipboard and handles it automatically.",
                    items: [
                        KeyValueItem(key: "image", value: "Image data (PNG/TIFF) → attached as an image", symbolName: "photo", symbolColor: .blue),
                        KeyValueItem(key: "file", value: "File path → attached as a file", symbolName: "doc", symbolColor: .secondary),
                        KeyValueItem(key: "url", value: "URL → attached as a URL reference", symbolName: "link", symbolColor: .accentColor),
                        KeyValueItem(key: "text", value: "Long text (>2 KB) → converted to a text attachment", symbolName: "text.alignleft", symbolColor: .secondary),
                    ],
                    note: "Screenshots can be pasted directly — they are automatically attached as images."
                ),
                ManualSection(
                    title: "@ File References",
                    body: "Type @ in the input field to open a project file search popup. Files are filtered in real time as you type.",
                    items: [
                        KeyValueItem(key: "↑ / ↓", value: "Select item"),
                        KeyValueItem(key: "Return / Tab", value: "Insert file path into message"),
                        KeyValueItem(key: "Escape", value: "Close popup"),
                    ]
                ),
            ]

        case .customShortcuts:
            [
                ManualSection(
                    title: "What are Shortcut Buttons?",
                    body: "Quick-access buttons shown at the top of the chat area. Run frequently used messages or shell commands with a single click."
                ),
                ManualSection(
                    title: "Adding a Shortcut",
                    body: "Click the ⚡ button in the toolbar to open the Shortcut Manager, or press the + button on the right side of the shortcut bar. You can set a name, message/command, icon, and color."
                ),
                ManualSection(
                    title: "Terminal Command Mode",
                    body: "Enable the \"Run as terminal command\" option to execute the shortcut as a shell command in the inspector terminal instead of sending it as a chat message. The project directory is used as the working directory."
                ),
                ManualSection(
                    title: "Managing Shortcuts",
                    body: "Open Settings → Shortcuts to reorder, edit, or delete shortcuts. Shortcut configurations are saved per project.",
                    note: "JSON import/export is supported for backing up or sharing your shortcut set."
                ),
            ]

        case .inspectorPanel:
            [
                ManualSection(
                    title: "Opening the Inspector Panel",
                    body: "Click the sidebar.trailing (⊟) button at the top right of the toolbar to toggle the inspector panel. The panel docks to the right side of the window and contains two tabs: Terminal and Memo."
                ),
                ManualSection(
                    title: "Terminal Tab",
                    body: "An embedded zsh terminal that opens at the current project's directory. Use it to run shell commands, inspect files, or manage git — all without leaving the app."
                ),
                ManualSection(
                    title: "Memo Tab",
                    body: "A per-project rich text memo editor. Notes are auto-saved after a short pause and persist across sessions. Markdown formatting is supported.",
                    items: [
                        KeyValueItem(key: "#", value: "Heading levels (# / ## / ###)"),
                        KeyValueItem(key: "**text**", value: "Bold"),
                        KeyValueItem(key: "*text*", value: "Italic"),
                        KeyValueItem(key: "`code`", value: "Inline code"),
                        KeyValueItem(key: "~~text~~", value: "Strikethrough"),
                        KeyValueItem(key: "- item", value: "Unordered list (auto-continues on Return)"),
                    ]
                ),
                ManualSection(
                    title: "Interactive Terminal Popup",
                    body: "Some slash commands (such as /config, /permissions, /model) open in a separate interactive terminal sheet. The popup runs the command automatically and closes when it exits.",
                    note: "The exit code is shown at the bottom — \"exit 0\" means the command completed successfully."
                ),
            ]

        case .github:
            [
                ManualSection(
                    title: "GitHub Integration",
                    body: "Click the GitHub Mark button at the top of the sidebar to open the GitHub panel. After connecting your GitHub account, your repositories are listed and can be added to Clarc with one click."
                ),
                ManualSection(
                    title: "Adding a Repository",
                    body: "Search for a repository by name, then click Add. Clarc clones it automatically and opens it as a new project.",
                    items: [
                        KeyValueItem(key: "lock", value: "Private repository", symbolName: "lock", symbolColor: .secondary),
                        KeyValueItem(key: "globe", value: "Public repository", symbolName: "globe", symbolColor: .secondary),
                        KeyValueItem(key: "checkmark", value: "Already added to Clarc", symbolName: "checkmark.circle.fill", symbolColor: .green),
                    ]
                ),
            ]

        case .marketplace:
            [
                ManualSection(
                    title: "Skill Marketplace",
                    body: "Click the brain icon (🧠) in the toolbar to browse the MCP plugin catalog published on Anthropic's GitHub. Plugins can be filtered by category or searched by name, description, or author."
                ),
                ManualSection(
                    title: "Installing Plugins",
                    body: "Click a plugin to view its details, then press Install. An interactive terminal popup opens and runs the install command automatically.",
                    items: [
                        KeyValueItem(key: "clock", value: "Not installed", symbolName: "clock", symbolColor: .secondary),
                        KeyValueItem(key: "arrow.down", value: "Installing…", symbolName: "arrow.down.circle", symbolColor: .accentColor),
                        KeyValueItem(key: "checkmark", value: "Installed", symbolName: "checkmark.circle.fill", symbolColor: .green),
                    ],
                    note: "The catalog refreshes automatically every 5 minutes."
                ),
            ]

        case .permissions:
            [
                ManualSection(
                    title: "What are Permission Requests?",
                    body: "Before Claude edits files or runs commands, it pauses and asks for your approval. A modal appears showing the tool name and its arguments."
                ),
                ManualSection(
                    title: "Approval Options",
                    body: "Each permission request offers three choices.",
                    items: [
                        KeyValueItem(key: "Allow", value: "Approve this single action", symbolName: "checkmark.circle.fill", symbolColor: .green),
                        KeyValueItem(key: "Allow Session", value: "Approve all future requests of this type for the current session", symbolName: "checkmark.shield.fill", symbolColor: .blue),
                        KeyValueItem(key: "Deny", value: "Reject the action", symbolName: "xmark.circle.fill", symbolColor: .red),
                    ],
                    note: "If no action is taken, the request is automatically denied after 5 minutes. Press Return to Allow, or Escape to Deny."
                ),
                ManualSection(
                    title: "Skip Permissions Mode",
                    body: "Toggle the shield icon at the top of the chat to auto-approve all permission requests. This speeds up tasks but also auto-executes potentially dangerous operations — use with caution.",
                    items: [
                        KeyValueItem(key: "bolt.shield", value: "Normal mode — permission prompts appear as usual", symbolName: "bolt.shield", symbolColor: .green),
                        KeyValueItem(key: "bolt.shield.fill", value: "Skip mode — all permissions auto-approved", symbolName: "bolt.shield.fill", symbolColor: .red),
                    ],
                    note: "Only enable Skip Permissions on projects you fully trust."
                ),
            ]
        }
    }
}

#Preview {
    UserManualView()
}
