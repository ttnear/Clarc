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
    @State private var showAtFilePopup = false
    @State private var atFileSelectedIndex = 0
    @State private var historyIndex: Int = -1
    @State private var pendingSend = false
    @State private var pendingNewline = false
    @State private var textFieldLayoutID = 0
    @State private var queuePreviewHeight: CGFloat = 0
    @State private var measuredInputHeight: CGFloat = 20

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
            .overlay { dragOverlay }
            .overlay(alignment: .top) {
                if !windowState.messageQueue.isEmpty {
                    HStack(spacing: 0) {
                        Spacer()
                        queuedMessagePreviews
                            .background(
                                GeometryReader { geo in
                                    Color.clear.onAppear { queuePreviewHeight = geo.size.height }
                                        .onChange(of: geo.size.height) { _, h in queuePreviewHeight = h }
                                }
                            )
                    }
                    .offset(y: -queuePreviewHeight)
                    .transition(.offset(y: 10).combined(with: .opacity))
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
        .frame(maxWidth: .infinity)
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
                    .font(.system(size: ClaudeTheme.size(14)))
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
            .font(.system(size: ClaudeTheme.size(14)))
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
            .frame(minHeight: clampedInputHeight)
            .background(InputHeightMeasurer(text: windowState.inputText, measuredHeight: $measuredInputHeight))
    }

    private var clampedInputHeight: CGFloat {
        let oneLine: CGFloat = 20
        let maxLines: CGFloat = 10
        return min(max(measuredInputHeight, oneLine), oneLine * maxLines)
    }

    private func handleInputTextChange(oldValue: String, newValue: String) {
        // Safety net for paste routes onKeyPress doesn't intercept (context menu, Edit menu).
        // delta > 1 filters out single-keystroke typing; IME commits are too short to hit
        // the longTextThreshold, so false positives are not a concern.
        if newValue.count - oldValue.count > 1,
           let inserted = insertedSubstring(oldValue: oldValue, newValue: newValue) {
            if let attachment = attachmentFromPastedText(inserted) {
                windowState.addAttachment(attachment)
                windowState.inputText = oldValue
                return
            }
            if chatBridge.autoPreviewSettings.longText,
               inserted.count >= AttachmentFactory.longTextThreshold {
                windowState.addAttachment(AttachmentFactory.fromLongText(inserted))
                windowState.inputText = oldValue
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
        if pendingNewline {
            pendingNewline = false
            Task { @MainActor in
                windowState.inputText.append("\n")
            }
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
            windowState.inputText = ""
        } else {
            let history = userMessageHistory
            let msgIndex = history.count - 1 - historyIndex
            if msgIndex >= 0 && msgIndex < history.count {
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

    // Always returns .handled so NSTextField doesn't run a native paste in parallel.
    private func handlePasteKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers == .command else { return .ignored }
        let pb = NSPasteboard.general

        if let attachment = imageAttachmentFromPasteboard(pb) {
            if chatBridge.autoPreviewSettings.image {
                windowState.addAttachment(attachment)
            }
            return .handled
        }

        if let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: \.isFileURL) {
            if chatBridge.autoPreviewSettings.filePath,
               let attachment = AttachmentFactory.fromFileURL(url) {
                windowState.addAttachment(attachment)
            } else {
                insertAtCursor(url.path)
            }
            return .handled
        }

        guard let text = pb.string(forType: .string), !text.isEmpty else { return .handled }

        if let attachment = attachmentFromPastedText(text) {
            windowState.addAttachment(attachment)
            return .handled
        }

        if chatBridge.autoPreviewSettings.longText,
           text.count >= AttachmentFactory.longTextThreshold {
            windowState.addAttachment(AttachmentFactory.fromLongText(text))
            return .handled
        }

        insertAtCursor(text)
        return .handled
    }

    private func attachmentFromPastedText(_ text: String) -> Attachment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if chatBridge.autoPreviewSettings.filePath,
           let attachment = attachmentFromPathText(trimmed) {
            return attachment
        }
        if chatBridge.autoPreviewSettings.url,
           !trimmed.contains(" "), !trimmed.contains("\n"),
           let url = URL(string: trimmed),
           let scheme = url.scheme, ["http", "https"].contains(scheme),
           url.host != nil {
            return AttachmentFactory.fromURL(url)
        }
        return nil
    }

    /// Assumes a single insertion (paste/type at one cursor position) — not a general diff.
    private func insertedSubstring(oldValue: String, newValue: String) -> String? {
        guard newValue.count > oldValue.count else { return nil }

        var oldPrefix = oldValue.startIndex
        var newPrefix = newValue.startIndex
        while oldPrefix < oldValue.endIndex, newPrefix < newValue.endIndex,
              oldValue[oldPrefix] == newValue[newPrefix] {
            oldValue.formIndex(after: &oldPrefix)
            newValue.formIndex(after: &newPrefix)
        }

        var oldSuffix = oldValue.endIndex
        var newSuffix = newValue.endIndex
        while oldSuffix > oldPrefix, newSuffix > newPrefix {
            let prevOld = oldValue.index(before: oldSuffix)
            let prevNew = newValue.index(before: newSuffix)
            guard oldValue[prevOld] == newValue[prevNew] else { break }
            oldSuffix = prevOld
            newSuffix = prevNew
        }

        guard newPrefix < newSuffix else { return nil }
        return String(newValue[newPrefix..<newSuffix])
    }

    // Image paths skip fileExists — some screenshot tools write the clipboard before the file.
    private func attachmentFromPathText(_ trimmed: String) -> Attachment? {
        guard !trimmed.contains("\n"), !trimmed.isEmpty else { return nil }

        let path: String
        if trimmed.hasPrefix("file://") {
            guard let url = URL(string: trimmed), url.isFileURL else { return nil }
            path = url.path
        } else if trimmed.hasPrefix("/") {
            path = trimmed
        } else if trimmed.hasPrefix("~/") {
            path = (trimmed as NSString).expandingTildeInPath
        } else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if AttachmentFactory.imageExtensions.contains(ext) {
            return AttachmentFactory.fromFileURL(url)
        }
        if FileManager.default.fileExists(atPath: path) {
            return AttachmentFactory.fromFileURL(url)
        }
        return nil
    }

    private func insertAtCursor(_ text: String) {
        let current = windowState.inputText
        if let editor = NSApp.keyWindow?.firstResponder as? NSText {
            let range = editor.selectedRange
            if range.location != NSNotFound {
                windowState.inputText = (current as NSString).replacingCharacters(in: range, with: text)
                resetIMEState()
                return
            }
        }
        windowState.inputText = current + text
        resetIMEState()
    }

    private func imageAttachmentFromPasteboard(_ pb: NSPasteboard) -> Attachment? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pb.data(forType: type) {
                return Attachment(type: .image, name: "clipboard-\(UUID().uuidString.prefix(8)).png", imageData: data)
            }
        }
        if let image = NSImage(pasteboard: pb),
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            return Attachment(type: .image, name: "clipboard-\(UUID().uuidString.prefix(8)).png", imageData: pngData)
        }
        return nil
    }

    // Recreate the text field to reset IME state; prevents ghost Hangul leaking into the next input.
    private func resetIMEState() {
        textFieldLayoutID += 1
        DispatchQueue.main.async { isInputFocused = true }
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
            // Without this the last composing Hangul character leaks into the next input as a ghost prefix.
            NSTextInputContext.current?.client.unmarkText()
            resetIMEState()
            Task { await chatBridge.cancelStreaming() }
            return .handled
        }
        return .ignored
    }

    // MARK: - Slash / At Queries

    private var slashQuery: String {
        let text = windowState.inputText
        guard !text.contains(" ") else { return "" }
        guard text.hasPrefix("/") else { return "" }
        return text
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
        windowState.inputText = text
    }

    private func hasActiveAtQuery(in text: String) -> Bool {
        guard let atRange = text.range(of: "@", options: .backwards) else { return false }
        let afterAt = String(text[atRange.upperBound...])
        return !afterAt.contains(" ")
    }

    // MARK: - Drag Overlay

    @ViewBuilder private var dragOverlay: some View {
        if isDragOver {
            let shape = RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusPill)
            shape
                .strokeBorder(ClaudeTheme.accent.opacity(0.6), lineWidth: 2, antialiased: true)
                .background(ClaudeTheme.accent.opacity(0.05), in: shape)
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Queued Message Previews

    private var queuedMessagePreviews: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(windowState.messageQueue) { queued in
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: ClaudeTheme.size(10)))
                        .foregroundStyle(ClaudeTheme.textSecondary.opacity(0.7))

                    Text(queued.text.isEmpty ? String(localized: "(attachment)", bundle: .module) : queued.text)
                        .font(.system(size: ClaudeTheme.size(13)))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !queued.attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.system(size: ClaudeTheme.size(10)))
                            .foregroundStyle(ClaudeTheme.textSecondary.opacity(0.7))
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            windowState.dequeueMessage(id: queued.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: ClaudeTheme.size(9), weight: .semibold))
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
                .frame(maxWidth: 350)
                .opacity(0.9)
            }
        }
        .padding(.trailing, 24)
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
            windowState.inputText = ""
            windowState.attachments = []
            resetIMEState()
            return
        }

        Task { await chatBridge.send() }
        resetIMEState()
    }

    private func processNextQueued() {
        guard let next = windowState.dequeueNext() else { return }
        windowState.inputText = next.text
        windowState.attachments = next.attachments
        Task { await chatBridge.send() }
    }

    private func handleReturnKey(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.shift) {
            // Mirror the plain-Enter IME path: commit composing Hangul first, then append \n
            // once the committed text has propagated to inputText via onChange.
            if NSTextInputContext.current?.client.hasMarkedText() == true {
                NSTextInputContext.current?.client.unmarkText()
                pendingNewline = true
                return .handled
            }
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
                loadFileURLAsAttachment(from: provider)
            } else if provider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) {
                loadImageDataAsAttachment(from: provider)
            }
        }
    }

    private func loadFileURLAsAttachment(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               let attachment = AttachmentFactory.fromFileURL(url) {
                DispatchQueue.main.async { windowState.addAttachment(attachment) }
                return
            }
            // Inlined (not factored into loadImageDataAsAttachment) to keep `provider` within
            // this nonisolated closure — passing it to a MainActor method violates Sendable.
            guard provider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) else { return }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                let name = "drop-\(UUID().uuidString.prefix(8)).png"
                let attachment = Attachment(type: .image, name: name, imageData: data)
                DispatchQueue.main.async { windowState.addAttachment(attachment) }
            }
        }
    }

    private func loadImageDataAsAttachment(from provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            let name = "drop-\(UUID().uuidString.prefix(8)).png"
            let attachment = Attachment(type: .image, name: name, imageData: data)
            DispatchQueue.main.async { windowState.addAttachment(attachment) }
        }
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

// TextField(axis:.vertical) underreports height for soft-wrapped lines on macOS — it only grows
// with hard \n. A hidden Text at the same width/font reports the true wrapped height.
// Extracted as its own View so the long modifier chain on TextField doesn't push SourceKit's
// type-checker past its time budget.
private struct InputHeightMeasurer: View {
    let text: String
    @Binding var measuredHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            Text(measuringText)
                .font(.system(size: ClaudeTheme.size(14)))
                .frame(width: geo.size.width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(heightReporter)
                .hidden()
                .allowsHitTesting(false)
        }
    }

    private var heightReporter: some View {
        GeometryReader { inner in
            Color.clear
                .onAppear { measuredHeight = inner.size.height }
                .onChange(of: inner.size.height) { _, h in
                    measuredHeight = h
                }
        }
    }

    // A trailing \n has zero intrinsic height when rendered through Text, so append a space to
    // force the empty final line to be measured.
    private var measuringText: String {
        if text.isEmpty { return " " }
        return text.hasSuffix("\n") ? text + " " : text
    }
}
