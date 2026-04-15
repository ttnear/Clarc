import SwiftUI
import ClarcCore
import UniformTypeIdentifiers

struct ProjectListView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var showFilePicker = false
    @State private var projectToDelete: Project? = nil
    @State private var projectToRename: Project? = nil
    @State private var renameText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            List(appState.projects, selection: selectedProjectBinding) { project in
                projectRow(project)
                    .tag(project.id)
                    .contextMenu {
                        Button {
                            renameText = project.name
                            projectToRename = project
                        } label: {
                            Label("Rename Project", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            projectToDelete = project
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                        }
                    }
            }
            .listStyle(.sidebar)
            .confirmationDialog(
                "Delete \"\(projectToDelete?.name ?? "")\"?",
                isPresented: Binding(
                    get: { projectToDelete != nil },
                    set: { if !$0 { projectToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let project = projectToDelete {
                        Task { await appState.deleteProject(project, in: windowState) }
                    }
                    projectToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    projectToDelete = nil
                }
            } message: {
                Text("This will remove the project from Clarc. The files on disk will not be deleted.")
            }
            .sheet(item: $projectToRename) { project in
                RenameProjectSheet(name: $renameText) {
                    Task { await appState.renameProject(project, to: renameText) }
                }
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Projects")
                .font(.headline)

            Spacer()

            Button {
                showFilePicker = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add Project")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
        }
    }

    // MARK: - Project Row

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.body)
                        .lineLimit(1)
                }

                Text(truncatedPath(project.path))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var selectedProjectBinding: Binding<UUID?> {
        Binding<UUID?>(
            get: { windowState.selectedProject?.id },
            set: { id in
                if let id,
                   let project = appState.projects.first(where: { $0.id == id }) {
                    Task { await appState.selectProject(project, in: windowState) }
                }
            }
        )
    }

    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    private func truncatedPath(_ path: String) -> String {
        if path.hasPrefix(Self.homePath) {
            return "~" + path.dropFirst(Self.homePath.count)
        }
        return path
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else { return }

        Task {
            await appState.addProjectFromFolder(url, in: windowState)
        }
    }
}

// MARK: - Rename Sheet

struct RenameProjectSheet: View {
    @Binding var name: String
    @Environment(\.dismiss) private var dismiss
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Project")
                .font(.headline)

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { confirm() }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Rename") { confirm() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }

    private func confirm() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onConfirm()
        dismiss()
    }
}

#Preview {
    ProjectListView()
        .environment(AppState())
        .frame(width: 260)
}
