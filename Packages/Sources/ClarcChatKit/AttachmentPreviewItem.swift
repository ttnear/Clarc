import SwiftUI
import LinkPresentation
import ClarcCore

/// Attachment preview item — tall rectangular card
/// Shows an X button overlay on mouse hover
struct AttachmentPreviewItem: View {
    let attachment: Attachment
    let onRemove: () -> Void
    var onTap: (() -> Void)?

    @State private var isHovered = false

    private let cardWidth: CGFloat = 120
    private let cardHeight: CGFloat = 130

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ClaudeTheme.inputBorder.opacity(0.5), lineWidth: 1)
                )

            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.3))
                    .frame(width: cardWidth, height: cardHeight)

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: ClaudeTheme.size(18)))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.borderless)
                .offset(x: -4, y: 4)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch attachment.type {
        case .image:
            imageCard
        case .file:
            fileCard
        case .text:
            textCard
        case .link:
            linkCard
        }
    }

    // MARK: - Image Card

    @State private var renderedImage: CGImage?

    private var imageCard: some View {
        ZStack(alignment: .bottom) {
            if let cgImage = renderedImage {
                Image(decorative: cgImage, scale: 2.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
            } else {
                ClaudeTheme.surfaceSecondary
                    .frame(width: cardWidth, height: cardHeight)
                Image(systemName: "photo")
                    .font(.system(size: ClaudeTheme.size(22)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }

            Text(attachment.name)
                .font(.system(size: ClaudeTheme.size(10)))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.5))
        }
        .task(id: attachment.id) {
            renderedImage = makeCGImage()
        }
    }

    private func makeCGImage() -> CGImage? {
        guard let data = attachment.imageData else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 200,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - File Card

    private var fileCard: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.fill")
                .font(.system(size: ClaudeTheme.size(30)))
                .foregroundStyle(ClaudeTheme.accent)
            Text(attachment.name)
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(ClaudeTheme.surfaceSecondary)
    }

    // MARK: - Text Card

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let text = attachment.textContent {
                Text(text.prefix(300))
                    .font(.system(size: ClaudeTheme.size(7), design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .lineLimit(nil)
                    .padding(6)
            }
            Spacer(minLength: 0)

            HStack(spacing: 3) {
                Image(systemName: "doc.text")
                    .font(.system(size: ClaudeTheme.size(9)))
                Text(shortTextName)
                    .font(.system(size: ClaudeTheme.size(9)))
                    .lineLimit(1)
            }
            .foregroundStyle(ClaudeTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClaudeTheme.surfaceSecondary)
        }
        .background(ClaudeTheme.background)
    }

    private var shortTextName: String {
        if let text = attachment.textContent {
            let lines = text.components(separatedBy: .newlines).count
            return "\(lines) lines"
        }
        return ""
    }

    // MARK: - Link Card

    @State private var linkTitle: String?
    @State private var linkFavicon: NSImage?

    private var linkCard: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                if let favicon = linkFavicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "link")
                        .font(.system(size: ClaudeTheme.size(26)))
                        .foregroundStyle(ClaudeTheme.accent)
                }
            }

            Spacer()

            VStack(spacing: 3) {
                Text(attachment.name)
                    .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textPrimary)
                    .lineLimit(1)

                if let title = linkTitle {
                    Text(title)
                        .font(.system(size: ClaudeTheme.size(9)))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(ClaudeTheme.surfaceSecondary)
        .task(id: attachment.id) {
            await fetchLinkMetadata()
        }
    }

    private func fetchLinkMetadata() async {
        guard attachment.type == .link,
              let url = URL(string: attachment.path) else { return }

        let provider = LPMetadataProvider()
        provider.shouldFetchSubresources = true
        provider.timeout = 5

        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }

        linkTitle = metadata.title

        guard let iconProvider = metadata.iconProvider else { return }
        linkFavicon = await withCheckedContinuation { continuation in
            iconProvider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }
}
