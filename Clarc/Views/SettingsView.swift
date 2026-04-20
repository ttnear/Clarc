import SwiftUI
import ClarcCore
import ClarcChatKit

// MARK: - Settings Sheet

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let projectName: String

    @State private var selectedTab = 0
    @State private var showUserManual = false

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(showUserManual: $showUserManual)
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }
                .tag(0)

            ChatSettingsTab()
                .tabItem {
                    Label("Message", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(1)

            SlashCommandManagerView(projectName: projectName, isEmbedded: true)
                .tabItem {
                    Label("Slash Commands", systemImage: "terminal.fill")
                }
                .tag(2)

            ShortcutManagerView(projectName: projectName, isEmbedded: true)
                .tabItem {
                    Label("Shortcuts", systemImage: "bolt.fill")
                }
                .tag(3)
        }
        .frame(width: 680, height: 620)
        .focusable(false)
        .onAppear { selectedTab = 0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.title == "Settings" else { return }
            selectedTab = 0
        }
        .onDisappear {
            windowState.registryVersion += 1
        }
        .sheet(isPresented: $showUserManual) {
            UserManualView()
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Binding var showUserManual: Bool
    @State private var showSkillMarket = false
    @State private var showThemePicker = false

    var body: some View {
        @Bindable var appState = appState
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                themeSection
                Divider()
                notificationsSection(appState: $appState.notificationsEnabled)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    skillMarketSection
                    helpSection
                    sourceCodeSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Notifications Section

    private func notificationsSection(appState: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications")
                .font(.system(size: 13, weight: .semibold))

            Toggle(isOn: appState) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify when response completes")
                        .font(.system(size: 13))
                    Text("Sends a system notification while Clarc is in the background.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.system(size: 13, weight: .semibold))

            Button {
                showThemePicker.toggle()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.selectedTheme.colors.accent)
                        .frame(width: 10, height: 10)
                    Text(appState.selectedTheme.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showThemePicker, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemePickerRow(
                            theme: theme,
                            isSelected: appState.selectedTheme == theme
                        ) {
                            appState.selectedTheme = theme
                            showThemePicker = false
                        }
                    }
                }
                .padding(4)
                .frame(minWidth: 220)
                .focusable(false)
            }
        }
    }

    // MARK: - Skill Market Section

    private var skillMarketSection: some View {
        Button {
            showSkillMarket = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skill Marketplace")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Text("Browse and manage Claude Code skills")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSkillMarket) {
            SkillMarketView(isEmbedded: false)
        }
    }

    // MARK: - Source Code Section

    private var sourceCodeSection: some View {
        Link(destination: URL(string: "https://github.com/ttnear/Clarc")!) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 14))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open Source")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Text(verbatim: "github.com/ttnear/Clarc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Help Section

    private var helpSection: some View {
        Button {
            showUserManual = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "book.fill")
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text("User Guide")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Settings Tab

struct ChatSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modelSection(selectedModel: $appState.selectedModel)
                Divider()
                permissionModeSection
                Divider()
                effortSection
                Divider()
                focusModeSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Model Section

    private func modelSection(selectedModel: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Model")
                .font(.system(size: 13, weight: .semibold))

            Text("Used for new sessions. You can override the model per session from the toolbar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Picker("", selection: selectedModel) {
                ForEach(AppState.availableModels, id: \.self) { model in
                    Text(AppState.modelDisplayName(model)).tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Text(AppState.modelDescription(selectedModel.wrappedValue))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permission Mode Section

    private var permissionModeSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Default Permission Mode")
                .font(.system(size: 13, weight: .semibold))

            Text("Used for new sessions. You can override the permission mode per session from the toolbar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Picker("", selection: $appState.permissionMode) {
                ForEach(PermissionMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.displayName)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Text(AppState.permissionModeDescription(appState.permissionMode))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Effort Section

    private var effortSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Default Effort Level")
                .font(.system(size: 13, weight: .semibold))

            Text("Used for new sessions. You can override the effort level per session from the toolbar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Picker("", selection: $appState.selectedEffort) {
                Text("Auto").tag("auto")
                ForEach(AppState.availableEfforts, id: \.self) { effort in
                    Text(effortDisplayName(effort)).tag(effort)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Text(AppState.effortDescription(appState.selectedEffort))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Focus Mode Section

    private var focusModeSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Focus Mode")
                .font(.system(size: 13, weight: .semibold))

            Text("focus.mode.desc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Toggle(isOn: $appState.focusMode) {
                Text("Enable Focus Mode")
            }
            .toggleStyle(.switch)
            .fixedSize()
        }
    }

    private func effortDisplayName(_ effort: String) -> String {
        switch effort {
        case "low":    return "Low"
        case "medium": return "Medium"
        case "high":   return "High"
        case "xhigh":  return "Extra High"
        case "max":    return "Max"
        default:       return effort.capitalized
        }
    }
}

// MARK: - Theme Picker Row

private struct ThemePickerRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.colors.accent)
                    .frame(width: 10, height: 10)
                Text(theme.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color(NSColor.selectedContentBackgroundColor).opacity(0.5) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    SettingsView(projectName: "MyProject")
        .environment(AppState())
        .environment(WindowState())
}
