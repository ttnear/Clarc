import Combine
import SwiftUI
import ClarcCore

public struct ChatView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(ChatBridge.self) private var chatBridge

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            messageScrollView

            InputBarView()

            StatusLineView()
        }
        .background(ClaudeTheme.background)
        .onKeyPress(.escape, phases: .down) { _ in
            guard chatBridge.isStreaming else { return .ignored }
            Task { await chatBridge.cancelStreaming() }
            return .handled
        }
        .onChange(of: windowState.selectedProject?.path) { _, _ in
            bindRegistries()
        }
        .onChange(of: windowState.registryVersion) { _, _ in
            bindRegistries()
        }
        .onAppear {
            bindRegistries()
        }
    }

    private func bindRegistries() {
        let path = windowState.selectedProject?.path
        SlashCommandRegistry.bind(to: path)
    }

    // MARK: - Messages

    private var messageScrollView: some View {
        MessageListView(onTapBackground: { windowState.requestInputFocus = true })
    }
}
