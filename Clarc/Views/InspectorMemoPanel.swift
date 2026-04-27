import SwiftUI
import AppKit
import ClarcCore

private let memoArchiveKey = "clarc.memoAttrData"
private let checkboxStateKey = NSAttributedString.Key("clarc.checkboxState")

private let defaultMemoFont: NSFont = .systemFont(ofSize: 14)
private let defaultMemoParagraphStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.paragraphSpacing = 2
    style.lineSpacing = 2
    return style
}()
private let headingSizes: [Int: CGFloat] = [1: 22, 2: 19, 3: 16]
private let headingSizeSet: Set<CGFloat> = Set(headingSizes.values)
private let headingPrefixes: [Int: String] = [1: "# ", 2: "## ", 3: "### "]
private let bulletMarker = "- "
private let boldTrait = NSFontTraitMask(rawValue: 2)
private let italicTrait = NSFontTraitMask(rawValue: 1)

private func checkboxImage(symbolName: String, color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config)?
        .tinted(with: color)
}

private let uncheckedCheckboxImage: NSImage? = checkboxImage(symbolName: "circle", color: .secondaryLabelColor)
private let checkedCheckboxImage: NSImage? = checkboxImage(symbolName: "checkmark.circle.fill", color: .controlAccentColor)

// Physical key codes (hardware-independent of input method/locale)
private let kB: UInt16 = 11
private let kI: UInt16 = 34
private let kU: UInt16 = 32
private let kL: UInt16 = 37
private let kK: UInt16 = 40

// MARK: - MemoContext (toolbar ↔ text view bridge)

@Observable private final class MemoContext {
    weak var textView: MemoTextView?

    private func refocus() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    func applyBold()          { refocus(); textView?.applyFontTrait(boldTrait) }
    func applyItalic()        { refocus(); textView?.applyFontTrait(italicTrait) }
    func applyUnder()         { refocus(); textView?.toggleUnderline() }
    func addBullet()          { refocus(); textView?.toggleBulletPrefix() }
    func addCheckbox()        { refocus(); textView?.toggleCheckboxPrefix() }
    func applyHeading(level: Int) { refocus(); textView?.toggleHeadingPrefix(level: level) }

    func addLink() {
        guard let tv = textView else { return }
        let alert = NSAlert()
        alert.messageText = "Insert Link"
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { tv.window?.makeFirstResponder(tv); return }
        let raw = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { tv.window?.makeFirstResponder(tv); return }
        let urlString = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://\(raw)"
        tv.window?.makeFirstResponder(tv)
        tv.insertLink(urlString: urlString)
    }
}

// MARK: - InspectorMemoPanel

struct InspectorMemoPanel: View {
    var projectId: UUID? = nil
    var clearTrigger: UUID? = nil
    @State private var memoContext = MemoContext()

    var body: some View {
        VStack(spacing: 0) {
            RichEditorView(clearTrigger: clearTrigger, memoContext: memoContext, projectId: projectId)
                .id(projectId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MemoFormattingToolbar(context: memoContext)
        }
        .background(ClaudeTheme.background)
    }
}

// MARK: - Formatting toolbar

private struct MemoFormattingToolbar: View {
    let context: MemoContext

    var body: some View {
        HStack(spacing: 0) {
            toolbarBtn("bold",      label: "Bold (⌘B)",          action: context.applyBold)
            toolbarBtn("italic",    label: "Italic (⌘I)",         action: context.applyItalic)
            toolbarBtn("underline", label: "Underline (⌘U)",      action: context.applyUnder)
            toolbarDivider()
            toolbarTextBtn("H1", label: "Heading 1 (# )",   action: { context.applyHeading(level: 1) })
            toolbarTextBtn("H2", label: "Heading 2 (## )",  action: { context.applyHeading(level: 2) })
            toolbarTextBtn("H3", label: "Heading 3 (### )", action: { context.applyHeading(level: 3) })
            toolbarDivider()
            toolbarTextBtn("-", label: "Bullet (- )", action: context.addBullet)
            toolbarBtn("checkmark.circle", label: "Checkbox (⌘⇧L)", action: context.addCheckbox)
            toolbarBtn("link", label: "Link (⌘K)", action: context.addLink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ClaudeTheme.background)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func toolbarBtn(_ symbol: String, label: String, action: @escaping () -> Void, iconSize: CGFloat = 12) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func toolbarTextBtn(_ text: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func toolbarDivider() -> some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
            .opacity(0.5)
    }
}

// MARK: - Checkbox attachment

private func makeCheckboxAttachment(checked: Bool) -> NSAttributedString {
    let image = checked ? checkedCheckboxImage : uncheckedCheckboxImage
    let attachment = NSTextAttachment()
    attachment.image = image
    if let sz = image?.size {
        attachment.bounds = CGRect(x: 0, y: -2, width: sz.width, height: sz.height)
    }
    let fullRange = NSRange(location: 0, length: 1)
    let attrStr = NSMutableAttributedString(attachment: attachment)
    attrStr.addAttribute(checkboxStateKey, value: checked, range: fullRange)
    attrStr.addAttribute(.font, value: defaultMemoFont, range: fullRange)
    attrStr.addAttribute(.paragraphStyle, value: defaultMemoParagraphStyle, range: fullRange)
    return attrStr
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { [self] rect in
            color.set()
            self.draw(in: rect)
            rect.fill(using: .sourceIn)
            return true
        }
        img.isTemplate = false
        return img
    }
}

// MARK: - Heading styles

private func headingLevel(in ns: NSString, at start: Int) -> Int {
    let len = ns.length
    if start + 4 <= len, ns.substring(with: NSRange(location: start, length: 4)) == "### " { return 3 }
    if start + 3 <= len, ns.substring(with: NSRange(location: start, length: 3)) == "## "  { return 2 }
    if start + 2 <= len, ns.substring(with: NSRange(location: start, length: 2)) == "# "   { return 1 }
    return 0
}

private func applyHeadingStyles(to storage: NSTextStorage) {
    let ns = storage.string as NSString
    let total = ns.length
    var lineStart = 0
    var attributeChanges: [(NSRange, NSFont)] = []

    while lineStart < total {
        let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
        guard lineRange.length > 0 else { break }

        var contentRange = lineRange
        if ns.character(at: contentRange.location + contentRange.length - 1) == 0x0A {
            contentRange.length -= 1
        }

        if contentRange.length > 0 {
            let level = headingLevel(in: ns, at: lineStart)
            if level > 0, let size = headingSizes[level] {
                attributeChanges.append((contentRange, .boldSystemFont(ofSize: size)))
            } else {
                // Reset heading-sized fonts back to default
                storage.enumerateAttribute(.font, in: contentRange, options: []) { val, range, _ in
                    if let f = val as? NSFont, headingSizeSet.contains(f.pointSize) {
                        attributeChanges.append((range, defaultMemoFont))
                    }
                }
            }
        }

        lineStart = lineRange.location + lineRange.length
    }

    if !attributeChanges.isEmpty {
        storage.beginEditing()
        for (range, font) in attributeChanges {
            storage.addAttribute(.font, value: font, range: range)
        }
        storage.endEditing()
    }
}

// MARK: - Load post-processing

private func refreshCheckboxAttachments(_ attr: NSAttributedString) -> NSAttributedString {
    let mutable = NSMutableAttributedString(attributedString: attr)
    mutable.enumerateAttribute(checkboxStateKey,
                               in: NSRange(location: 0, length: mutable.length),
                               options: .reverse) { value, range, _ in
        if let state = value as? Bool {
            mutable.replaceCharacters(in: range, with: makeCheckboxAttachment(checked: state))
        }
    }
    return mutable
}

// MARK: - RichEditorView

private struct RichEditorView: NSViewRepresentable {
    let clearTrigger: UUID?
    let memoContext: MemoContext
    let projectId: UUID?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let tv = MemoTextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = true
        tv.importsGraphics = false
        tv.usesFontPanel = true
        tv.isAutomaticLinkDetectionEnabled = true
        tv.isAutomaticDataDetectionEnabled = false
        tv.allowsUndo = true
        tv.writingToolsBehavior = .complete
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.font = defaultMemoFont
        tv.textColor = .labelColor
        tv.defaultParagraphStyle = defaultMemoParagraphStyle
        tv.typingAttributes = [
            .font: defaultMemoFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultMemoParagraphStyle
        ]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = .width
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = tv

        _ = tv.layoutManager  // Force TextKit 1 before view appears

        let attr = context.coordinator.loadAttributedText()
        tv.textStorage?.setAttributedString(attr)
        if let storage = tv.textStorage { applyHeadingStyles(to: storage) }

        memoContext.textView = tv
        context.coordinator.setupKeyMonitor(textView: tv, memoContext: memoContext)
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeKeyMonitor()
        coordinator.cancelPendingSave()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let trigger = clearTrigger,
              trigger != context.coordinator.lastClearTrigger else { return }
        context.coordinator.lastClearTrigger = trigger
        context.coordinator.cancelPendingSave()
        guard let tv = scrollView.documentView as? NSTextView else { return }
        tv.textStorage?.setAttributedString(NSAttributedString(string: ""))
        UserDefaults.standard.removeObject(forKey: context.coordinator.storageKey)
    }

    func makeCoordinator() -> Coordinator { Coordinator(projectId: projectId) }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let projectId: UUID?
        var lastClearTrigger: UUID? = nil
        var saveTask: Task<Void, Never>?
        var eventMonitor: Any?

        init(projectId: UUID?) { self.projectId = projectId }

        var storageKey: String {
            guard let id = projectId else { return memoArchiveKey }
            return "\(memoArchiveKey).\(id.uuidString)"
        }

        func cancelPendingSave() {
            saveTask?.cancel()
            saveTask = nil
        }

        func loadAttributedText() -> NSAttributedString {
            guard let data = UserDefaults.standard.data(forKey: storageKey) else {
                return NSAttributedString(string: "")
            }
            do {
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
                unarchiver.requiresSecureCoding = false
                guard let attr = unarchiver.decodeObject(
                    forKey: NSKeyedArchiveRootObjectKey
                ) as? NSAttributedString else { return NSAttributedString(string: "") }
                return refreshCheckboxAttachments(attr)
            } catch {
                return NSAttributedString(string: "")
            }
        }

        func setupKeyMonitor(textView: MemoTextView, memoContext: MemoContext) {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak textView, weak memoContext] event in
                guard let tv = textView, tv.window?.firstResponder === tv else { return event }

                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let hasCmd   = mods.contains(.command)
                let hasShift = mods.contains(.shift)
                let hasOpt   = mods.contains(.option)
                let hasCtrl  = mods.contains(.control)

                if hasCmd && !hasShift && !hasOpt && !hasCtrl {
                    switch event.keyCode {
                    case kB: tv.applyFontTrait(boldTrait); return nil
                    case kI: tv.applyFontTrait(italicTrait); return nil
                    case kU: tv.toggleUnderline(); return nil
                    case kK: DispatchQueue.main.async { memoContext?.addLink() }; return nil
                    default: break
                    }
                }
                if hasCmd && hasShift && !hasOpt && !hasCtrl {
                    switch event.keyCode {
                    case kL: tv.toggleCheckboxPrefix(); return nil
                    default: break
                    }
                }
                return event
            }
        }

        private func isListLine(ns: NSString, storage: NSTextStorage, lineRange: NSRange) -> Bool {
            var start = lineRange.location
            while start < lineRange.location + lineRange.length, ns.character(at: start) == 0x09 { start += 1 }
            guard start < lineRange.location + lineRange.length else { return false }
            let char = ns.character(at: start)
            if char == 0xFFFC, storage.attribute(checkboxStateKey, at: start, effectiveRange: nil) != nil { return true }
            let markerLen = (bulletMarker as NSString).length
            let remaining = lineRange.location + lineRange.length - start
            return remaining >= markerLen && ns.substring(with: NSRange(location: start, length: markerLen)) == bulletMarker
        }

        func removeKeyMonitor() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }

        // MARK: NSTextViewDelegate

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let storage = textView.textStorage else { return false }

            if commandSelector == #selector(NSResponder.insertTab(_:)) ||
               commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                let dedent = commandSelector == #selector(NSResponder.insertBacktab(_:))
                let ns = storage.string as NSString
                let lineRange = ns.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
                guard isListLine(ns: ns, storage: storage, lineRange: lineRange) else { return false }
                if dedent {
                    guard lineRange.length > 0, ns.character(at: lineRange.location) == 0x09 else { return true }
                    storage.beginEditing()
                    storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 1), with: "")
                    storage.endEditing()
                } else {
                    let tabAttr = NSAttributedString(string: "\t", attributes: textView.typingAttributes)
                    storage.beginEditing()
                    storage.insert(tabAttr, at: lineRange.location)
                    storage.endEditing()
                }
                textView.didChangeText()
                return true
            }

            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            applyHeadingStyles(to: storage)

            let cursorLoc = textView.selectedRange().location
            let ns = storage.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: cursorLoc, length: 0))
            let linePrefix = ns.substring(with: NSRange(location: lineRange.location,
                                                         length: cursorLoc - lineRange.location))

            if lineRange.length >= 1,
               (storage.string as NSString).character(at: lineRange.location) == 0xFFFC,
               storage.attribute(checkboxStateKey, at: lineRange.location, effectiveRange: nil) != nil {
                let lineEnd = lineRange.location + lineRange.length
                let trailingNL = (lineEnd > 0 && ns.character(at: lineEnd - 1) == 0x0A) ? 1 : 0
                let contentEnd = lineEnd - trailingNL
                let contentStart = min(lineRange.location + 2, contentEnd)

                if cursorLoc <= contentStart || contentStart == contentEnd {
                    let removeRange = NSRange(location: lineRange.location,
                                              length: min(2, contentEnd - lineRange.location))
                    storage.replaceCharacters(in: removeRange, with: "")
                    textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    let newLine = NSMutableAttributedString(string: "\n",
                                                            attributes: textView.typingAttributes)
                    newLine.append(makeCheckboxAttachment(checked: false))
                    newLine.append(NSAttributedString(string: " ",
                                                      attributes: textView.typingAttributes))
                    textView.insertText(newLine, replacementRange: textView.selectedRange())
                }
                return true
            }

            for marker in [bulletMarker, "* "] {
                guard linePrefix.hasPrefix(marker) else { continue }
                if linePrefix == marker {
                    storage.replaceCharacters(
                        in: NSRange(location: lineRange.location,
                                    length: (marker as NSString).length), with: "")
                    textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    textView.insertText("\n\(marker)", replacementRange: textView.selectedRange())
                }
                return true
            }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            guard (tv as? MemoTextView)?.isApplyingAppearance != true else { return }

            // When the document is emptied (e.g. select-all + delete), residual
            // typing attributes from the previous selection can keep applying a
            // heading/bold style to the next input. Reset to defaults.
            if storage.length == 0 {
                tv.typingAttributes = [
                    .font: defaultMemoFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: defaultMemoParagraphStyle
                ]
            }

            let attr = NSAttributedString(attributedString: storage)
            cancelPendingSave()
            saveTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let data = try? NSKeyedArchiver.archivedData(
                    withRootObject: attr,
                    requiringSecureCoding: false
                ) else { return }
                UserDefaults.standard.set(data, forKey: self.storageKey)
            }
        }
    }
}

// MARK: - MemoTextView

private final class MemoTextView: NSTextView {

    var isApplyingAppearance = false

    // Prevent checkboxStateKey from bleeding into newly typed characters
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get {
            var attrs = super.typingAttributes
            attrs.removeValue(forKey: checkboxStateKey)
            return attrs
        }
        set { super.typingAttributes = newValue }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let storage = textStorage else { return }
        var replacements: [(NSRange, NSAttributedString)] = []
        storage.enumerateAttribute(checkboxStateKey,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: .reverse) { value, range, _ in
            if let state = value as? Bool {
                replacements.append((range, makeCheckboxAttachment(checked: state)))
            }
        }
        guard !replacements.isEmpty else { return }
        isApplyingAppearance = true
        storage.beginEditing()
        for (range, attrStr) in replacements { storage.replaceCharacters(in: range, with: attrStr) }
        storage.endEditing()
        isApplyingAppearance = false
    }

    override func paste(_ sender: Any?) {
        if let str = NSPasteboard.general.string(forType: .string),
           containsCheckboxMarkdown(str) {
            insertMarkdownWithCheckboxes(str)
        } else {
            super.paste(sender)
        }
        checkTextInDocument(nil)
        if let storage = textStorage { applyHeadingStyles(to: storage) }
    }

    override func copy(_ sender: Any?) {
        let md = markdownRepresentation(of: selectedRange())
        super.copy(sender)
        if !md.isEmpty { NSPasteboard.general.setString(md, forType: .string) }
    }

    override func cut(_ sender: Any?) {
        let md = markdownRepresentation(of: selectedRange())
        super.cut(sender)
        if !md.isEmpty { NSPasteboard.general.setString(md, forType: .string) }
    }

    private func markdownRepresentation(of range: NSRange) -> String {
        guard let storage = textStorage, range.length > 0 else { return "" }
        let substr = storage.attributedSubstring(from: range)
        let mutable = NSMutableString(string: substr.string)
        substr.enumerateAttribute(checkboxStateKey,
                                  in: NSRange(location: 0, length: mutable.length),
                                  options: .reverse) { value, range, _ in
            guard let state = value as? Bool,
                  range.length == 1,
                  mutable.character(at: range.location) == 0xFFFC else { return }
            mutable.replaceCharacters(in: range, with: state ? "- [x]" : "- [ ]")
        }
        return mutable as String
    }

    private func containsCheckboxMarkdown(_ s: String) -> Bool {
        s.contains("- [ ]") || s.contains("- [x]") || s.contains("- [X]")
    }

    private func insertMarkdownWithCheckboxes(_ s: String) {
        let result = NSMutableAttributedString()
        let lines = s.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            let ns = line as NSString
            var i = 0
            while i < ns.length {
                let c = ns.character(at: i)
                if c == 0x20 || c == 0x09 { i += 1 } else { break }
            }
            let indent = ns.substring(to: i)
            let afterIndent = ns.substring(from: i)

            var matched = false
            if afterIndent.count >= 5 {
                let prefix5 = String(afterIndent.prefix(5))
                if prefix5 == "- [ ]" || prefix5 == "- [x]" || prefix5 == "- [X]" {
                    let checked = prefix5 != "- [ ]"
                    var rest = String(afterIndent.dropFirst(5))
                    if rest.hasPrefix(" ") { rest = String(rest.dropFirst()) }
                    if !indent.isEmpty {
                        result.append(NSAttributedString(string: indent, attributes: typingAttributes))
                    }
                    result.append(makeCheckboxAttachment(checked: checked))
                    result.append(NSAttributedString(string: " " + rest, attributes: typingAttributes))
                    matched = true
                }
            }
            if !matched {
                result.append(NSAttributedString(string: line, attributes: typingAttributes))
            }
            if idx < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: typingAttributes))
            }
        }
        insertText(result, replacementRange: selectedRange())
    }

    private func isCheckboxChar(in storage: NSTextStorage, at idx: Int) -> Bool {
        guard idx < storage.length else { return false }
        let char = (storage.string as NSString).character(at: idx)
        return char == 0xFFFC && storage.attribute(checkboxStateKey, at: idx, effectiveRange: nil) != nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let idx = charIndex(at: point), let storage = textStorage else {
            super.mouseDown(with: event)
            return
        }
        if isCheckboxChar(in: storage, at: idx),
           let state = storage.attribute(checkboxStateKey, at: idx, effectiveRange: nil) as? Bool {
            toggleCheckbox(at: idx, was: state)
            return
        }
        super.mouseDown(with: event)
        if let link = storage.attribute(.link, at: idx, effectiveRange: nil) {
            let url: URL?
            if let u = link as? URL { url = u }
            else if let s = link as? String { url = URL(string: s) }
            else { url = nil }
            if let url { NSWorkspace.shared.open(url) }
        }
    }

    private func charIndex(at viewPoint: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let cp = NSPoint(x: viewPoint.x - textContainerOrigin.x,
                         y: viewPoint.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let gi = lm.glyphIndex(for: cp, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        guard fraction >= 0, fraction <= 1.0 else { return nil }
        // Verify the click lands within the glyph's actual line fragment (rejects clicks in empty space)
        let lineRect = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
        guard lineRect.contains(cp) else { return nil }
        let ci = lm.characterIndexForGlyph(at: gi)
        guard ci < (textStorage?.length ?? 0) else { return nil }
        return ci
    }

    func toggleCheckbox(at idx: Int, was: Bool) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let newState = !was
        let replacement = makeCheckboxAttachment(checked: newState)

        let lineRange = ns.lineRange(for: NSRange(location: idx, length: 0))
        let contentStart = min(idx + 2, lineRange.location + lineRange.length)
        var contentEnd = lineRange.location + lineRange.length
        if contentEnd > 0, ns.character(at: contentEnd - 1) == 0x0A { contentEnd -= 1 }
        let contentRange = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))

        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: idx, length: 1), with: replacement)
        if contentRange.length > 0 {
            if newState {
                storage.addAttribute(.strikethroughStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: contentRange)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                     range: contentRange)
            } else {
                storage.removeAttribute(.strikethroughStyle, range: contentRange)
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor,
                                     range: contentRange)
            }
        }
        storage.endEditing()
        didChangeText()
    }

    func applyFontTrait(_ trait: NSFontTraitMask) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()

        if sel.length == 0 {
            var attrs = typingAttributes
            let font = attrs[.font] as? NSFont ?? defaultMemoFont
            let has = NSFontManager.shared.traits(of: font).contains(trait)
            attrs[.font] = has
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            typingAttributes = attrs
            return
        }

        var allHas = true
        storage.enumerateAttribute(.font, in: sel, options: []) { val, _, stop in
            let f = val as? NSFont ?? defaultMemoFont
            if !NSFontManager.shared.traits(of: f).contains(trait) { allHas = false; stop.pointee = true }
        }
        var updates: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: sel, options: []) { val, range, _ in
            let f = val as? NSFont ?? defaultMemoFont
            updates.append((range, allHas
                ? NSFontManager.shared.convert(f, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(f, toHaveTrait: trait)))
        }
        storage.beginEditing()
        for (range, font) in updates { storage.addAttribute(.font, value: font, range: range) }
        storage.endEditing()
        didChangeText()
    }

    func toggleUnderline() {
        guard let storage = textStorage else { return }
        let sel = selectedRange()

        if sel.length == 0 {
            var attrs = typingAttributes
            let current = attrs[.underlineStyle] as? Int ?? 0
            if current != 0 { attrs.removeValue(forKey: .underlineStyle) }
            else { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            typingAttributes = attrs
            return
        }

        var allUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: sel, options: []) { val, _, stop in
            if (val as? Int ?? 0) == 0 { allUnderlined = false; stop.pointee = true }
        }
        storage.beginEditing()
        if allUnderlined { storage.removeAttribute(.underlineStyle, range: sel) }
        else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: sel) }
        storage.endEditing()
        didChangeText()
    }

    func toggleBulletPrefix() {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        let markerLen = (bulletMarker as NSString).length
        storage.beginEditing()
        if lineRange.length >= markerLen,
           ns.substring(with: NSRange(location: lineRange.location, length: markerLen)) == bulletMarker {
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: markerLen), with: "")
        } else {
            storage.insert(NSAttributedString(string: bulletMarker, attributes: typingAttributes),
                           at: lineRange.location)
        }
        storage.endEditing()
        didChangeText()
    }

    func toggleCheckboxPrefix() {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: selectedRange())

        storage.beginEditing()
        if lineRange.length >= 1,
           (storage.string as NSString).character(at: lineRange.location) == 0xFFFC,
           storage.attribute(checkboxStateKey, at: lineRange.location, effectiveRange: nil) != nil {
            var removeLen = 1
            if lineRange.length >= 2, ns.character(at: lineRange.location + 1) == 0x20 { removeLen = 2 }
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: removeLen), with: "")
        } else {
            let combined = NSMutableAttributedString()
            combined.append(makeCheckboxAttachment(checked: false))
            combined.append(NSAttributedString(string: " ", attributes: typingAttributes))
            storage.insert(combined, at: lineRange.location)
        }
        storage.endEditing()
        didChangeText()
    }

    func toggleHeadingPrefix(level: Int) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        guard let prefix = headingPrefixes[level] else { return }

        // Check if ANY heading prefix is present and remove it first
        for (_, p) in headingPrefixes.sorted(by: { $0.key > $1.key }) {
            let pLen = (p as NSString).length
            guard lineRange.length >= pLen else { continue }
            let start = ns.substring(with: NSRange(location: lineRange.location, length: pLen))
            if start == p {
                storage.replaceCharacters(in: NSRange(location: lineRange.location, length: pLen), with: "")
                if p == prefix {
                    applyHeadingStyles(to: storage)
                    didChangeText()
                    return
                }
                break
            }
        }

        // Insert new heading prefix
        let attr = NSAttributedString(string: prefix, attributes: typingAttributes)
        storage.insert(attr, at: lineRange.location)
        applyHeadingStyles(to: storage)
        didChangeText()
    }

    func insertLink(urlString: String) {
        guard let storage = textStorage, let url = URL(string: urlString) else { return }
        let sel = selectedRange()
        storage.beginEditing()
        if sel.length > 0 {
            storage.addAttribute(.link, value: url, range: sel)
        } else {
            var attrs = typingAttributes
            attrs[.link] = url
            let attrStr = NSAttributedString(string: urlString, attributes: attrs)
            storage.replaceCharacters(in: sel, with: attrStr)
        }
        storage.endEditing()
        if sel.length == 0 {
            setSelectedRange(NSRange(location: sel.location + (urlString as NSString).length, length: 0))
        }
        didChangeText()
    }
}
