# Clarc

**The terminal was for the few. Clarc is for everyone.**

Clarc is a lightweight native macOS desktop client for Claude Code. It brings the CLI agent workflow into a project-centric GUI with streaming chat, repository switching, file browsing, Git status, permissions, terminal access, and per-project notes.

![Platform](https://img.shields.io/badge/platform-macOS%2015.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.x-orange)
![Version](https://img.shields.io/badge/version-1.2.0-blue)
![License](https://img.shields.io/badge/license-Apache%202.0-green)

---

## Screenshots

![Clarc Screenshot](docs/screenshot.png)

---

## Why Clarc?

The terminal is a wall. For most people who aren't developers, it's a closed door — install a CLI, generate SSH keys, approve every tool call without a real preview of what it's about to do. None of that is hard for engineers; all of it is hard for everyone else. The terminal was for the few, and it still is.

Clarc was built so my non-developer coworkers could use Claude Code without learning a shell first. It doesn't reinvent the agent. It spawns the real `claude` CLI underneath, so your `CLAUDE.md`, skills, MCP servers, and slash commands keep working as-is. What sits on top is a native Mac app:

- Approval modals that surface the actual diff before any tool runs, with risk-aware Allow / Allow Session / Deny options.
- Per-project windows you can run in parallel — switch tabs, double-click to spin off a window, keep streams alive in the background.
- Drag-and-drop attachments, smart paste for images, file paths, URLs, and long text.
- GitHub OAuth that handles SSH key setup for you, so `git clone` just works.
- An inspector with a file tree, Git status, embedded terminal, and a per-project memo pad.

Same engine, no terminal required.

---

## Key Features vs. Claude Desktop

| Clarc feature | Why it matters |
|---------------|----------------|
| **Native macOS app** | Built with SwiftUI, not Electron. The current v1.2.0 release is about 5.6 MB to download and about 13 MB unpacked, without bundling a browser runtime. |
| **Project-centric workspace** | Register multiple local repositories, switch between them from project tabs, or open a project in its own window for parallel sessions. In-progress streams keep running in the background while you switch. |
| **Custom slash commands** | Add, edit, hide, disable, import, and export slash commands. Customizations are stored locally and can be backed up or shared as JSON. |
| **Shortcut buttons** | Create quick buttons for prompts or terminal commands you run repeatedly. Terminal-command shortcuts can launch directly into Clarc's interactive terminal popup. |
| **Built-in file explorer with Git status** | Browse and search project files, toggle hidden files, preview or edit files, inspect Git status, and switch branches from the sidebar. |
| **Rich-text memo pad per project** | Keep project-specific notes in the inspector panel with headings, lists, checkboxes, links, and Markdown copy/paste support. |
| **Embedded terminal** | Use a SwiftTerm-based terminal in the inspector, plus interactive terminal popups for commands such as `/config`, `/permissions`, and `/model`. |

---

## Features

| Feature | Description |
|---------|-------------|
| **Streaming Chat** | Real-time Claude Code conversations with Markdown rendering, tool call visualization, diff views, and error bubbles for failed empty responses. |
| **Multi-Project Workspace** | Register local folders or GitHub repositories, switch freely, and keep per-project session history. |
| **Dedicated Project Windows** | Double-click a project tab to open it in an independent window and work across multiple repositories at once. |
| **Per-Session Controls** | Choose model, permission mode, and effort level per session from the chat toolbar. Defaults are configurable in Settings. |
| **Permission Modes** | Ask, Accept Edits, Plan, Auto, and Bypass modes mirror Claude Code's permission model and can be changed from the toolbar. |
| **Permission Management** | Risk-based approve/deny UI with Allow, Allow Session, Deny, and 5-minute auto-deny handling. |
| **Effort Levels** | Auto, Low, Medium, High, XHigh, and Max reasoning controls for each session. |
| **Model Selection** | Claude Code aliases with localized descriptions, including Opus, Sonnet, Haiku, 1M context, and plan variants. |
| **File Attachments** | Drag-and-drop files and images. Smart paste detects images, file paths, URLs, and long text. |
| **Attachment Auto-Preview Settings** | Toggle automatic preview chips separately for URLs, file paths, images, and long text. |
| **Slash Commands** | Built-in and custom command system with default-command edits, reset, JSON import, and JSON export. |
| **Shortcut Buttons** | Configurable quick-access buttons for frequent prompts and terminal commands. |
| **Message Queue** | Queue messages while Claude is responding; cancel queued items with ESC or the remove button. |
| **Status Line** | Project path, model, 5-hour and 7-day rate limits, context usage, and response time at a glance. |
| **Built-in Terminal** | SwiftTerm-powered inspector terminal with reset support, plus full interactive terminal sheets. |
| **File Explorer** | Project file tree with search, hidden-file toggle, syntax-highlighted preview, file editing, and `@path` insertion. |
| **Git Status** | Sidebar Git status summary with changed-file counts, branch display, and local/remote branch switching. |
| **GitHub Integration** | OAuth device flow, Keychain token storage, SSH key management, repository browsing, and cloning. |
| **Memo Panel** | Per-project rich-text memo pad with headings, lists, checkboxes, links, and persistent storage. |
| **Skill Marketplace** | Browse and install official Anthropic plugins, refreshed with a 5-minute cache. |
| **Themes and Font Controls** | Six accent themes plus independent font size controls for the interface and message area. |
| **Focus Mode** | Optional focused chat layout that can be enabled from Settings. |
| **Notifications** | Optional system notifications with response previews while Clarc is in the background. |
| **Localization** | Full English and Korean UI. |
| **User Guide** | Built-in in-app help guide accessible from the toolbar and Settings. |
| **Auto-update** | Sparkle-based update checking on launch, with manual checks from the app menu. |

---

## Requirements

- **macOS 15.0** or later
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)** installed and authenticated
- **Xcode with Swift 6.2+ toolchain** for building the current source tree

---

## Installation

1. Download the latest `Clarc-x.y.z.zip` from the [Releases](https://github.com/ttnear/Clarc/releases) page.
2. Unzip and move `Clarc.app` to your `Applications` folder.
3. Launch `Clarc.app`.

### First Launch on macOS 15 (Sequoia)

macOS Sequoia blocks the first launch of any downloaded app, even notarized ones, and routes approval through System Settings instead of the old right-click -> Open flow.

When you see **"Apple could not verify 'Clarc.app' is free of malware..."**:

1. Click **Done** on the dialog.
2. Open **System Settings -> Privacy & Security**.
3. Scroll to the Security section and click **Open Anyway** next to `Clarc.app`.
4. Confirm with your password or Touch ID.

After this one-time approval, Clarc launches normally. The app is signed with a Developer ID certificate and notarized by Apple. This prompt is standard macOS behavior, not a security warning specific to Clarc.

---

## Build from Source

```bash
open Clarc.xcodeproj
```

For a CLI build:

```bash
xcodebuild -project Clarc.xcodeproj -scheme Clarc -configuration Debug build
```

For tests:

```bash
xcodebuild test -project Clarc.xcodeproj -scheme Clarc -destination 'platform=macOS'
swift test --package-path Packages
```

For a signed release ZIP, use the release scripts under `scripts/`.

---

## Project Structure

| Path | Purpose |
|------|---------|
| `Clarc/` | macOS app target: app entry point, views, services, resources, and integrations. |
| `Packages/Sources/ClarcCore/` | Shared models, theme, utilities, Git helpers, and pure core logic. |
| `Packages/Sources/ClarcChatKit/` | Reusable chat UI, message rendering, input bar, slash commands, shortcuts, diffs, and status line. |
| `ClarcTests/` | App-level XCTest coverage. |
| `Packages/Tests/` | Swift Testing coverage for core utilities. |
| `release_notes/` | Human-readable release notes used for publishing. |
| `scripts/` | Build, notarization, Sparkle signing, and release automation. |

---

## License

Apache License 2.0. See the [LICENSE](LICENSE) file for details.
