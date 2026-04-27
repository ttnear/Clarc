import SwiftUI
import ClarcCore

struct GitHubLoginView: View {
    @Environment(AppState.self) private var appState
    @State private var userCode: String?
    @State private var verificationURL: String?
    @State private var isPolling = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var codeCopied = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: ClaudeTheme.size(48)))
                .foregroundStyle(ClaudeTheme.accent)

            Text("Connect GitHub")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(ClaudeTheme.textPrimary)

            if appState.isLoggedIn {
                authenticatedView
            } else if let code = userCode {
                deviceCodeView(code: code)
            } else {
                startView
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.statusError)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(width: 480, height: 400)
        .background(ClaudeTheme.background)
    }

    // MARK: - Start View

    private var startView: some View {
        VStack(spacing: 12) {
            Text("Connect GitHub to fetch your repo list and add projects with a single click.")
                .font(.subheadline)
                .foregroundStyle(ClaudeTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await startDeviceFlow() }
            } label: {
                Label("Sign in with GitHub", systemImage: "arrow.right.circle")
            }
            .buttonStyle(ClaudeAccentButtonStyle())
            .disabled(isStarting)

            if isStarting {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Device Code View

    private func deviceCodeView(code: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Authentication Code")
                    .font(.subheadline)
                    .foregroundStyle(ClaudeTheme.textSecondary)

                Text(code)
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(ClaudeTheme.accent)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    codeCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        codeCopied = false
                    }
                } label: {
                    Label(codeCopied ? "Copied" : "Copy Code",
                          systemImage: codeCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(ClaudeSecondaryButtonStyle())

                Button {
                    if let url = verificationURL.flatMap({ URL(string: $0) }) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Authenticate on GitHub", systemImage: "safari")
                }
                .buttonStyle(ClaudeAccentButtonStyle())
            }

            if isPolling {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for authentication...")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Authenticated View

    private var authenticatedView: some View {
        VStack(spacing: 12) {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(ClaudeTheme.statusSuccess)
                .font(.title3)

            if let user = appState.gitHubUser {
                Text("@\(user.login)")
                    .font(.subheadline)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(ClaudeSecondaryButtonStyle())
        }
    }

    // MARK: - Logic

    private func startDeviceFlow() async {
        isStarting = true
        errorMessage = nil

        do {
            let response = try await appState.loginToGitHub()
            userCode = response.userCode
            verificationURL = response.verificationUri
            isStarting = false

            isPolling = true
            try await appState.completeGitHubLogin(
                deviceCode: response.deviceCode,
                interval: response.interval
            )
            isPolling = false

            await appState.fetchRepos()
        } catch {
            isStarting = false
            isPolling = false
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    GitHubLoginView()
        .environment(AppState())
}
