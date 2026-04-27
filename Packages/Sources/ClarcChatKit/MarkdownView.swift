import SwiftUI
import ClarcCore

// MARK: - Render Group Cache

/// Shared cache that retains markdown parse results regardless of view recreation (.id changes).
/// NSCache is automatically purged under memory pressure.
private final class RenderGroupCache: @unchecked Sendable {
    static let shared = RenderGroupCache()
    private let cache = NSCache<NSString, CacheEntry>()

    private final class CacheEntry {
        let groups: [RenderGroup]
        init(_ groups: [RenderGroup]) { self.groups = groups }
    }

    init() {
        cache.countLimit = 200
        NotificationCenter.default.addObserver(forName: .clarcThemeDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func get(_ key: String) -> [RenderGroup]? {
        cache.object(forKey: key as NSString)?.groups
    }

    func set(_ key: String, _ groups: [RenderGroup]) {
        cache.setObject(CacheEntry(groups), forKey: key as NSString)
    }
}

// MARK: - Markdown Content View

/// Renders markdown text with styled code blocks, headers, lists, and rich text.
struct MarkdownContentView: View {
    let text: String
    @State private var cachedGroups: [RenderGroup]
    @State private var cachedText: String

    init(text: String) {
        self.text = text
        let groups: [RenderGroup]
        if let cached = RenderGroupCache.shared.get(text) {
            groups = cached
        } else {
            groups = Self.buildRenderGroups(for: text)
            RenderGroupCache.shared.set(text, groups)
        }
        _cachedGroups = State(initialValue: groups)
        _cachedText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(cachedGroups.enumerated()), id: \.offset) { _, group in
                switch group {
                case .attributedText(let attrStr):
                    Text(attrStr)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .blockquote(let attrStr):
                    BlockquoteView(content: attrStr)
                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                        .padding(.vertical, 8)
                case .table(let headers, let rows):
                    MarkdownTableView(headers: headers, rows: rows)
                        .padding(.vertical, 8)
                case .horizontalRule:
                    ClaudeThemeDivider()
                        .padding(.vertical, 8)
                }
            }
        }
        .onChange(of: text) { _, newText in
            guard newText != cachedText else { return }
            cachedText = newText
            if let cached = RenderGroupCache.shared.get(newText) {
                cachedGroups = cached
            } else {
                let groups = Self.buildRenderGroups(for: newText)
                RenderGroupCache.shared.set(newText, groups)
                cachedGroups = groups
            }
        }
    }

    // MARK: - Render Groups

    private static func buildRenderGroups(for text: String) -> [RenderGroup] {
        let blocks = parseBlocks(from: text)
        var groups: [RenderGroup] = []
        var current = AttributedString()
        var hasContent = false
        var inListOrQuote = false
        // On encountering a spacer, just set a flag instead of flushing to keep content in the same Text view
        // → prevents drag selection from breaking between paragraphs and bullets
        var afterSpacer = false

        // Buffer for consecutive blockquote lines; rendered as a single group with a continuous left bar
        var quoteBuffer = AttributedString()
        var quoteHasContent = false

        func flushQuote() {
            guard quoteHasContent else { return }
            var trimmed = quoteBuffer
            while trimmed.characters.last == "\n" {
                let lastIdx = trimmed.characters.index(before: trimmed.endIndex)
                trimmed.removeSubrange(lastIdx..<trimmed.endIndex)
            }
            if !trimmed.characters.isEmpty {
                groups.append(.blockquote(trimmed))
            }
            quoteBuffer = AttributedString()
            quoteHasContent = false
        }

        func flush() {
            flushQuote()
            guard hasContent else {
                afterSpacer = false
                return
            }
            // Remove trailing unnecessary newlines
            var trimmed = current
            while trimmed.characters.last == "\n" {
                let lastIdx = trimmed.characters.index(before: trimmed.endIndex)
                trimmed.removeSubrange(lastIdx..<trimmed.endIndex)
            }
            if !trimmed.characters.isEmpty {
                groups.append(.attributedText(trimmed))
            }
            current = AttributedString()
            hasContent = false
            inListOrQuote = false
            afterSpacer = false
        }

        func addNewline(thinSpacing: Bool = false) {
            guard hasContent else { return }
            var sep = AttributedString("\n")
            if thinSpacing { sep.font = .system(size: 8) }
            current.append(sep)
        }

        func appendPrefixed(prefix: String, content: String, contentColor: Color? = nil, thinSep: Bool = false, prefixFont: Font = .system(size: 15)) {
            addNewline(thinSpacing: thinSep)
            var prefixAttr = AttributedString(prefix)
            prefixAttr.font = prefixFont
            prefixAttr.foregroundColor = ClaudeTheme.accent
            current.append(prefixAttr)
            var itemText = inlineMarkdown(content)
            if let contentColor { itemText.foregroundColor = contentColor }
            current.append(itemText)
            hasContent = true
        }

        for block in blocks {
            // Any non-blockquote block ends an in-progress quote group
            if case .blockquote = block {} else if case .spacer = block {} else {
                flushQuote()
            }

            switch block {
            case .codeBlock(let lang, let code):
                flush()
                groups.append(.codeBlock(language: lang, code: code))

            case .table(let headers, let rows):
                flush()
                groups.append(.table(headers: headers, rows: rows))

            case .horizontalRule:
                flush()
                groups.append(.horizontalRule)

            case .heading(let level, let content):
                if hasContent {
                    current.append(AttributedString("\n\n"))
                }
                afterSpacer = false
                inListOrQuote = false
                var heading = inlineMarkdown(content)
                heading.font = fontForHeading(level)
                current.append(heading)
                hasContent = true

            case .text(let content):
                if hasContent {
                    // Paragraph break (\n\n) when transitioning from spacer or list → text
                    if afterSpacer || inListOrQuote {
                        current.append(AttributedString("\n"))
                    }
                }
                afterSpacer = false
                inListOrQuote = false
                addNewline()
                var textAttr = inlineMarkdown(content)
                current.append(textAttr)
                hasContent = true

            case .unorderedListItem(let content):
                if hasContent && afterSpacer && inListOrQuote {
                    current.append(AttributedString("\n"))
                }
                let isFirstBullet = hasContent && !inListOrQuote
                afterSpacer = false
                inListOrQuote = true
                appendPrefixed(prefix: "  \u{2022} ", content: content, thinSep: isFirstBullet)

            case .orderedListItem(let number, let content):
                if hasContent && afterSpacer && inListOrQuote {
                    current.append(AttributedString("\n"))
                }
                let isFirstOrdered = hasContent && !inListOrQuote
                afterSpacer = false
                inListOrQuote = true
                appendPrefixed(prefix: "  \(number). ", content: content, thinSep: isFirstOrdered, prefixFont: .system(size: 15).monospacedDigit())

            case .blockquote(let content):
                if quoteHasContent {
                    quoteBuffer.append(AttributedString("\n"))
                } else {
                    flush()
                }
                var itemText = inlineMarkdown(content)
                itemText.foregroundColor = ClaudeTheme.textSecondary
                quoteBuffer.append(itemText)
                quoteHasContent = true

            case .spacer:
                if quoteHasContent {
                    // Empty line inside a quote run: keep it as a paragraph break within the same quote group
                    quoteBuffer.append(AttributedString("\n"))
                } else {
                    // Just set a flag instead of flushing → handled as \n\n in the next block
                    afterSpacer = hasContent
                }
            }
        }

        flush()
        return groups
    }

    // MARK: - Inline Markdown

    private static func inlineMarkdown(_ content: String) -> AttributedString {
        parseInlineMarkdown(content)
    }

    private static func fontForHeading(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 20, weight: .bold)
        case 2: return .system(size: 18, weight: .bold)
        case 3: return .system(size: 16, weight: .semibold)
        case 4: return .system(size: 15, weight: .semibold)
        case 5: return .system(size: 15, weight: .medium)
        default: return .system(size: 15, weight: .medium)
        }
    }

    // MARK: - Block Parsing

    private static func parseBlocks(from text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent = ""
        var index = 0

        func flushText() {
            let trimmed = currentText.trimmingTrailingNewlines()
            if !trimmed.isEmpty {
                blocks.append(.text(trimmed))
            }
            currentText = ""
        }

        while index < lines.count {
            let line = lines[index]

            // Code block handling
            if !inCodeBlock && line.hasPrefix("```") {
                flushText()
                inCodeBlock = true
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeContent = ""
                index += 1
                continue
            }

            if inCodeBlock {
                if line.hasPrefix("```") {
                    blocks.append(.codeBlock(language: codeLanguage, code: codeContent.trimmingTrailingNewlines()))
                    inCodeBlock = false
                    codeLanguage = ""
                    codeContent = ""
                } else {
                    if !codeContent.isEmpty { codeContent += "\n" }
                    codeContent += line
                }
                index += 1
                continue
            }

            // Table detection: check if current line + next two lines form a table
            if let table = parseTable(lines: lines, startIndex: index) {
                flushText()
                blocks.append(.table(headers: table.headers, rows: table.rows))
                index = table.endIndex
                continue
            }

            // Heading
            if let headingMatch = parseHeading(line) {
                flushText()
                blocks.append(.heading(level: headingMatch.level, content: headingMatch.content))
                index += 1
                continue
            }

            // Horizontal rule
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.count >= 3,
               (trimmedLine.allSatisfy({ $0 == "-" || $0 == " " }) && trimmedLine.contains("-")) ||
               (trimmedLine.allSatisfy({ $0 == "*" || $0 == " " }) && trimmedLine.contains("*")) ||
               (trimmedLine.allSatisfy({ $0 == "_" || $0 == " " }) && trimmedLine.contains("_")),
               trimmedLine.filter({ $0 != " " }).count >= 3 {
                flushText()
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // Unordered list item
            if let listContent = parseUnorderedListItem(line) {
                flushText()
                blocks.append(.unorderedListItem(content: listContent))
                index += 1
                continue
            }

            // Ordered list item
            if let (number, listContent) = parseOrderedListItem(line) {
                flushText()
                blocks.append(.orderedListItem(number: number, content: listContent))
                index += 1
                continue
            }

            // Blockquote
            if trimmedLine.hasPrefix(">") {
                flushText()
                var quoteContent = String(trimmedLine.dropFirst())
                if quoteContent.hasPrefix(" ") {
                    quoteContent = String(quoteContent.dropFirst())
                }
                blocks.append(.blockquote(content: quoteContent))
                index += 1
                continue
            }

            // Empty line
            if trimmedLine.isEmpty {
                if !currentText.isEmpty {
                    flushText()
                    blocks.append(.spacer)
                }
                index += 1
                continue
            }

            // Regular text
            if !currentText.isEmpty { currentText += "\n" }
            currentText += line
            index += 1
        }

        // Handle remaining content
        if inCodeBlock && !codeContent.isEmpty {
            blocks.append(.codeBlock(language: codeLanguage, code: codeContent.trimmingTrailingNewlines()))
        } else {
            flushText()
        }

        return blocks
    }

    // MARK: - Table Parsing

    private static func parseTable(lines: [String], startIndex: Int) -> (headers: [String], rows: [[String]], endIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }

        let headerLine = lines[startIndex]
        let separatorLine = lines[startIndex + 1]

        // Header must contain pipes
        guard headerLine.contains("|") else { return nil }

        // Separator must be like |---|---| or ---|---
        let separatorTrimmed = separatorLine.trimmingCharacters(in: .whitespaces)
        guard isTableSeparator(separatorTrimmed) else { return nil }

        let headers = parseTableRow(headerLine)
        guard !headers.isEmpty else { return nil }

        // Collect data rows
        var rows: [[String]] = []
        var currentIndex = startIndex + 2

        while currentIndex < lines.count {
            let rowLine = lines[currentIndex]
            let trimmed = rowLine.trimmingCharacters(in: .whitespaces)

            // Stop if empty line or non-table line
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            // Skip if it's another separator line
            guard !isTableSeparator(trimmed) else {
                currentIndex += 1
                continue
            }

            let cells = parseTableRow(rowLine)
            rows.append(cells)
            currentIndex += 1
        }

        return (headers: headers, rows: rows, endIndex: currentIndex)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        // Must contain at least one -- pattern and only |, -, :, spaces (GFM: one or more dashes per cell)
        guard stripped.contains("--") else { return false }
        return stripped.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" }
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        // Remove leading/trailing pipes
        if content.hasPrefix("|") { content = String(content.dropFirst()) }
        if content.hasSuffix("|") { content = String(content.dropLast()) }
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Line Parsers

    private static func parseHeading(_ line: String) -> (level: Int, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, trimmed.count > level else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " else { return nil }
        let content = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return (level, content)
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")) {
            return String(trimmed.dropFirst(2))
        }
        return nil
    }

    private static func parseOrderedListItem(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let numberPart = trimmed[trimmed.startIndex..<dotIndex]
        guard let number = Int(numberPart), number >= 0 else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.hasPrefix(" ") else { return nil }
        return (number, String(afterDot.dropFirst()))
    }
}

// MARK: - Markdown Block

// MARK: - Render Group

private enum RenderGroup {
    case attributedText(AttributedString)
    case blockquote(AttributedString)
    case codeBlock(language: String, code: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
}

private func parseInlineMarkdown(_ content: String) -> AttributedString {
    let autoLinked = autoLinkURLs(sanitizeMarkdownLinkURLs(content))
    guard var result = try? AttributedString(
        markdown: autoLinked,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) else {
        return AttributedString(content)
    }
    // Apply base font per-run to preserve bold/italic emphasis from markdown parsing
    var codeRanges: [Range<AttributedString.Index>] = []
    for run in result.runs {
        guard let intent = run.inlinePresentationIntent else {
            result[run.range].font = .system(size: 15)
            continue
        }
        if intent.contains(.code) {
            codeRanges.append(run.range)
        } else {
            let isBold = intent.contains(.stronglyEmphasized)
            let isItalic = intent.contains(.emphasized)
            switch (isBold, isItalic) {
            case (true, true):  result[run.range].font = .system(size: 15, weight: .bold).italic()
            case (true, false): result[run.range].font = .system(size: 15, weight: .bold)
            case (false, true): result[run.range].font = .system(size: 15).italic()
            default:            result[run.range].font = .system(size: 15)
            }
        }
    }
    // Inline code spans: monospace font + background color
    for range in codeRanges.reversed() {
        result[range].font = .system(size: 14, design: .monospaced)
        result[range].foregroundColor = ClaudeTheme.textPrimary
        result[range].backgroundColor = ClaudeTheme.surfaceTertiary
        result[range].baselineOffset = 0.5
    }
    return result
}

/// Removes incorrectly included characters (such as backticks) from URLs inside markdown links `[text](url)`
func sanitizeMarkdownLinkURLs(_ text: String) -> String {
    let pattern = #"\[([^\]]*)\]\(([^)]*`[^)]*)\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    let range = NSRange(text.startIndex..., in: text)
    var result = text
    for match in regex.matches(in: text, range: range).reversed() {
        guard let fullRange = Range(match.range, in: result),
              let labelRange = Range(match.range(at: 1), in: result),
              let urlRange = Range(match.range(at: 2), in: result) else { continue }
        let label = String(result[labelRange])
        let url = String(result[urlRange]).replacingOccurrences(of: "`", with: "")
        result.replaceSubrange(fullRange, with: "[\(label)](\(url))")
    }
    return result
}

/// Converts bare URLs not already inside a markdown link into `[url](url)` form
func autoLinkURLs(_ text: String) -> String {
    // Leave URLs already inside markdown links untouched
    // Pattern: match only bare URLs that are not in ](url) or [text](url) form
    let pattern = #"(?<!\]\()(?<!\()https?://[^\s\)<>\[\]`]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    let range = NSRange(text.startIndex..., in: text)
    var result = text
    // Substitute from back to front to prevent index shifting
    let matches = regex.matches(in: text, range: range).reversed()
    for match in matches {
        guard let swiftRange = Range(match.range, in: result) else { continue }
        let url = String(result[swiftRange])
        result.replaceSubrange(swiftRange, with: "[\(url)](\(url))")
    }
    return result
}

private enum MarkdownBlock {
    case heading(level: Int, content: String)
    case text(String)
    case codeBlock(language: String, code: String)
    case unorderedListItem(content: String)
    case orderedListItem(number: Int, content: String)
    case blockquote(content: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
    case spacer
}

// MARK: - Blockquote View

private struct BlockquoteView: View {
    let content: AttributedString

    var body: some View {
        Text(content)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 13)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(ClaudeTheme.accent)
                    .frame(width: 3)
            }
    }
}

// MARK: - Table View

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { colIndex, header in
                        cellView(text: header, isHeader: true, colIndex: colIndex)
                    }
                }
                .background(ClaudeTheme.surfaceTertiary)

                // Separator
                GridRow {
                    Rectangle()
                        .fill(ClaudeTheme.border)
                        .frame(height: 1)
                        .gridCellColumns(headers.count)
                }

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(headers.indices), id: \.self) { colIndex in
                            let text = colIndex < row.count ? row[colIndex] : ""
                            cellView(text: text, isHeader: false, colIndex: colIndex)
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.clear : ClaudeTheme.surfaceTertiary.opacity(0.4))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                    .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
            )
        }
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    private func cellView(text: String, isHeader: Bool, colIndex: Int) -> some View {
        Text(parseInlineMarkdown(text))
            .font(.system(size: ClaudeTheme.messageSize(14), weight: isHeader ? .semibold : .regular))
            .foregroundStyle(ClaudeTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 80, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if colIndex > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 0.5)
                }
            }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium, design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                }

                Spacer()

                copyButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(ClaudeTheme.codeHeaderBackground)

            Rectangle()
                .fill(ClaudeTheme.border)
                .frame(height: 0.5)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language, fontSize: 14))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ClaudeTheme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
        )
    }

    private var copyButton: some View {
        Button {
            copyToClipboard(code, feedback: $isCopied)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                Text(isCopied ? String(localized: "Copied", bundle: .module) : String(localized: "Copy", bundle: .module))
                    .font(.caption2)
            }
            .foregroundStyle(isCopied ? ClaudeTheme.statusSuccess : ClaudeTheme.textTertiary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - String Extension

private extension String {
    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }
}


// MARK: - Previews

#Preview("Markdown") {
    ScrollView {
        MarkdownContentView(text: """
        # H1 Heading
        ## H2 Subheading
        ### H3 Section heading
        #### H4 Small heading

        This is a **markdown** test. `Inline code` is also supported.

        > This is a blockquote. Use it to emphasize important content.

        - List item 1
        - List item 2
        - **Bold** list item 3

        1. Ordered list
        2. Second item
        3. Third item

        ---

        | Item | Value |
        |------|-------|
        | Swift files | 381 |
        | Total lines | ~55,000 |
        | SwiftUI : UIKit ratio | 87% : 13% |

        ```swift
        func hello() {
            print("Hello, World!")
        }
        ```

        Regular text continues here.
        """)
        .padding()
    }
    .frame(width: 500, height: 600)
    .background(ClaudeTheme.background)
}
