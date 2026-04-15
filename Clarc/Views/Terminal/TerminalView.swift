import SwiftUI
import ClarcCore
import SwiftTerm

// MARK: - TerminalProcess

/// Reference type that manages the lifecycle of a terminal process.
final class TerminalProcess {
    var terminalView: LocalProcessTerminalView?
    private(set) var terminated = false

    func terminate() {
        guard !terminated else { return }
        terminated = true
        terminalView?.terminate()
        terminalView = nil
    }

    deinit {
        terminalView?.terminate()
    }
}

// MARK: - EmbeddedTerminalView

struct EmbeddedTerminalView: NSViewRepresentable {

    let executable: String
    let arguments: [String]
    var environment: [String]?
    var currentDirectory: String?
    var initialCommand: String?
    var onProcessTerminated: ((Int32) -> Void)?
    var process: TerminalProcess?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let tv = LocalProcessTerminalView(frame: .zero)

        // Set terminal background/foreground colors to match the theme
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tv.nativeBackgroundColor = isDark
            ? NSColor(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x18/255.0, alpha: 1) // dark: codeBackground
            : NSColor(red: 0xE8/255.0, green: 0xE5/255.0, blue: 0xDC/255.0, alpha: 1) // light: codeBackground
        tv.nativeForegroundColor = isDark
            ? NSColor(red: 0xCC/255.0, green: 0xC9/255.0, blue: 0xC0/255.0, alpha: 1) // dark: textPrimary
            : NSColor(red: 0x3C/255.0, green: 0x39/255.0, blue: 0x29/255.0, alpha: 1) // light: textPrimary

        tv.processDelegate = context.coordinator
        tv.startProcess(
            executable: executable,
            args: arguments,
            environment: resolvedEnvironment(),
            currentDirectory: currentDirectory
        )

        process?.terminalView = tv

        if let cmd = initialCommand {
            pollAndSend(tv: tv, command: cmd)
        }

        // Auto-focus after being added to the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            tv.window?.makeFirstResponder(tv)
        }

        return tv
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTerminated: onProcessTerminated)
    }

    /// Build an environment array that guarantees UTF-8 locale so Korean and other
    /// multibyte characters render correctly in the terminal.
    private func resolvedEnvironment() -> [String] {
        // Start from the caller-supplied environment or the current process environment.
        var env: [String: String]
        if let provided = environment {
            env = Dictionary(uniqueKeysWithValues: provided.compactMap { entry -> (String, String)? in
                let parts = entry.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            })
        } else {
            env = ProcessInfo.processInfo.environment
        }
        // Ensure UTF-8 locale for correct multibyte (Korean, CJK, etc.) rendering.
        if env["LANG"] == nil || !(env["LANG"]?.hasSuffix("UTF-8") ?? false) {
            env["LANG"] = "en_US.UTF-8"
        }
        env["LC_CTYPE"] = "UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
    }

    private func pollAndSend(tv: LocalProcessTerminalView, command: String, attempt: Int = 0) {
        guard attempt < 30 else { return }
        let proc = process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard proc?.terminated != true else { return }
            let terminal = tv.getTerminal()
            let firstLine = terminal.getLine(row: 0)?.translateToString(trimRight: true) ?? ""
            if !firstLine.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard proc?.terminated != true else { return }
                    tv.send(data: Array((command + "\r").utf8)[...])
                }
            } else {
                self.pollAndSend(tv: tv, command: command, attempt: attempt + 1)
            }
        }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        nonisolated(unsafe) let onTerminated: ((Int32) -> Void)?

        nonisolated init(onTerminated: ((Int32) -> Void)?) {
            self.onTerminated = onTerminated
        }

        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
            onTerminated?(exitCode ?? -1)
        }
    }
}

// MARK: - Interactive Terminal Popup

struct InteractiveTerminalPopup: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var environmentDismiss
    let state: InteractiveTerminalState
    @State private var processExited = false
    @State private var exitCode: Int32 = 0
    @State private var process = TerminalProcess()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(ClaudeTheme.accent)
                Text(state.title)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textPrimary)

                Spacer()

                if processExited {
                    HStack(spacing: 4) {
                        Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(exitCode == 0 ? ClaudeTheme.statusSuccess : ClaudeTheme.statusError)
                        Text(exitCode == 0 ? "exit 0" : "exit \(exitCode)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("w", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ClaudeThemeDivider()

            // Terminal
            EmbeddedTerminalView(
                executable: state.executable,
                arguments: state.arguments,
                environment: state.environment,
                currentDirectory: state.currentDirectory,
                initialCommand: state.initialCommand,
                onProcessTerminated: { code in
                    Task { @MainActor in
                        exitCode = code
                        processExited = true
                    }
                },
                process: process
            )
            .padding(8)
            .background(ClaudeTheme.codeBackground)
            .frame(minHeight: 700)
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 760, idealHeight: 860)
        .background(ClaudeTheme.surfaceElevated)
        .onDisappear {
            dismiss()
        }
    }

    private func dismiss() {
        process.terminate()
        if windowState.interactiveTerminal != nil {
            appState.dismissInteractiveTerminal(exitCode: exitCode, in: windowState)
        } else {
            environmentDismiss()
        }
    }
}
