import SwiftUI
import AppKit
import ClarcCore

private let memoTextKey = "clarc.memoText"
private let memoRTFKey  = "clarc.memoRTFData"

struct InspectorMemoPanel: View {
    var clearTrigger: UUID? = nil

    var body: some View {
        PlainEditorView(clearTrigger: clearTrigger)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ClaudeTheme.background)
    }
}

private struct PlainEditorView: NSViewRepresentable {
    let clearTrigger: UUID?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = .width
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = tv

        tv.string = context.coordinator.loadText()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let trigger = clearTrigger,
              trigger != context.coordinator.lastClearTrigger else { return }
        context.coordinator.lastClearTrigger = trigger
        context.coordinator.cancelPendingSave()
        guard let tv = scrollView.documentView as? NSTextView else { return }
        tv.string = ""
        UserDefaults.standard.set("", forKey: memoTextKey)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastClearTrigger: UUID? = nil
        var saveTask: Task<Void, Never>?

        func cancelPendingSave() {
            saveTask?.cancel()
            saveTask = nil
        }

        func loadText() -> String {
            // Migrate legacy RTF → plain text
            if let data = UserDefaults.standard.data(forKey: memoRTFKey),
               let attr = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) {
                let text = attr.string
                UserDefaults.standard.set(text, forKey: memoTextKey)
                UserDefaults.standard.removeObject(forKey: memoRTFKey)
                return text
            }
            return UserDefaults.standard.string(forKey: memoTextKey) ?? ""
        }

        // MARK: - NSTextViewDelegate

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }

            let cursorLoc = textView.selectedRange().location
            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: cursorLoc, length: 0))
            let linePrefix = text.substring(with: NSRange(location: lineRange.location,
                                                          length: cursorLoc - lineRange.location))

            for marker in ["- ", "* "] {
                guard linePrefix.hasPrefix(marker) else { continue }
                if linePrefix == marker {
                    guard let storage = textView.textStorage else { return false }
                    storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 2), with: "")
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
            guard let tv = notification.object as? NSTextView else { return }
            let text = tv.string
            cancelPendingSave()
            saveTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(text, forKey: memoTextKey)
            }
        }
    }
}
