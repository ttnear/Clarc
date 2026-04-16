import SwiftUI
import UniformTypeIdentifiers
import ClarcCore

struct InputBarView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    @FocusState private var isInputFocused: Bool

    @State private var showFilePicker = false
    @State private var showSlashPopup = false
    @State private var slashSelectedIndex = 0
    @State private var slashDetailCommand: SlashCommand?
    @State private var textPreviewAttachment: Attachment?
    @State private var isDragOver = false
    @State private var isPasteInProgress = false
    @State private var lastPasteChangeCount = 0
    @State private var showAtFilePopup = false
    @State private var atFileSelectedIndex = 0
    @State private var historyIndex: Int = -1
    @State private var pendingSend = false
    @State private var textFieldLayoutID = 0

    var body: some View {
        VStack(spacing: 0) {
            if !windowState.attachments.isEmpty {
                attachmentPreviews
            }

            inputRow
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(ClaudeTheme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusPill))
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusPill)
                    .strokeBorder(ClaudeTheme.inputBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .sheet(item: $slashDetailCommand) { cmd in CommandDetailSheet(command: cmd) }
            .sheet(item: $textPreviewAttachment) { attachment in TextPreviewSheet(attachment: attachment) }
            .onDrop(of: [.fileURL, .image], isTargeted: $isDragOver) { providers in
                processItemProviders(providers)
                return true
            }
            .overlay {
                if isDragOver {
                    RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusPill)
                        .strokeBorder(ClaudeTheme.accent.opacity(0.6), lineWidth: 2, antialiased: true)
                        .background(ClaudeTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusPill))
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 4) {
                    if showSlashPopup && !slashFilteredCommands.isEmpty {
                        SlashCommandPopup(
                            query: slashQuery,
                            onSelect: { cmd in selectSlashCommand(cmd) },
                            selectedIndex: $slashSelectedIndex
                        )
                        .transition(.offset(y: 10).combined(with: .opacity))
                    }
                    if showAtFilePopup && !atFileFilteredEntries.isEmpty {
                        AtFilePopup(
                            entries: atFileFilteredEntries,
                            onSelect: { relativePath in selectAtFile(relativePath) },
                            selectedIndex: $atFileSelectedIndex
                        )
                        .transition(.offset(y: 10).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !windowState.messageQueue.isEmpty {
                    queuedMessagePreviews
                        .transition(.offset(y: 10).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .offset(y: -4)
            // Show popup above the input bar by mapping top guide to bottom
            .alignmentGuide(.top) { $0[.bottom] }
        }
        .onChange(of: windowState.requestInputFocus) { _, newValue in
            if newValue {
                isInputFocused = true
                windowState.requestInputFocus = false
            }
        }
        .onChange(of: windowState.currentSessionId) { _, _ in
            lastPasteChangeCount = NSPasteboard.general.changeCount
            historyIndex = -1
            // Defer to next MainActor iteration so the bridge observation has time to
            // update isStreaming to reflect the newly-active session before we check it.
            Task { @MainActor in
                if !chatBridge.isStreaming {
                    processNextQueued()
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                isInputFocused = true
            }
        }
        .onChange(of: chatBridge.isStreaming) { _, isStreaming in
            if !isStreaming {
                processNextQueued()
            }
        }
        .onAppear {
            lastPasteChangeCount = NSPasteboard.general.changeCount
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                isInputFocused = true
            }
            if let path = windowState.selectedProject?.path {
                AtFileSearch.prefetch(projectPath: path)
            }
        }
        .onChange(of: windowState.selectedProject?.path) { _, newPath in
            if let path = newPath {
                AtFileSearch.prefetch(projectPath: path)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = true }
    }

    // MARK: - Input Row

    @ViewBuilder
    private var inputRow: some View {
        HStack(spacing: 10) {
            Button {
                showFilePicker = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 14))
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help("Attach file")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }

            inputTextField

            if !showSlashPopup {
                ClaudeSendButton(
                    isEnabled: !windowState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !windowState.attachments.isEmpty,
                    action: sendMessage
                )
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                ClaudeSendButton(isEnabled: false, action: {}).disabled(true)
            }
        }
    }

    @ViewBuilder
    private var inputTextField: some View {
        TextField(String(localized: "Type a message...", bundle: .module), text: Bindable(windowState).inputText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(ClaudeTheme.textPrimary)
            .lineLimit(1...10)
            .focused($isInputFocused)
            .onChange(of: windowState.inputText) { oldValue, newValue in
                handleInputTextChange(oldValue: oldValue, newValue: newValue)
            }
            .onKeyPress(.return, phases: .down) { handleReturnKey($0) }
            .onKeyPress(.upArrow, phases: .down) { _ in handleUpArrow() }
            .onKeyPress(.downArrow, phases: .down) { _ in handleDownArrow() }
            .onKeyPress(.tab, phases: .down) { _ in handleTab() }
            .onKeyPress(keys: [.init("v")], phases: .down) { handlePasteKey($0) }
            .onKeyPress(.escape, phases: .down) { _ in handleEscapeKey() }
            .id(textFieldLayoutID)
    }

    private func handleInputTextChange(oldValue: String, newValue: String) {
        let pbCount = NSPasteboard.general.changeCount
        defer {
            isPasteInProgress = false
            lastPasteChangeCount = pbCount
        }
        if windowState.skipPasteDetection {
            windowState.skipPasteDetection = false
            return
        }
        let delta = newValue.count - oldValue.count
        if delta > 1 && (isPasteInProgress || pbCount != lastPasteChangeCount) {
            if let result = detectPasteContent() {
                switch result {
                case .attachment(let attachment):
                    windowState.addAttachment(attachment)
                    windowState.skipPasteDetection = true
                    windowState.inputText = oldValue
                case .filePath(let path):
                    windowState.skipPasteDetection = true
                    windowState.inputText = oldValue + path
                }
                return
            }
        }

        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        let hasSpaceAfterSlash = newValue.contains(" ")
        let shouldShowSlash = trimmed.hasPrefix("/") && !hasSpaceAfterSlash
        if shouldShowSlash != showSlashPopup {
            withAnimation(.easeOut(duration: 0.15)) { showSlashPopup = shouldShowSlash }
        }
        if shouldShowSlash { slashSelectedIndex = 0 }

        let shouldShowAt = !shouldShowSlash && hasActiveAtQuery(in: newValue)
        if shouldShowAt != showAtFilePopup {
            withAnimation(.easeOut(duration: 0.15)) { showAtFilePopup = shouldShowAt }
        }
        if shouldShowAt { atFileSelectedIndex = 0 }

        if pendingSend {
            pendingSend = false
            sendMessage()
        }
    }

    private func handleUpArrow() -> KeyPress.Result {
        if showAtFilePopup && !atFileFilteredEntries.isEmpty {
            let count = atFileFilteredEntries.count
            atFileSelectedIndex = (atFileSelectedIndex - 1 + count) % count
            return .handled
        }
        if showSlashPopup && !slashFilteredCommands.isEmpty {
            let count = slashFilteredCommands.count
            slashSelectedIndex = (slashSelectedIndex - 1 + count) % count
            return .handled
        }
        let history = userMessageHistory
        guard !history.isEmpty else { return .ignored }
        let nextIndex = historyIndex + 1
        if nextIndex < history.count {
            historyIndex = nextIndex
            let msgIndex = history.count - 1 - historyIndex
            windowState.skipPasteDetection = true
            windowState.inputText = history[msgIndex]
        }
        return .handled
    }

    private func handleDownArrow() -> KeyPress.Result {
        if showAtFilePopup && !atFileFilteredEntries.isEmpty {
            let count = atFileFilteredEntries.count
            atFileSelectedIndex = (atFileSelectedIndex + 1) % count
            return .handled
        }
        if showSlashPopup && !slashFilteredCommands.isEmpty {
            let count = slashFilteredCommands.count
            slashSelectedIndex = (slashSelectedIndex + 1) % count
            return .handled
        }
        guard historyIndex >= 0 else { return .ignored }
        historyIndex -= 1
        if historyIndex < 0 {
            windowState.skipPasteDetection = true
            windowState.inputText = ""
        } else {
            let history = userMessageHistory
            let msgIndex = history.count - 1 - historyIndex
            if msgIndex >= 0 && msgIndex < history.count {
                windowState.skipPasteDetection = true
                windowState.inputText = history[msgIndex]
            }
        }
        return .handled
    }

    private func handleTab() -> KeyPress.Result {
        if showAtFilePopup && !atFileFilteredEntries.isEmpty {
            let entries = atFileFilteredEntries
            if atFileSelectedIndex < entries.count { selectAtFile(entries[atFileSelectedIndex].relativePath) }
            return .handled
        }
        guard showSlashPopup && !slashFilteredCommands.isEmpty else { return .ignored }
        let commands = slashFilteredCommands
        if slashSelectedIndex < commands.count { selectSlashCommand(commands[slashSelectedIndex]) }
        return .handled
    }

    private func handlePasteKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers == .command else { return .ignored }
        let pb = NSPasteboard.general
        let hasString = pb.string(forType: .string) != nil
        let hasFileURL = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.contains(where: \.isFileURL) == true
        let hasImageData = pb.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
        if hasImageData || (!hasString && hasFileURL) {
            if let result = detectPasteContent() {
                switch result {
                case .attachment(let att): windowState.addAttachment(att)
                case .filePath(let path):
                    windowState.skipPasteDetection = true
                    windowState.inputText += path
                }
                return .handled
            }
            return .ignored
        }
        // Multi-line text: intercept to preserve newlines, since NSTextField may strip them.
        // Also force TextField to remeasure its height after programmatic text update.
        if let text = pb.string(forType: .string), text.contains("\n"),
           text.count < AttachmentFactory.longTextThreshold {
            let current = windowState.inputText
            if let editor = NSApp.keyWindow?.firstResponder as? NSText {
                let range = editor.selectedRange
                let nsString = current as NSString
                if range.location != NSNotFound {
                    windowState.skipPasteDetection = true
                    windowState.inputText = nsString.replacingCharacters(in: range, with: text)
                    textFieldLayoutID += 1
                    DispatchQueue.main.async { isInputFocused = true }
                    return .handled
                }
            }
            windowState.skipPasteDetection = true
            windowState.inputText = current + text
            textFieldLayoutID += 1
            DispatchQueue.main.async { isInputFocused = true }
            return .handled
        }
        // For all other pastes: flag onChange to check for file/image/long-text.
        // This handles cases like Finder file copy (has both file URL and string path).
        isPasteInProgress = true
        return .ignored
    }

    private func handleEscapeKey() -> KeyPress.Result {
        if showAtFilePopup {
            withAnimation(.easeOut(duration: 0.15)) { showAtFilePopup = false }
            return .handled
        }
        if showSlashPopup {
            withAnimation(.easeOut(duration: 0.15)) { showSlashPopup = false }
            return .handled
        }
        if chatBridge.isStreaming {
            Task { await chatBridge.cancelStreaming() }
            return .handled
        }
        return .ignored
    }

    // MARK: - Slash / At Queries

    private var slashQuery: String {
        let text = windowState.inputText
        guard !text.contains(" ") else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return "" }
        return trimmed
    }

    private var slashFilteredCommands: [SlashCommand] {
        SlashCommandRegistry.filtered(by: slashQuery)
    }

    private var userMessageHistory: [String] {
        chatBridge.messages.filter { $0.role == .user }.map(\.content)
    }

    private var atFileQuery: String {
        let text = windowState.inputText
        guard let atRange = text.range(of: "@", options: .backwards) else { return "" }
        let afterAt = String(text[atRange.upperBound...])
        if afterAt.contains(" ") { return "" }
        return afterAt
    }

    private var atFileFilteredEntries: [AtFileEntry] {
        guard let project = windowState.selectedProject else { return [] }
        return AtFileSearch.search(query: atFileQuery, projectPath: project.path)
    }

    private func selectSlashCommand(_ cmd: SlashCommand) {
        withAnimation(.easeOut(duration: 0.15)) { showSlashPopup = false }
        windowState.skipPasteDetection = true
        if cmd.acceptsInput && !cmd.isInteractive {
            windowState.inputText = cmd.command + " "
        } else {
            windowState.inputText = ""
            Task { await chatBridge.sendSlashCommand(cmd.command) }
        }
    }

    private func selectAtFile(_ relativePath: String) {
        withAnimation(.easeOut(duration: 0.15)) { showAtFilePopup = false }
        var text = windowState.inputText
        if let atRange = text.range(of: "@", options: .backwards) {
            text.replaceSubrange(atRange.lowerBound..., with: "@\(relativePath) ")
        }
        windowState.skipPasteDetection = true
        windowState.inputText = text
    }

    private func hasActiveAtQuery(in text: String) -> Bool {
        guard let atRange = text.range(of: "@", options: .backwards) else { return false }
        let afterAt = String(text[atRange.upperBound...])
        return !afterAt.contains(" ")
    }

    // MARK: - Queued Message Previews

    private var queuedMessagePreviews: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(windowState.messageQueue) { queued in
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(ClaudeTheme.textSecondary.opacity(0.7))

                    Text(queued.text.isEmpty ? String(localized: "(attachment)", bundle: .module) : queued.text)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 240)

                    if !queued.attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                            .foregroundStyle(ClaudeTheme.textSecondary.opacity(0.7))
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            windowState.dequeueMessage(id: queued.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ClaudeTheme.textSecondary)
                            .padding(3)
                            .background(ClaudeTheme.textSecondary.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .opacity(0.9)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Attachment Previews

    private var attachmentPreviews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(windowState.attachments) { attachment in
                    AttachmentPreviewItem(attachment: attachment) {
                        windowState.removeAttachment(attachment.id)
                    } onTap: {
                        if attachment.type == .text { textPreviewAttachment = attachment }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Send / Return

    private func sendMessage() {
        guard !windowState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !windowState.attachments.isEmpty else { return }
        historyIndex = -1

        if chatBridge.isStreaming {
            withAnimation(.easeOut(duration: 0.2)) {
                windowState.enqueueMessage(text: windowState.inputText, attachments: windowState.attachments)
            }
            windowState.skipPasteDetection = true
            windowState.inputText = ""
            windowState.attachments = []
            return
        }

        Task { await chatBridge.send() }
    }

    private func processNextQueued() {
        guard let next = windowState.dequeueNext() else { return }
        windowState.skipPasteDetection = true
        windowState.inputText = next.text
        windowState.attachments = next.attachments
        Task { await chatBridge.send() }
    }

    private func handleReturnKey(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.shift) {
            windowState.inputText.append("\n")
            return .handled
        }
        if showSlashPopup && !slashFilteredCommands.isEmpty {
            let commands = slashFilteredCommands
            if slashSelectedIndex < commands.count {
                if keyPress.modifiers.contains(.command) {
                    let cmd = commands[slashSelectedIndex]
                    if cmd.detailDescription != nil { slashDetailCommand = cmd }
                } else {
                    selectSlashCommand(commands[slashSelectedIndex])
                }
            }
            return .handled
        }
        if showAtFilePopup && !atFileFilteredEntries.isEmpty {
            let entries = atFileFilteredEntries
            if atFileSelectedIndex < entries.count {
                selectAtFile(entries[atFileSelectedIndex].relativePath)
            }
            return .handled
        }
        // If IME is composing (e.g. last Korean character), commit with unmarkText().
        // Return .handled instead of .ignored to prevent NSTextField "end editing" behavior (select all).
        // After commit, onChange fires and pendingSend flag triggers auto-send.
        if NSTextInputContext.current?.client.hasMarkedText() == true {
            NSTextInputContext.current?.client.unmarkText()
            pendingSend = true
            return .handled
        }
        sendMessage()
        return .handled
    }

    // MARK: - Paste & File Import

    private func processItemProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasRepresentationConforming(toTypeIdentifier: UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    if let attachment = AttachmentFactory.fromFileURL(url) {
                        DispatchQueue.main.async { windowState.addAttachment(attachment) }
                        return
                    }
                    // File URL exists but unsupported type — fall back to image data if available
                    guard provider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) else { return }
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        guard let data else { return }
                        let name = "drop-\(UUID().uuidString.prefix(8)).png"
                        let attachment = Attachment(type: .image, name: name, imageData: data)
                        DispatchQueue.main.async { windowState.addAttachment(attachment) }
                    }
                }
            } else if provider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    let name = "drop-\(UUID().uuidString.prefix(8)).png"
                    let attachment = Attachment(type: .image, name: name, imageData: data)
                    DispatchQueue.main.async { windowState.addAttachment(attachment) }
                }
            }
        }
    }

    enum PasteResult {
        case attachment(Attachment)
        case filePath(String)
    }

    private func detectPasteContent() -> PasteResult? {
        let pb = NSPasteboard.general
        let fileURL = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: \.isFileURL)
        if let url = fileURL {
            if let attachment = AttachmentFactory.fromFileURL(url) {
                return .attachment(attachment)
            }
            // Unsupported file type — fall through to image data check before returning path
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pb.data(forType: type) {
                return .attachment(Attachment(type: .image, name: "clipboard-\(UUID().uuidString.prefix(8)).png", imageData: data))
            }
        }
        // Fallback: handles JPEG, HEIC, and other image formats not caught above
        if let image = NSImage(pasteboard: pb),
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            return .attachment(Attachment(type: .image, name: "clipboard-\(UUID().uuidString.prefix(8)).png", imageData: pngData))
        }
        // No image data found — if there was an unsupported file URL, return its path
        if let url = fileURL {
            return .filePath(url.path)
        }
        if let text = pb.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains("\n"), trimmed.hasPrefix("/"),
               FileManager.default.fileExists(atPath: trimmed) {
                let url = URL(fileURLWithPath: trimmed)
                if let attachment = AttachmentFactory.fromFileURL(url) {
                    return .attachment(attachment)
                }
                return .filePath(trimmed)
            }
            if !trimmed.contains(" "), !trimmed.contains("\n"),
               let url = URL(string: trimmed),
               let scheme = url.scheme, ["http", "https"].contains(scheme),
               url.host != nil {
                return .attachment(AttachmentFactory.fromURL(url))
            }
            if text.count >= AttachmentFactory.longTextThreshold {
                return .attachment(AttachmentFactory.fromLongText(text))
            }
        }
        return nil
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            if let attachment = AttachmentFactory.fromFileURL(url) {
                windowState.addAttachment(attachment)
            }
        }
    }
}
