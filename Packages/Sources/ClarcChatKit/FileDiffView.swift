import SwiftUI
import ClarcCore

public struct FileDiffView: View {
    public let filePath: String
    public let fileName: String
    public let editHunks: [PreviewFile.EditHunk]
    @Environment(WindowState.self) private var windowState
    @State private var diffLines: [DiffLine] = []
    @State private var isLoading = true
    @State private var isCopied = false

    public init(filePath: String, fileName: String, editHunks: [PreviewFile.EditHunk] = []) {
        self.filePath = filePath
        self.fileName = fileName
        self.editHunks = editHunks
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()
            contentArea
        }
        .background(ClaudeTheme.background)
        .background {
            Button("") { windowState.diffFile = nil }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .task(id: filePath) { await loadDiff() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: ClaudeTheme.messageSize(13)))
                .foregroundStyle(ClaudeTheme.accent)

            Text(fileName)
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .semibold, design: .monospaced))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("Diff", bundle: .module)
                .font(.system(size: ClaudeTheme.messageSize(10), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(ClaudeTheme.surfaceSecondary, in: Capsule())

            if !diffLines.isEmpty {
                Button {
                    let raw = diffLines.map(\.text).joined(separator: "\n")
                    copyToClipboard(raw, feedback: $isCopied)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: ClaudeTheme.messageSize(12)))
                        .foregroundStyle(isCopied ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .help(isCopied ? "Copied" : "Copy")
            }

            Button { windowState.diffFile = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
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

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            VStack(spacing: 8) {
                Spacer()
                ProgressView().controlSize(.small)
                Text("loading...", bundle: .module)
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(ClaudeTheme.codeBackground)
        } else if diffLines.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: ClaudeTheme.messageSize(24)))
                    .foregroundStyle(ClaudeTheme.statusSuccess)
                Text("No changes", bundle: .module)
                    .font(.system(size: ClaudeTheme.messageSize(13)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(ClaudeTheme.codeBackground)
        } else {
            diffContentView
        }
    }

    private var diffContentView: some View {
        let lineNumberWidth = CGFloat(max(String(diffLines.count).count * 8 + 12, 32))

        return GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffLines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 0) {
                            Text(line.kind == .meta ? "" : "\(index + 1)")
                                .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                                .foregroundStyle(ClaudeTheme.textTertiary.opacity(0.6))
                                .frame(width: lineNumberWidth, height: 19, alignment: .trailing)
                                .padding(.trailing, 6)
                                .background(ClaudeTheme.codeBackground.opacity(0.5))
                            Rectangle()
                                .fill(ClaudeTheme.border.opacity(0.5))
                                .frame(width: 1, height: 19)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                                .foregroundStyle(line.kind.foregroundColor)
                                .frame(height: 19)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 10)
                        }
                        .padding(.trailing, 12)
                        .background(line.kind.backgroundColor)
                    }
                }
                .padding(.vertical, 10)
                .textSelection(.enabled)
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .background(ClaudeTheme.codeBackground)
    }

    // MARK: - Diff Sources

    private func loadDiff() async {
        isLoading = true
        defer { isLoading = false }

        if !editHunks.isEmpty {
            diffLines = buildEditDiffLines(from: editHunks)
            return
        }

        let workDir = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        let raw: String
        if let r1 = await GitHelper.run(["diff", "HEAD", "--", filePath], at: workDir) {
            raw = r1
        } else if let r2 = await GitHelper.run(["diff", "--", filePath], at: workDir) {
            raw = r2
        } else {
            raw = await GitHelper.run(["show", "HEAD", "--", filePath], at: workDir) ?? ""
        }
        diffLines = parseDiff(raw)
    }

    private func buildEditDiffLines(from hunks: [PreviewFile.EditHunk]) -> [DiffLine] {
        var lines: [DiffLine] = []
        for (index, hunk) in hunks.enumerated() {
            if hunks.count > 1 {
                lines.append(DiffLine(text: "@@ edit \(index + 1) of \(hunks.count) @@", kind: .hunk))
            }
            let (trimmedOld, trimmedNew) = stripCommonIndent(
                old: hunk.oldString.components(separatedBy: .newlines),
                new: hunk.newString.components(separatedBy: .newlines)
            )
            lines.append(contentsOf: trimmedOld.map { DiffLine(text: "-" + $0, kind: .removed) })
            lines.append(contentsOf: trimmedNew.map { DiffLine(text: "+" + $0, kind: .added) })
        }
        return lines
    }

    private func parseDiff(_ raw: String) -> [DiffLine] {
        guard !raw.isEmpty else { return [] }
        var lines = raw.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines.map { line in
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                return DiffLine(text: line, kind: .added)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                return DiffLine(text: line, kind: .removed)
            } else if line.hasPrefix("@@") {
                return DiffLine(text: line, kind: .hunk)
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") {
                return DiffLine(text: line, kind: .meta)
            } else {
                return DiffLine(text: line, kind: .context)
            }
        }
    }
}

// MARK: - Diff Line Model

struct DiffLine {
    enum Kind {
        case added, removed, hunk, meta, context

        var foregroundColor: Color {
            switch self {
            case .added:   return Color(hex: 0x3fb950)
            case .removed: return Color(hex: 0xf85149)
            case .hunk:    return Color(hex: 0x79c0ff)
            case .meta:    return ClaudeTheme.textTertiary
            case .context: return ClaudeTheme.textPrimary
            }
        }

        var backgroundColor: Color {
            switch self {
            case .added:   return Color(hex: 0x3fb950).opacity(0.12)
            case .removed: return Color(hex: 0xf85149).opacity(0.12)
            case .hunk:    return Color(hex: 0x388bfd).opacity(0.08)
            case .meta, .context: return .clear
            }
        }
    }

    let text: String
    let kind: Kind
}

// MARK: - Shared Indent Utility

func stripCommonIndent(old: [String], new: [String]) -> (old: [String], new: [String]) {
    let combined = old + new
    let commonIndent = combined
        .filter { !$0.allSatisfy(\.isWhitespace) }
        .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
        .min() ?? 0
    guard commonIndent > 0 else { return (old, new) }
    func strip(_ line: String) -> String {
        line.count >= commonIndent ? String(line.dropFirst(commonIndent)) : line
    }
    return (old.map(strip), new.map(strip))
}
