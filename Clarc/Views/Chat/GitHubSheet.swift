import SwiftUI
import ClarcCore

struct GitHubSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss
    @State private var showLoginSheet = false
    @State private var searchText = ""
    @State private var cloningRepo: String?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("GitHub")
                    .font(.headline)
                    .foregroundStyle(ClaudeTheme.textPrimary)

                Spacer()

                if appState.isLoggedIn, let user = appState.gitHubUser {
                    Text("@\(user.login)")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)

                    Button {
                        Task { await appState.fetchRepos() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(ClaudeTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help("Refresh")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ClaudeTheme.textTertiary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ClaudeThemeDivider()

            // Content
            if appState.isLoggedIn {
                repoContent
            } else {
                connectPrompt
            }
        }
        .frame(width: 480, height: 520)
        .background(ClaudeTheme.background)
        .focusable(false)
        .task {
            if appState.isLoggedIn, appState.repos.isEmpty {
                await appState.fetchRepos()
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            GitHubLoginView()
        }
    }

    // MARK: - Connect Prompt

    private var connectPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "link.badge.plus")
                .font(.system(size: ClaudeTheme.size(40)))
                .foregroundStyle(ClaudeTheme.accent)

            Text("Connect GitHub to\nimport repos instantly")
                .font(.body)
                .foregroundStyle(ClaudeTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showLoginSheet = true
            } label: {
                Label("Connect GitHub", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(ClaudeAccentButtonStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Repo Content

    private var repoContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ClaudeTheme.textTertiary)
                TextField("Search repos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ClaudeTheme.textPrimary)
            }
            .padding(8)
            .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ClaudeThemeDivider()

            if appState.isFetchingRepos {
                loadingState
            } else if appState.repos.isEmpty {
                emptyState
            } else {
                repoListContent
            }

            ClaudeThemeDivider()

            // Footer
            HStack {
                Link("Don't see your org repos? →",
                     destination: URL(string: "https://github.com/settings/connections/applications/\(GitHubService.oauthClientId)")!)
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Loading repos...")
                .font(.subheadline)
                .foregroundStyle(ClaudeTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No repos found")
                .font(.subheadline)
                .foregroundStyle(ClaudeTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var repoListContent: some View {
        List(filteredRepos) { repo in
            repoRow(repo)
        }
        .listStyle(.plain)
    }

    private func repoRow(_ repo: GitHubRepo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.body)
                    .foregroundStyle(ClaudeTheme.textPrimary)
                    .lineLimit(1)
                Text(repo.fullName)
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if cloningRepo == repo.fullName {
                ProgressView()
                    .controlSize(.small)
            } else if isAlreadyAdded(repo) {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.statusSuccess)
            } else {
                Button {
                    Task { await cloneRepo(repo) }
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(ClaudeSecondaryButtonStyle())
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var filteredRepos: [GitHubRepo] {
        if searchText.isEmpty {
            return appState.repos
        }
        return appState.repos.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func isAlreadyAdded(_ repo: GitHubRepo) -> Bool {
        appState.projects.contains { $0.gitHubRepo == repo.fullName }
    }

    private func cloneRepo(_ repo: GitHubRepo) async {
        cloningRepo = repo.fullName
        do {
            try await appState.cloneAndAddProject(repo, in: windowState)
        } catch {
            windowState.errorMessage = "Clone failed: \(error.localizedDescription)"
            windowState.showError = true
        }
        cloningRepo = nil
    }
}

#Preview {
    GitHubSheet()
        .environment(AppState())
}
