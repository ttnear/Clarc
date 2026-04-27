import SwiftUI
import ClarcCore

/// View that visually shows the Git status of the project.
struct GitStatusView: View {
    let projectPath: String
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var gitStatus: GitStatusInfo = .loading
    @State private var refreshTask: Task<Void, Never>?
    @State private var localBranches: [String] = []
    @State private var remoteBranches: [String] = []
    @State private var headWatcher: (any DispatchSourceFileSystemObject)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch gitStatus {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Checking...")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Spacer()
                }

            case .notARepo:
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text("Not a Git repository")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Spacer()
                }

            case .clean(let branch):
                // First row: branch button + refresh
                HStack(spacing: 8) {
                    branchMenu(branch)
                    Spacer()
                    refreshButton
                }
                // Second row: status
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: ClaudeTheme.size(10)))
                        .foregroundStyle(ClaudeTheme.statusSuccess)
                    Text("No changes")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }

            case .dirty(let branch, let changes):
                // First row: branch button + refresh
                HStack(spacing: 8) {
                    branchMenu(branch)
                    Spacer()
                    refreshButton
                }
                // Second row: change status + badges
                HStack(spacing: 6) {
                    Circle()
                        .fill(ClaudeTheme.accent)
                        .frame(width: 6, height: 6)
                    Text("\(changes.total) changed")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(ClaudeTheme.accent)

                    if changes.modified > 0 {
                        badge("M \(changes.modified)", color: .blue)
                    }
                    if changes.added > 0 {
                        badge("A \(changes.added)", color: ClaudeTheme.statusSuccess)
                    }
                    if changes.deleted > 0 {
                        badge("D \(changes.deleted)", color: ClaudeTheme.statusError)
                    }
                }

            case .error:
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text("Failed to check status")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Spacer()
                    refreshButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ClaudeTheme.surfaceSecondary.opacity(0.5))
        .onAppear {
            startWatchingHEAD()
        }
        .onDisappear {
            stopWatchingHEAD()
        }
        .onChange(of: projectPath) { _, _ in
            // Enqueue stop/start on the next run loop tick — keeps the watcher lifecycle
            // out of the selectProject first-frame critical path.
            Task { @MainActor in
                stopWatchingHEAD()
                startWatchingHEAD()
            }
        }
        .onChange(of: appState.isStreaming(in: windowState)) { old, new in
            if old && !new { refresh() }
        }
        .task(id: projectPath) {
            let path = projectPath
            let fresh = await fetchGitStatus(at: path)
            guard !Task.isCancelled else { return }
            gitStatus = fresh
        }
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button {
            refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: ClaudeTheme.size(10)))
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .buttonStyle(.borderless)
        .help("Refresh")
    }

    // MARK: - Branch Menu

    private func branchMenu(_ currentBranch: String) -> some View {
        Menu {
            Section("Local") {
                ForEach(localBranches, id: \.self) { branch in
                    Button {
                        Task {
                            let success = await gitCheckout(branch: branch, at: projectPath)
                            if success { refresh(); loadBranches() }
                        }
                    } label: {
                        HStack {
                            Text(branch)
                            if branch == currentBranch {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(branch == currentBranch)
                }
                if localBranches.isEmpty {
                    Text("No local branches")
                }
            }

            Section("Remote (origin)") {
                ForEach(remoteBranches, id: \.self) { branch in
                    Button {
                        // Checkout remote branch and create local tracking branch
                        Task {
                            let success = await gitCheckout(branch: branch, at: projectPath)
                            if success { refresh(); loadBranches() }
                        }
                    } label: {
                        Text(branch)
                    }
                }
                if remoteBranches.isEmpty {
                    Text("No remote branches")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: ClaudeTheme.size(10)))
                Text(currentBranch)
                    .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: ClaudeTheme.size(8), weight: .semibold))
            }
            .foregroundStyle(ClaudeTheme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ClaudeTheme.surfacePrimary.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch Branch")
        .onAppear { loadBranches() }
        .onChange(of: projectPath) { _, _ in loadBranches() }
    }

    // MARK: - Branch Loading

    private func loadBranches() {
        Task {
            let result = await fetchGitBranches(at: projectPath)
            localBranches = result.local
            remoteBranches = result.remote
        }
    }

    private var currentBranchName: String? {
        switch gitStatus {
        case .clean(let branch): branch
        case .dirty(let branch, _): branch
        default: nil
        }
    }

    // MARK: - Badge

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: ClaudeTheme.size(10)))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - HEAD Watcher

    private func startWatchingHEAD() {
        let headPath = projectPath + "/.git/HEAD"
        let fd = open(headPath, O_EVTONLY)
        guard fd != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak source] in
            let data = source?.data ?? []
            refresh()
            if !data.intersection([.delete, .rename]).isEmpty {
                stopWatchingHEAD()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startWatchingHEAD()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        headWatcher = source
    }

    private func stopWatchingHEAD() {
        headWatcher?.cancel()
        headWatcher = nil
    }

    // MARK: - Refresh

    private func refresh() {
        refreshTask?.cancel()
        let path = projectPath
        refreshTask = Task {
            let fresh = await fetchGitStatus(at: path)
            guard !Task.isCancelled else { return }
            gitStatus = fresh
        }
    }
}

// MARK: - Git Status Model

enum GitStatusInfo: Sendable {
    case loading
    case notARepo
    case clean(branch: String)
    case dirty(branch: String, changes: ChangeCount)
    case error

    struct ChangeCount: Sendable {
        let modified: Int
        let added: Int
        let deleted: Int
        var total: Int { modified + added + deleted }
    }
}

// MARK: - Git Status Fetcher

private func fetchGitStatus(at path: String) async -> GitStatusInfo {
    // Run both git calls in parallel — saves the slower one's wait time (~100-250ms)
    async let branchResult = GitHelper.run(["rev-parse", "--abbrev-ref", "HEAD"], at: path)
    async let statusResult = GitHelper.run(["status", "--porcelain"], at: path)
    let (b, s) = await (branchResult, statusResult)

    guard let branchRaw = b, !branchRaw.isEmpty else { return .notARepo }
    guard let statusRaw = s else { return .error }

    let branch = branchRaw.trimmingCharacters(in: .whitespacesAndNewlines)

    if statusRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .clean(branch: branch)
    }

    let counts = parseGitStatusPorcelain(statusRaw)
    return .dirty(
        branch: branch,
        changes: .init(modified: counts.modified, added: counts.added, deleted: counts.deleted)
    )
}

// MARK: - Git Branch List

struct BranchList {
    var local: [String] = []
    var remote: [String] = []
}

private func fetchGitBranches(at path: String) async -> BranchList {
    guard let result = await GitHelper.run(["branch", "-a", "--no-color"], at: path) else {
        return BranchList()
    }

    var local: [String] = []
    var remote: [String] = []
    var localSet = Set<String>()

    for line in result.components(separatedBy: "\n") {
        var name = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("* ") { name = String(name.dropFirst(2)) }
        if name.isEmpty { continue }
        if name.contains("->") { continue }

        if name.hasPrefix("remotes/origin/") {
            let shortName = String(name.dropFirst("remotes/origin/".count))
            remote.append(shortName)
        } else {
            local.append(name)
            localSet.insert(name)
        }
    }

    // Exclude branches from remote that already exist locally
    remote = remote.filter { !localSet.contains($0) }

    return BranchList(local: local.sorted(), remote: remote.sorted())
}

// MARK: - Git Checkout

private func gitCheckout(branch: String, at path: String) async -> Bool {
    guard let _ = await GitHelper.run(["checkout", branch], at: path) else {
        return false
    }
    return true
}


#Preview {
    VStack(spacing: 0) {
        GitStatusView(projectPath: "/Users/jmlee/workspace/Clarc")
    }
    .frame(width: 400)
}
