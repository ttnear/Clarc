# Attachment Auto-Preview Settings

**Date:** 2026-04-27  
**Issue:** https://github.com/ttnear/Clarc/issues/4

## Problem

When a user pastes a URL, file path, image, or long text into the chat input, Clarc automatically converts it into an attachment preview chip. There is no way to disable this behavior per content type. Users who want a URL to remain as plain text in the message have no option to do so.

## Goal

Add per-type toggle settings that control whether pasted content is auto-converted to an attachment. When a type is disabled, pasting that content keeps it as plain text in the input field and sends it as inline text in the message.

## Scope

Four independently toggleable content types:
- **URL** — http/https links
- **File path** — local text/code file paths
- **Image** — image files (png, jpg, gif, etc.)
- **Long text** — pasted text exceeding 200 characters

## Architecture

### Data Model

New file: `Packages/Sources/ClarcCore/Models/AttachmentAutoPreviewSettings.swift`

```swift
struct AttachmentAutoPreviewSettings: Codable {
    var url: Bool = true
    var filePath: Bool = true
    var image: Bool = true
    var longText: Bool = true
}
```

All four fields default to `true` (preserves current behavior for existing users).

Stored as a single JSON blob in `UserDefaults` under key `"attachmentAutoPreviewSettings"`.

### AppState

`App/AppState.swift` — add one property:

```swift
var autoPreviewSettings: AttachmentAutoPreviewSettings = {
    // decode from UserDefaults["attachmentAutoPreviewSettings"], fallback to default
}() {
    didSet {
        // encode to UserDefaults["attachmentAutoPreviewSettings"]
    }
}
```

No `@AppStorage` wrapper needed since the value is `Codable` (not a primitive). Load/save manually via `JSONEncoder`/`JSONDecoder`.

### InputBarView

`Packages/Sources/ClarcChatKit/InputBarView.swift`

In `attachmentFromPastedText()` and `handlePasteKey()`, check settings before creating each attachment type:

| Detection branch | Guard condition |
|---|---|
| URL detected | `appState.autoPreviewSettings.url == false` → return nil, keep text |
| File path detected | `appState.autoPreviewSettings.filePath == false` → return nil, keep text |
| Image pasted | `appState.autoPreviewSettings.image == false` → skip image attachment |
| Long text detected | `appState.autoPreviewSettings.longText == false` → return nil, keep text |

When a guard fires, the pasted content is left as-is in `inputText`.

### Settings UI

`Views/SettingsView.swift` — Message tab

Add a new `Section` titled "Auto-preview Attachments":

```
Section("Auto-preview Attachments") {
    Toggle("URL links", isOn: $appState.autoPreviewSettings.url)
    Toggle("File paths", isOn: $appState.autoPreviewSettings.filePath)
    Toggle("Images", isOn: $appState.autoPreviewSettings.image)
    Toggle("Long text (200+ characters)", isOn: $appState.autoPreviewSettings.longText)
}
```

Bindings use `$appState.autoPreviewSettings.url` etc. — SwiftUI's `Bindable` on `@Observable` AppState supports nested property bindings.

## Data Flow

```
User pastes content
  → InputBarView detects type
  → checks appState.autoPreviewSettings.<type>
  → if true: create attachment chip (existing behavior)
  → if false: leave as plain text in inputText
```

Settings change:
```
User toggles in SettingsView
  → autoPreviewSettings updated on AppState
  → didSet encodes to UserDefaults
  → next paste respects new setting immediately
```

## Behavior Details

- **Default state:** all four types enabled (`true`) — zero behavior change for existing users
- **Disabled URL:** pasting `https://example.com` leaves it as text; the user can still manually add it as an attachment via drag-and-drop or file picker if those paths exist
- **Disabled image:** the image paste path in `handlePasteKey()` is skipped entirely; since clipboard images have no text representation, nothing is inserted into the input field (the paste is a no-op for that content)
- **Persistence:** settings survive app restarts via UserDefaults

## Files Changed

| File | Change |
|---|---|
| `Packages/Sources/ClarcCore/Models/AttachmentAutoPreviewSettings.swift` | New file — settings model |
| `App/AppState.swift` | Add `autoPreviewSettings` property with UserDefaults load/save |
| `Packages/Sources/ClarcChatKit/InputBarView.swift` | Guard attachment creation with settings flags |
| `Views/SettingsView.swift` | Add toggles section in Message tab |

## Out of Scope

- Per-file-extension granularity (e.g., disable preview only for `.md` files)
- Retroactively changing already-sent messages
- Disabling attachment creation via drag-and-drop (only paste is affected)
