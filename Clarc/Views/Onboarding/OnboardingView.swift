import SwiftUI
import ClarcCore

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var isCheckingCLI = false
    @State private var cliInstalled = false
    @State private var cliVersion: String?
    @State private var cliError: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            cliCheckStep
                .frame(maxWidth: 460)

            Spacer()

            navigationButtons
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .frame(width: 560, height: 420)
        .background(ClaudeTheme.background)
        .task {
            await checkCLI()
        }
    }

    // MARK: - CLI Check

    private var cliCheckStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal")
                .font(.system(size: ClaudeTheme.size(48)))
                .foregroundStyle(ClaudeTheme.accent)

            Text("Claude CLI Installation Check")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(ClaudeTheme.textPrimary)

            if isCheckingCLI {
                ProgressView("Checking...")
            } else if cliInstalled {
                Label("Installed — \(cliVersion ?? "")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(ClaudeTheme.statusSuccess)
                    .font(.body)
            } else {
                VStack(spacing: 12) {
                    Label("Claude CLI not found", systemImage: "xmark.circle.fill")
                        .foregroundStyle(ClaudeTheme.statusError)
                        .font(.body)

                    if let error = cliError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(ClaudeTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Install command:")
                            .font(.subheadline)
                            .foregroundStyle(ClaudeTheme.textSecondary)

                        HStack {
                            Text("npm install -g @anthropic-ai/claude-code")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(ClaudeTheme.textPrimary)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(ClaudeTheme.codeBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    "npm install -g @anthropic-ai/claude-code",
                                    forType: .string
                                )
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(ClaudeTheme.textSecondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy")
                        }
                    }
                }

                Button("Check Again") {
                    Task { await checkCLI() }
                }
                .buttonStyle(ClaudeSecondaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            Spacer()
            Button("Get Started") {
                appState.skipGitHubLogin()
            }
            .buttonStyle(ClaudeAccentButtonStyle())
            .disabled(!cliInstalled)
        }
    }

    // MARK: - Helpers

    private func checkCLI() async {
        isCheckingCLI = true
        cliError = nil

        do {
            let version = try await appState.claude.checkVersion()
            cliVersion = version
            cliInstalled = true
            appState.claudeInstalled = true
        } catch {
            cliInstalled = false
            cliError = error.localizedDescription

            let binary = await appState.claude.findClaudeBinary()
            if let binary {
                cliError = "Binary found: \(binary), but version check failed"
                cliInstalled = true
                appState.claudeInstalled = true
            }
        }

        isCheckingCLI = false
    }

}

#Preview {
    OnboardingView()
        .environment(AppState())
}
