import SwiftUI
import ClarcCore

/// Detail preview sheet for text attachments
struct TextPreviewSheet: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(ClaudeTheme.accent)
                Text(attachment.name)
                    .font(.system(size: ClaudeTheme.size(14), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textPrimary)

                Spacer()

                Button {
                    if let text = attachment.textContent {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: ClaudeTheme.size(12)))
                }
                .buttonStyle(.borderless)
                .help("Copy")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: ClaudeTheme.size(16)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Text content
            ScrollView {
                if let text = attachment.textContent {
                    Text(text)
                        .font(.system(size: ClaudeTheme.size(13), design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .background(ClaudeTheme.background)
        }
        .frame(width: 600, height: 450)
        .background(ClaudeTheme.surfaceElevated)
    }
}
