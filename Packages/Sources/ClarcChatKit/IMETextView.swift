import SwiftUI
import AppKit

// SwiftUI's TextEditor (PlatformTextView) overrides insertText to enforce binding sync, which
// races and discards composing Hangul on commit. Hosting an NSTextView directly lets us own the
// binding and skip write-back while marked text is active, eliminating the race.
struct IMETextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var hasMarkedText: Bool
    var font: NSFont
    var textColor: NSColor
    var placeholder: String = ""
    var onReturn: () -> Void
    var onShiftReturn: () -> Void
    var onUpArrow: () -> Bool
    var onDownArrow: () -> Bool
    var onTab: () -> Bool
    var onEscape: () -> Bool
    var onPasteCommandV: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = _IMETextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 5
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        applyCallbacks(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? _IMETextView else { return }
        applyCallbacks(to: textView)
        // Skip write-in while IME is composing — same reason coordinator skips write-back.
        // Compare against coordinator's cached value to avoid materializing textView.string
        // (O(n) in length) on every parent re-render.
        if !textView.hasMarkedText(), context.coordinator.lastAppliedText != text {
            textView.string = text
            context.coordinator.lastAppliedText = text
        }
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }
        if textView.placeholder != placeholder { textView.placeholder = placeholder }
        // isKeyWindow guard prevents an unbounded async dispatch loop while the window is
        // inactive (sheets, modal dialogs) — makeFirstResponder would silently fail otherwise.
        if isFocused,
           let window = textView.window, window.isKeyWindow,
           window.firstResponder !== textView {
            DispatchQueue.main.async {
                if textView.window?.firstResponder !== textView {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
    }

    private func applyCallbacks(to textView: _IMETextView) {
        textView.onReturn = onReturn
        textView.onShiftReturn = onShiftReturn
        textView.onUpArrow = onUpArrow
        textView.onDownArrow = onDownArrow
        textView.onTab = onTab
        textView.onEscape = onEscape
        textView.onPasteCommandV = onPasteCommandV
        textView.onMarkedTextChange = { active in
            if hasMarkedText != active {
                hasMarkedText = active
            }
        }
        textView.onFocusChange = { focused in
            if isFocused != focused {
                isFocused = focused
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        var lastAppliedText: String = ""

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Skip binding write-back during IME composition; the binding picks up the committed
            // text from the next textDidChange after the IME finalizes.
            if tv.hasMarkedText() { return }
            let current = tv.string
            lastAppliedText = current
            if text.wrappedValue != current {
                text.wrappedValue = current
            }
        }
    }
}

fileprivate final class _IMETextView: NSTextView {
    var onReturn: () -> Void = {}
    var onShiftReturn: () -> Void = {}
    var onUpArrow: () -> Bool = { false }
    var onDownArrow: () -> Bool = { false }
    var onTab: () -> Bool = { false }
    var onEscape: () -> Bool = { false }
    var onPasteCommandV: () -> Bool = { false }
    var onMarkedTextChange: (Bool) -> Void = { _ in }
    var onFocusChange: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange(false) }
        return result
    }

    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty && !hasMarkedText(), !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let inset = textContainerInset
        let rect = NSRect(
            x: inset.width + padding,
            y: inset.height,
            width: max(0, bounds.width - inset.width * 2 - padding),
            height: max(0, bounds.height - inset.height * 2)
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholder.draw(in: rect, withAttributes: attrs)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onMarkedTextChange(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChange(false)
    }

    override func keyDown(with event: NSEvent) {
        // Shift+Enter: NSTextView doesn't bind this to a doCommand by default. Force-commit any
        // composing IME text, then fire the newline callback (which appends "\n" via the binding).
        if event.keyCode == 36, event.modifierFlags.contains(.shift) {
            commitMarkedTextIfNeeded()
            onShiftReturn()
            return
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            // IME has already committed any composing text via insertText: before this command
            // is dispatched. Binding is up-to-date.
            onReturn()
            return
        case #selector(insertTab(_:)):
            if onTab() { return }
        case #selector(moveUp(_:)):
            if onUpArrow() { return }
        case #selector(moveDown(_:)):
            if onDownArrow() { return }
        case #selector(cancelOperation(_:)):
            if onEscape() { return }
        default:
            break
        }
        super.doCommand(by: selector)
    }

    override func paste(_ sender: Any?) {
        if onPasteCommandV() { return }
        super.paste(sender)
    }

    private func commitMarkedTextIfNeeded() {
        guard hasMarkedText() else { return }
        let range = markedRange()
        guard range.location != NSNotFound, range.length > 0,
              let storage = textStorage,
              NSMaxRange(range) <= (storage.string as NSString).length else { return }
        let composing = (storage.string as NSString).substring(with: range)
        insertText(composing, replacementRange: range)
    }
}
