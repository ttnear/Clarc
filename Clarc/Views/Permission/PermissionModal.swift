import SwiftUI
import ClarcCore
import Combine

struct PermissionModal: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    let request: PermissionRequest

    @State private var remainingSeconds: Int = 300
    @FocusState private var isFocused: Bool

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            ClaudeThemeDivider()
            detailsSection
            Spacer()
            timerSection
            buttonSection
        }
        .padding(24)
        .frame(width: 480, height: 380)
        .background(ClaudeTheme.surfaceElevated)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            Task { await appState.respondToPermission(request, decision: .allow, in: windowState) }
            return .handled
        }
        .onAppear { isFocused = true }
        .onReceive(timer) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                Task { await appState.respondToPermission(request, decision: .deny, in: windowState) }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: ToolCategory(toolName: request.toolName).sfSymbol)
                .font(.title)
                .foregroundStyle(ClaudeTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Permission Request")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(ClaudeTheme.textPrimary)

                Text(request.toolName)
                    .font(.headline)
                    .foregroundStyle(ClaudeTheme.textPrimary)
            }

            Spacer()
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch request.toolName.lowercased() {
            case "bash", "execute":
                detailRow(label: "Command", value: extractString("command"))
            case "edit", "write", "multiedit", "multi_edit":
                detailRow(label: "File", value: extractString("file_path"))
            default:
                detailRow(label: "Input", value: inputSummary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundStyle(ClaudeTheme.textSecondary)

            ScrollView {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(ClaudeTheme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                    .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Timer

    private var timerSection: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textTertiary)

            Text("Auto-deny in \(formattedTime)")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
    }

    private var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Buttons

    /// Plan mode is a deliberate read-only stance; a one-click broad allow would silently undo it.
    private var hideBroadScopeButton: Bool {
        request.streamPermissionMode == .plan
    }

    private var bashCommand: String? {
        guard request.toolName.lowercased() == "bash",
              case .string(let cmd) = request.toolInput["command"] else { return nil }
        return cmd
    }

    private var broadScopeButtonLabel: LocalizedStringKey {
        if bashCommand != nil {
            return "Always allow this command"
        }
        return "Allow this tool for the session"
    }

    private var broadScopeDecision: PermissionDecision {
        if let cmd = bashCommand {
            return .allowAlwaysCommand(command: cmd)
        }
        return .allowSessionTool
    }

    private var buttonSection: some View {
        HStack(spacing: 12) {
            Button("Deny") {
                Task { await appState.respondToPermission(request, decision: .deny, in: windowState) }
            }
            .keyboardShortcut(.escape)
            .buttonStyle(ClaudeSecondaryButtonStyle())
            .controlSize(.large)

            Spacer()

            if !hideBroadScopeButton {
                Button(broadScopeButtonLabel) {
                    Task { await appState.respondToPermission(request, decision: broadScopeDecision, in: windowState) }
                }
                .buttonStyle(ClaudeSecondaryButtonStyle())
                .controlSize(.large)
            }

            Button("Allow") {
                Task { await appState.respondToPermission(request, decision: .allow, in: windowState) }
            }
            .keyboardShortcut(.return)
            .buttonStyle(ClaudeAccentButtonStyle())
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func extractString(_ key: String) -> String {
        if let value = request.toolInput[key] {
            if case .string(let s) = value { return s }
            return "\(value)"
        }
        return inputSummary
    }

    private var inputSummary: String {
        let pairs = request.toolInput.map { "\($0.key): \($0.value)" }
        return pairs.joined(separator: "\n")
    }
}

#Preview {
    PermissionModal(request: PermissionRequest(
        id: "test-1",
        toolName: "Bash",
        toolInput: ["command": .string("rm -rf /tmp/test")],
        runToken: "token"
    ))
    .environment(AppState())
}
