// Modifications Copyright 2026 dttxorg (MiniClarc).
// SPDX-License-Identifier: Apache-2.0
//
// Originally: Clarc (https://github.com/ttnear/Clarc), Apache License 2.0.
// See ../../NOTICE in the repository root for the full modification history.

import SwiftUI
import ClarcCore
import ClarcChatKit

// MARK: - Settings Sheet

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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

            SlashCommandManagerView(isEmbedded: true)
                .tabItem {
                    Label("Slash Commands", systemImage: "terminal.fill")
                }
                .tag(2)

            ShortcutManagerView(isEmbedded: true)
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
    @State private var testSheetOpen = false
    @State private var viewModel = UsageSettingsViewModel()

    var body: some View {
        @Bindable var appState = appState
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                themeSection
                Divider()
                fontSizeSection
                Divider()
                notificationsSection(appState: $appState.notificationsEnabled)
                Divider()
                permissionSection(timeout: $appState.autoDenyTimeout)
                Divider()
                usageEndpointSection
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

    // MARK: - Toggle Section

    private func toggleSection(
        title: LocalizedStringKey,
        label: LocalizedStringKey,
        detail: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: ClaudeTheme.size(13)))
                    Text(detail)
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Font Size Section

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Font Size")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))
            fontSizeRow(
                label: "Interface",
                value: appState.fontSizeAdjustment,
                onDecrease: { appState.decreaseFontSize() },
                onIncrease: { appState.increaseFontSize() },
                onReset: { appState.fontSizeAdjustment = 0 }
            )
            fontSizeRow(
                label: "Messages",
                value: appState.messageFontSizeAdjustment,
                onDecrease: { appState.decreaseMessageFontSize() },
                onIncrease: { appState.increaseMessageFontSize() },
                onReset: { appState.messageFontSizeAdjustment = 0 }
            )
            Text("font.size.hint")
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)
        }
    }

    private func fontSizeRow(label: LocalizedStringKey, value: Int, onDecrease: @escaping () -> Void, onIncrease: @escaping () -> Void, onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            fontStepButton(systemName: "minus", action: onDecrease)
                .disabled(value <= ThemeStore.minFontSizeAdjustment)
            Group {
                if value == 0 {
                    Text("Default")
                } else {
                    Text(verbatim: value > 0 ? "+\(value)" : "\(value)")
                }
            }
            .font(.system(size: ClaudeTheme.size(13), weight: .medium))
            .frame(minWidth: 48, alignment: .center)
            fontStepButton(systemName: "plus", action: onIncrease)
                .disabled(value >= ThemeStore.maxFontSizeAdjustment)
            if value != 0 {
                Button("Reset", action: onReset)
                    .buttonStyle(.plain)
                    .font(.system(size: ClaudeTheme.size(12)))
                    .foregroundStyle(ClaudeTheme.accent)
            }
        }
    }

    private func fontStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 26, height: 26)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(NSColor.separatorColor), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notifications Section

    private func notificationsSection(appState: Binding<Bool>) -> some View {
        toggleSection(
            title: "Notifications",
            label: "Notify when response completes",
            detail: "Sends a system notification while Clarc is in the background.",
            isOn: appState
        )
    }

    // MARK: - Permission Section

    private func permissionSection(timeout: Binding<AutoDenyTimeout>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("Permission Auto-Deny"))
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Picker(LocalizedStringKey("Auto-deny after"), selection: timeout) {
                ForEach(AutoDenyTimeout.allCases, id: \.self) { value in
                    // Wrap in LocalizedStringKey so the localized
                    // displayName (e.g. "5 minutes" / "5 分钟") is
                    // resolved from Localizable.strings.
                    Text(LocalizedStringKey(value.displayName)).tag(value)
                }
            }
            .pickerStyle(.menu)

            Text(LocalizedStringKey("How long a pending permission request waits for your decision before Clarc denies it automatically. Choose a longer window or “Don’t auto-deny” if you step away from the keyboard."))
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Usage Endpoint Section

    /// Settings for the rate-limit / usage data source. The user picks
    /// a provider (Anthropic / MiniMax / OpenAI / Custom), and the
    /// endpoint / token / path fields adapt to that choice. Test Endpoint
    /// triggers a one-shot probe and shows the result in a sheet.
    private var usageEndpointSection: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("Usage Endpoint"))
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Picker(LocalizedStringKey("Provider"), selection: $appState.usageProvider) {
                ForEach(UsageProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: appState.usageProvider) { _, newValue in
                applyProviderDefaults(newValue, appState: appState)
            }

            Text(LocalizedStringKey("usage.provider.desc"))
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            providerFields(for: appState.usageProvider)
        }
        .sheet(isPresented: $testSheetOpen) {
            TestEndpointSheet(
                viewModel: viewModel,
                appState: appState,
                isPresented: $testSheetOpen
            )
        }
    }

    @ViewBuilder
    private func providerFields(for provider: UsageProvider) -> some View {
        @Bindable var appState = appState

        let isAnthropic = (provider == .anthropic)

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("Endpoint URL"))
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(
                    provider.endpointPlaceholder,
                    text: Binding(
                        get: { appState.usageEndpoint ?? provider.endpointPlaceholder },
                        set: { appState.usageEndpoint = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                .disabled(isAnthropic)
                .opacity(isAnthropic ? 0.55 : 1.0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("Bearer token (optional)"))
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField(
                    isAnthropic ? "OAuth" : "sk-...",
                    text: Binding(
                        get: { appState.usageEndpointBearerToken ?? "" },
                        set: { appState.usageEndpointBearerToken = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                .disabled(isAnthropic)
                .opacity(isAnthropic ? 0.55 : 1.0)
            }

            if provider == .minimax {
                Text(LocalizedStringKey("usage.minimax.note"))
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                jsonPathField(
                    label: LocalizedStringKey("5h utilization JSON path"),
                    placeholder: provider.defaultFiveHourPath ?? "five_hour.utilization",
                    bindingPath: \.usageEndpointFiveHourPath,
                    appState: appState
                )
                jsonPathField(
                    label: LocalizedStringKey("7d utilization JSON path"),
                    placeholder: provider.defaultSevenDayPath ?? "seven_day.utilization",
                    bindingPath: \.usageEndpointSevenDayPath,
                    appState: appState
                )
            }

            Button {
                testSheetOpen = true
            } label: {
                Label("Test Endpoint", systemImage: "play.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func jsonPathField(
        label: LocalizedStringKey,
        placeholder: String,
        bindingPath: ReferenceWritableKeyPath<AppState, String?>,
        appState: AppState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                .foregroundStyle(.secondary)
            TextField(
                placeholder,
                text: Binding(
                    get: { appState[keyPath: bindingPath] ?? placeholder },
                    set: { appState[keyPath: bindingPath] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
        }
    }

    private func applyProviderDefaults(_ provider: UsageProvider, appState: AppState) {
        switch provider {
        case .anthropic:
            // Clear user path overrides so the next Anthropic fetch uses
            // the built-in defaults.
            appState.usageEndpointFiveHourPath = nil
            appState.usageEndpointSevenDayPath = nil
        case .minimax:
            // usageEndpoint is `String?`; setter normalizes "" to nil.
            // Pre-fill only when the user has not typed anything.
            if appState.usageEndpoint == nil,
               let def = UsageProvider.minimax.defaultEndpoint {
                appState.usageEndpoint = def
            }
        case .openai:
            if appState.usageEndpointFiveHourPath == nil {
                appState.usageEndpointFiveHourPath = UsageProvider.openai.defaultFiveHourPath
            }
            if appState.usageEndpointSevenDayPath == nil {
                appState.usageEndpointSevenDayPath = UsageProvider.openai.defaultSevenDayPath
            }
        case .custom:
            break
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Button {
                showThemePicker.toggle()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.selectedTheme.colors.accent)
                        .frame(width: 10, height: 10)
                    Text(appState.selectedTheme.displayName)
                        .font(.system(size: ClaudeTheme.size(13)))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: ClaudeTheme.size(10)))
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
                    .font(.system(size: ClaudeTheme.size(14)))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skill Marketplace")
                        .font(.system(size: ClaudeTheme.size(13)))
                        .foregroundStyle(.primary)
                    Text("Browse and manage Claude Code skills")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: ClaudeTheme.size(11)))
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
        // MiniClarc is a hard fork of upstream ttnear/Clarc, but we don't
        // surface that in the in-app UI. The Apache 2.0 attribution and
        // upstream URL remain in `NOTICE` and `FORK.md` at the repository
        // root for anyone who audits the source distribution.
        VStack(spacing: 8) {
            Link(destination: URL(string: "https://github.com/dttxorg/MiniClarc")!) {
                linkRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Open Source",
                    subtitle: "github.com/dttxorg/MiniClarc"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func linkRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: ClaudeTheme.size(14)))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: ClaudeTheme.size(13)))
                    .foregroundStyle(.primary)
                Text(verbatim: subtitle)
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: ClaudeTheme.size(11)))
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

    // MARK: - Help Section

    private var helpSection: some View {
        Button {
            showUserManual = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "book.fill")
                    .font(.system(size: ClaudeTheme.size(14)))
                    .frame(width: 20)
                Text("User Guide")
                    .font(.system(size: ClaudeTheme.size(13)))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: ClaudeTheme.size(11)))
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
                Divider()
                foldThresholdSection
                Divider()
                autoPreviewSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Model Section

    private func modelSection(selectedModel: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Model")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Text("Used for new sessions. You can override the model per session from the toolbar.")
                .font(.system(size: ClaudeTheme.size(11)))
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
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permission Mode Section

    private var permissionModeSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Default Permission Mode")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Text("Used for new sessions. You can override the permission mode per session from the toolbar.")
                .font(.system(size: ClaudeTheme.size(11)))
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
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Effort Section

    private var effortSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Default Effort Level")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Text("Used for new sessions. You can override the effort level per session from the toolbar.")
                .font(.system(size: ClaudeTheme.size(11)))
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
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Focus Mode Section

    private var focusModeSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Focus Mode")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Text("focus.mode.desc")
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)

            Toggle(isOn: $appState.focusMode) {
                Text("Enable Focus Mode")
            }
            .toggleStyle(.switch)
            .fixedSize()
        }
    }

    // MARK: - Fold Threshold Section

    private var foldThresholdSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Fold older messages")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Picker(LocalizedStringKey("Fold older messages"), selection: $appState.foldThreshold) {
                Text("Fold: 8").tag(8)
                Text("Fold: 15").tag(15)
                Text("Fold: 30").tag(30)
                Text("Fold: Off").tag(0)
            }
            .pickerStyle(.menu)
            .fixedSize()

            Text(LocalizedStringKey("Fold threshold description"))
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Auto-Preview Attachments Section

    private var autoPreviewSection: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 12) {
            Text("Auto-preview Attachments")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))

            Text("auto.preview.desc")
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("URL links", isOn: $appState.autoPreviewSettings.url)
                Toggle("File paths", isOn: $appState.autoPreviewSettings.filePath)
                Toggle("Images", isOn: $appState.autoPreviewSettings.image)
                Toggle("Long text (200+ characters)", isOn: $appState.autoPreviewSettings.longText)
            }
            .toggleStyle(.checkbox)
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
                    .font(.system(size: ClaudeTheme.size(13)))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
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

// MARK: - Usage Settings View Model (stub; filled in by Task 12)

@MainActor
@Observable
final class UsageSettingsViewModel {
    enum TestState {
        case idle
        case running
    }
    var testState: TestState = .idle
}

private struct TestEndpointSheet: View {
    let viewModel: UsageSettingsViewModel
    let appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            Text("Test Endpoint sheet — coming next")
            Button("Close") { isPresented = false }
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - UsageProvider UI helpers

private extension UsageProvider {
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .minimax:   return "MiniMax"
        case .openai:    return "OpenAI"
        case .custom:    return "Custom"
        }
    }

    var endpointPlaceholder: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/api/oauth/usage"
        case .minimax:   return "https://www.minimaxi.com/v1/token_plan/remains"
        case .openai:    return "https://your-proxy/openai/usage"
        case .custom:    return "https://your-server/usage"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .environment(WindowState())
}
