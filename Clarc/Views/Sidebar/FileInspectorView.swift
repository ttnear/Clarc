import SwiftUI
import ClarcCore

/// Inspector panel for file preview with syntax highlighting
struct FileInspectorView: View {
    let filePath: String
    let fileName: String
    @State private var content: String?
    @State private var highlightedContent: AttributedString?
    @State private var lineCount = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isCopied = false
    @State private var isEditing = false
    @State private var editingContent = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    private var isDirty: Bool {
        isEditing && editingContent != (content ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if isEditing {
                editingView
            } else if let content {
                if fileExtension == "md" || fileExtension == "markdown" {
                    MarkdownPreviewView(content: content)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    codeContentView(content)
                }
            }
        }
        .background(ClaudeTheme.background)
        .background {
            // Cmd+S: Save
            Button("") { Task { await saveFile() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty || isSaving)
                .opacity(0)
                .allowsHitTesting(false)
            // ESC: Cancel editing if in edit mode, otherwise close the inspector
            Button("") {
                if isEditing {
                    isEditing = false
                    editingContent = content ?? ""
                } else {
                    windowState.inspectorFile = nil
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
        }
        .task(id: filePath) {
            isEditing = false
            editingContent = ""
            saveError = nil
            await loadFile()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: iconForExtension)
                .font(.system(size: ClaudeTheme.size(13)))
                .foregroundStyle(iconColorForExtension)

            Text(fileName)
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold, design: .monospaced))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(languageLabel)
                .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(ClaudeTheme.surfaceSecondary, in: Capsule())

            if content != nil {
                Button {
                    if !isEditing {
                        editingContent = content ?? ""
                    }
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle" : "pencil")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(isEditing ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Preview" : "Edit")
            }

            if let content, !isEditing {
                Button {
                    copyToClipboard(content, feedback: $isCopied)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(isCopied ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help(isCopied ? "Copied" : "Copy")
            }

            Button { windowState.inspectorFile = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(ClaudeTheme.surfaceSecondary, in: Circle())
            }
            .buttonStyle(.borderless)
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ClaudeTheme.surfacePrimary)
    }

    // MARK: - Content

    private func codeContentView(_ text: String) -> some View {
        let lineNumberWidth = max(String(lineCount).count * 8 + 12, 32)
        let highlighted = highlightedContent ?? AttributedString(text)

        return GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(0..<lineCount, id: \.self) { index in
                            Text("\(index + 1)")
                                .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                                .foregroundStyle(ClaudeTheme.textTertiary.opacity(0.6))
                                .frame(height: 19)
                        }
                    }
                    .frame(width: CGFloat(lineNumberWidth))
                    .padding(.top, 10)
                    .padding(.trailing, 6)
                    .background(ClaudeTheme.codeBackground.opacity(0.5))

                    Rectangle()
                        .fill(ClaudeTheme.border.opacity(0.5))
                        .frame(width: 1)

                    Text(highlighted)
                        .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.leading, 10)
                        .padding(.trailing, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .background(ClaudeTheme.codeBackground)
    }

    private var editingView: some View {
        VStack(spacing: 0) {
            if let error = saveError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: ClaudeTheme.size(11)))
                    Text(error)
                        .font(.system(size: ClaudeTheme.size(11)))
                }
                .foregroundStyle(ClaudeTheme.statusError)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ClaudeTheme.statusError.opacity(0.1))
                ClaudeThemeDivider()
            }
            TextEditor(text: $editingContent)
                .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(ClaudeTheme.codeBackground)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
                .onChange(of: editingContent) { _, newValue in
                    lineCount = 1 + newValue.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
                }
        }
        .background(ClaudeTheme.codeBackground)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("loading...")
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: ClaudeTheme.size(24)))
                .foregroundStyle(ClaudeTheme.statusWarning)
            Text(message)
                .font(.system(size: ClaudeTheme.size(13)))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - File Saving

    private func saveFile() async {
        isSaving = true
        saveError = nil
        let textToSave = editingContent
        let path = filePath
        do {
            try await Task.detached {
                let url = URL(fileURLWithPath: path)
                try textToSave.write(to: url, atomically: true, encoding: .utf8)
            }.value
            content = textToSave
            // Recalculate syntax highlighting after saving
            let ext = fileExtension
            let highlighted = await Task.detached {
                SyntaxHighlighter.highlight(textToSave, language: ext)
            }.value
            highlightedContent = highlighted
            isEditing = false
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
        isSaving = false
    }

    // MARK: - File Loading

    private func loadFile() async {
        isLoading = true
        content = nil
        highlightedContent = nil
        errorMessage = nil

        do {
            let data = try await Task.detached { [filePath] in
                let url = URL(fileURLWithPath: filePath)
                let attr = try FileManager.default.attributesOfItem(atPath: filePath)
                let size = (attr[.size] as? Int) ?? 0
                if size > 1_000_000 {
                    throw FileInspectorError.tooLarge
                }
                return try Data(contentsOf: url)
            }.value

            if let text = String(data: data, encoding: .utf8) {
                let ext = fileExtension
                let highlighted = await Task.detached {
                    SyntaxHighlighter.highlight(text, language: ext)
                }.value
                content = text
                highlightedContent = highlighted
                lineCount = text.components(separatedBy: "\n").count
            } else {
                errorMessage = "Binary file — preview not available"
            }
        } catch is FileInspectorError {
            errorMessage = "File is too large (>1MB)"
        } catch {
            errorMessage = "Read failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Helpers

    private var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    private var languageLabel: String {
        switch fileExtension {
        case "swift": "Swift"
        case "js": "JavaScript"
        case "jsx": "JSX"
        case "ts": "TypeScript"
        case "tsx": "TSX"
        case "json": "JSON"
        case "md": "Markdown"
        case "html": "HTML"
        case "css": "CSS"
        case "py": "Python"
        case "go": "Go"
        case "rs": "Rust"
        case "yaml", "yml": "YAML"
        case "sh", "bash", "zsh": "Shell"
        default: fileExtension.isEmpty ? "File" : fileExtension.uppercased()
        }
    }

    private var iconForExtension: String {
        FileNode(id: "", name: fileName, isDirectory: false, children: []).icon
    }

    private var iconColorForExtension: Color {
        FileNode(id: "", name: fileName, isDirectory: false, children: []).iconColor
    }
}

private enum FileInspectorError: Error {
    case tooLarge
}
