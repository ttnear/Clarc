# Task Update UI (Codex-style Phase Cards) Design

**Date:** 2026-06-02

## Problem

Today, assistant/tool output renders as a flat text stream. Long output stays expanded, there is no visual structure between phases of work, and there is no per-phase timing. The Codex CLI solves this with collapsible "TaskUpdate" cards: each phase is one card, with a title, status icon, summary, duration, and an expandable detail region (description, file changes, test results).

## Goal

Add a per-phase task-update card system that:

- Renders each phase as a single self-contained card (not wrapped in a normal assistant bubble)
- Tracks lifecycle (running / done / failed) with start/end times and a duration
- Auto-runs when the model's streamed text contains a `task_update` JSON or XML block, AND when Swift code explicitly calls `store.start/finish`
- Renders running phases with a live ticking duration; done/failed phases with a frozen duration
- Default-expands running and failed phases; default-collapses done phases
- Remembers a user's manual expand/collapse choice for the rest of the session
- Survives Codable round-trips of old messages without crashing

## Non-Goals

- Server-side timing of phases (this is a UI layer; timing happens locally)
- Replacing the existing `MessageBubble` text rendering — the new cards live alongside it, not in place of it
- Markdown rendering of `details` (the spec allows plain text with newlines preserved; a future task can add `MarkdownContentView` integration)
- Cross-session persistence of manual expand/collapse choices

## Architecture

### Module Layout

| Path | Responsibility |
|---|---|
| `Packages/Sources/ClarcCore/Models/TaskUpdateMessage.swift` | `TaskUpdateStatus`, `TaskUpdateMessage`, `TaskFileChange`, `TaskTestResult`; `formatDuration(_:)` helper |
| `Packages/Sources/ClarcCore/Models/ChatMessage.swift` | Extend `MessageBlock` with `taskUpdate: TaskUpdateMessage?` + `isTaskUpdate` predicate + `static func .taskUpdate(_:)` |
| `Clarc/Stores/TaskProgressStore.swift` | `@MainActor` store: `start/update/finish/fail/upsert`; `tasks` dict; `manualExpansion` dict |
| `Clarc/Parsing/TaskUpdateParser.swift` | JSON + XML parsers + `extract(from:)` text scanner |
| `Clarc/Views/TaskUpdateCard.swift` | Single-card view (header, details, files, tests) |
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | Add `if let taskUpdate = block.taskUpdate` branch in the `ForEach(visibleBlocks)` loop |

### Tests

| Path | Coverage |
|---|---|
| `Packages/Tests/ClarcCoreTests/TaskUpdateMessageTests.swift` | `formatDuration` cases (5, 65, 3660, 0, -1); Codable round-trip; default fields; done-state auto-duration |
| `Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift` | JSON parse; XML parse; `extract` for code-fence / bare object / XML; negative cases (plain text, no `type` field) |
| `Packages/Tests/ClarcCoreTests/TaskProgressStoreTests.swift` | start / update / finish / fail; same-id upsert preserves startTime; running→done writes duration; `isExpanded` default + override |

## Data Model

### `TaskUpdateMessage`

```swift
public enum TaskUpdateStatus: String, Codable, Sendable, CaseIterable {
    case running
    case done
    case failed
}

public struct TaskUpdateMessage: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var details: String
    public var status: TaskUpdateStatus
    public var startTime: Date
    public var endTime: Date?
    public var durationSeconds: TimeInterval?
    public var filesChanged: [TaskFileChange]
    public var testResults: [TaskTestResult]

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        details: String = "",
        status: TaskUpdateStatus = .running,
        startTime: Date = Date(),
        endTime: Date? = nil,
        durationSeconds: TimeInterval? = nil,
        filesChanged: [TaskFileChange] = [],
        testResults: [TaskTestResult] = []
    ) { ... }
}

public struct TaskFileChange: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var path: String
    public var additions: Int?
    public var deletions: Int?
    public var changeType: String?
}

public struct TaskTestResult: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var status: String
    public var durationSeconds: TimeInterval?
    public var output: String?
}
```

`formatDuration(_:)` lives in this file as a public free function:

```swift
public func formatDuration(_ seconds: TimeInterval) -> String {
    let clamped = max(0, seconds)
    let s = Int(clamped)
    if s < 60 { return "\(s)s" }
    if s < 3600 {
        return "\(s / 60)m \(s % 60)s"
    }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}
```

### `MessageBlock` extension

Add the field, predicate, and factory alongside the existing `text` / `toolCall` / `thinking` family. CodingKeys / init(from:) / encode(to:) all gain `taskUpdate`. Old messages without the field decode unchanged.

```swift
public var taskUpdate: TaskUpdateMessage?
public var isTaskUpdate: Bool { taskUpdate != nil }

public static func taskUpdate(_ update: TaskUpdateMessage) -> MessageBlock {
    MessageBlock(id: UUID().uuidString, taskUpdate: update)
}
```

## `TaskProgressStore`

`@MainActor final class ObservableObject`. Two pieces of internal state:

```swift
@Published private(set) var tasks: [UUID: TaskUpdateMessage] = [:]
@Published private(set) var manualExpansion: [UUID: Bool] = [:]
```

`tasks` is the source of truth for "have we already seen this id?" — it is **not** a render source. Render reads from `MessageBlock.taskUpdate` (which lives in `ChatMessage.blocks`). The store exists so the stream layer can ask "should I append a new block or update an existing one?" and so Swift code outside the stream can drive the lifecycle.

### API

```swift
func start(title: String, summary: String) -> UUID
func update(id: UUID, summary: String?, details: String?, filesChanged: [TaskFileChange]?, testResults: [TaskTestResult]?)
func finish(id: UUID, summary: String?, details: String?, status: TaskUpdateStatus)
func fail(id: UUID, summary: String?, details: String?)

/// Used by the parser path. Returns whether the id is new AND the
/// merged `TaskUpdateMessage` (with startTime preserved on update).
func upsert(_ update: TaskUpdateMessage) -> (wasNew: Bool, merged: TaskUpdateMessage)

func isExpanded(_ update: TaskUpdateMessage) -> Bool
func setExpanded(_ expanded: Bool, for id: UUID)
```

### Behavior

- `start(title:summary:)` creates a `TaskUpdateMessage` with `status: .running`, `startTime: Date()`, a fresh UUID, and stores it in `tasks`. Returns the id.
- `update(id:summary:details:filesChanged:testResults:)` only fills in non-nil arguments; leaves the rest of the existing `TaskUpdateMessage` intact. The status stays as-is (typically `.running`).
- `finish(id:summary:details:status:)` sets `endTime = Date()`, computes `durationSeconds = endTime - startTime`, applies the (optional) new `summary` and `details`, sets `status`.
- `fail(id:summary:details:)` is `finish(id:summary:details:status: .failed)`.
- `upsert(_:)`:
  - If `tasks[update.id]` exists → copy `startTime` from the existing entry, recompute `durationSeconds` if `status != .running` and `endTime != nil`, replace.
  - Otherwise → store as-is.
  - Returns `(wasNew, merged)`.
- `isExpanded(_:)`:
  - If `manualExpansion[update.id]` is set → use it.
  - Else: `update.status == .running` or `.failed` → `true`; `.done` → `false`.
- `setExpanded(_:for:)` writes into `manualExpansion`.

## Parser

`enum TaskUpdateParser` (non-instantiable, static methods).

### `extract(from: String) -> (updates: [TaskUpdateMessage], remaining: String)`

Tries three extractors, in order, and removes the matched spans from the input:

1. **Code-fence JSON** — `` ```json ... ``` `` blocks (greedy backticks; one block per fence). Parse the inner text as a JSON object. If the parsed object's `type` field is `"task_update"`, keep the parsed `TaskUpdateMessage` and remove the entire fence (including backticks).
2. **XML block** — `<task-update ...>...</task-update>` fragments (non-greedy). Hand the fragment to `parse(xmlFragment:)`. On success, keep the parsed message and remove the fragment.
3. **Bare JSON object** — top-level `{ "type": "task_update", ... }` outside fences. Find the matching brace via simple depth counting (skipping strings, respecting escapes). If the parsed object is a `task_update`, keep it and remove the brace range.

Plain text that does not match any of the three patterns passes through unchanged in `remaining`.

**Order matters**: extractors run in the order above, each operating on the running `remaining` from the previous step. So a JSON object inside a code fence is not double-extracted.

The method is pure: it does not mutate the store or any other state. The caller (`AppState.processStream`) is responsible for routing parsed updates through `store.upsert` and into the message's `blocks`.

### `parse(jsonObject: JSONValue) -> TaskUpdateMessage?`

Reuses the existing `ClarcCore/Models/JSONValue.swift` enum. Field mapping:

| JSON key | Target field | Behavior |
|---|---|---|
| `id` (string) | `id` | `UUID(uuidString:)`; nil → new `UUID()` |
| `title` (string) | `title` | Required — nil/missing → return nil (reject) |
| `summary` (string) | `summary` | Default `""` |
| `details` (string) | `details` | Default `""` |
| `status` (string) | `status` | Parse to `TaskUpdateStatus`; unknown → `.running` |
| `startTime` (string ISO8601) | `startTime` | `ISO8601DateFormatter`; parse fail → `Date()` |
| `endTime` (string ISO8601) | `endTime` | Parse fail or missing → nil |
| `durationSeconds` (number) | `durationSeconds` | Default nil |
| `filesChanged` (array) | `filesChanged` | Each dict → `TaskFileChange`; bad entries skipped |
| `testResults` (array) | `testResults` | Each dict → `TaskTestResult`; bad entries skipped |

If `status == .done` and `endTime` is set and `durationSeconds` is nil, the parser computes `durationSeconds = endTime - startTime` so historical JSON produces a usable duration.

### `parse(xmlFragment: String) -> TaskUpdateMessage?`

Foundation `XMLParser` (NSObject-based, wrapped in a `TaskUpdateXMLDelegate`). Schema:

```xml
<task-update id="..." title="..." status="running">
  <summary>...</summary>
  <details>...</details>
  <filesChanged>
    <file path="..." changeType="added" additions="120" deletions="4"/>
  </filesChanged>
  <testResults>
    <test name="..." status="passed" durationSeconds="3.2"/>
  </testResults>
</task-update>
```

- `id` / `title` / `status` from element attributes
- `<summary>` / `<details>` from element text content
- `<filesChanged><file .../></filesChanged>` from each `<file>` child's attributes
- `<testResults><test .../></testResults>` from each `<test>` child's attributes
- All `Int?` / `TimeInterval?` attribute parsing uses `Int(s)` / `Double(s)`; nil/empty → nil
- Missing `title` → return nil
- `status` unknown → `.running`

## `TaskUpdateCard` UI

```swift
struct TaskUpdateCard: View {
    let update: TaskUpdateMessage
    @Binding var isExpanded: Bool
    @State private var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                if !update.details.isEmpty { detailsSection }
                if !update.filesChanged.isEmpty { filesSection }
                if !update.testResults.isEmpty { testsSection }
            }
        }
        ...
        .onReceive(timer) { _ in
            if update.status == .running { now = Date() }
        }
    }
}
```

### Layout

- Outer container: 12-point padding, 12-point corner radius, `Color(nsColor: .controlBackgroundColor)` background, 0.5-pt `Color(nsColor: .separatorColor)` border
- Spans nearly the full message column width (no left/right bubble insets)

### Header (always visible)

`HStack`: status icon · title (semibold) · Spacer · summary (secondary text, single line) · duration (monospaced digit) · chevron (up if expanded, down otherwise)

Status icons:
- `.running` — `ProgressView()` (small, system style)
- `.done` — `checkmark.circle.fill`, `ClaudeTheme.statusSuccess`
- `.failed` — `xmark.circle.fill`, `ClaudeTheme.statusWarning` (or system red)

Title and summary share a row at the top; duration is right-aligned next to the chevron.

### Live duration

```swift
private var liveDuration: TimeInterval {
    switch update.status {
    case .running:
        return now.timeIntervalSince(update.startTime)
    case .done, .failed:
        return update.durationSeconds
            ?? update.endTime?.timeIntervalSince(update.startTime)
            ?? 0
    }
}
```

Timer fires every 1 s on the main run loop, but only mutates `now` when the card is `.running`. The header re-renders with the new duration.

### Details section (expanded only)

`details` rendered as a `Text` with `.font(.system(size: ..., design: .monospaced))` and `fixedSize(horizontal: false, vertical: true)` to preserve newlines. No markdown rendering in this iteration.

### Files section (expanded only, hidden if empty)

`VStack` of one row per `TaskFileChange`:

```
HStack {
  Image(systemName: fileIcon(for: changeType)) // doc / doc.badge.plus / minus / pencil
  Text(change.path).font(.system(size: 11, design: .monospaced))
  Spacer()
  if let a = change.additions { Text("+\(a)").foregroundStyle(.green) }
  if let d = change.deletions { Text("-\(d)").foregroundStyle(.red) }
}
```

### Tests section (expanded only, hidden if empty)

`VStack` of one row per `TaskTestResult`:

```
HStack {
  Image(systemName: testIcon(for: result.status)) // checkmark / xmark / minus
  Text(result.name)
  Spacer()
  if let dur = result.durationSeconds { Text(formatDuration(dur)) }
}
```

Plus a footer line: "X passed / Y failed" counts.

## `MessageBubble` integration

Add an `if let taskUpdate = block.taskUpdate` branch inside the existing `ForEach(visibleBlocks)` loop. The card receives a `Binding<Bool>` wired through `TaskProgressStore`:

```swift
if let taskUpdate = block.taskUpdate,
   let store = windowState.taskProgressStore {
    TaskUpdateCard(
        update: taskUpdate,
        isExpanded: Binding(
            get: { store.isExpanded(taskUpdate) },
            set: { store.setExpanded($0, for: taskUpdate.id) }
        )
    )
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

`WindowState` gains a `taskProgressStore: TaskProgressStore` property (initialized in `WindowState.init`). This avoids putting the store on `AppState` (which would couple every project's chat to one shared instance).

## `AppState` integration

### Where the store lives

One `TaskProgressStore` is created per `WindowState`. `AppState` does not hold a store directly; instead, `processStream` receives a `WindowState` and reads the store off it.

### Stream-time extraction

In `AppState.processStream`, just before `tail.messages[idx].appendText(buffered)`:

```swift
let (extracted, remaining) = TaskUpdateParser.extract(from: buffered)
for parsed in extracted {
    let (wasNew, merged) = store.upsert(parsed)
    if wasNew {
        msg.blocks.append(.taskUpdate(merged))
    } else if let idx = msg.blocks.firstIndex(where: { $0.taskUpdate?.id == merged.id }) {
        msg.blocks[idx].taskUpdate = merged
    }
}
buffered = remaining
msg.appendText(buffered)
```

`wasNew == false` means a previous `running` card for the same id was already in the message — we replace it in place to preserve SwiftUI identity. The new value is the `merged` one (with original `startTime` preserved by the store).

### Tool-direct path

`TaskProgressStore` is reachable through `bridge.taskProgressStore` (exposed on `ChatBridge`). Tools and other Swift code can call `bridge.taskProgressStore?.start(...)` / `finish(...)` without going through the parser. This is the path for the local "drive a card from Swift" use case.

## Compatibility

- Old `MessageBlock` JSON without `taskUpdate` decodes unchanged (`decodeIfPresent` + nil).
- Old `ChatMessage` JSON (using `content` / `toolCalls`) continues to flow through the existing migration path in `init(from:)`.
- New cards' persistence is the same `ChatMessage.blocks` JSON array, just with one more optional field per block.
- `formatDuration` clamps negative input to `0s` so a clock skew on the wire can't produce a "−3s" UI.
- Running cards persist with `endTime == nil` / `durationSeconds == nil`; on reload the live timer picks up from `startTime` and the user sees the card resume ticking.

## File Changes

### New
- `Packages/Sources/ClarcCore/Models/TaskUpdateMessage.swift`
- `Clarc/Stores/TaskProgressStore.swift`
- `Clarc/Parsing/TaskUpdateParser.swift`
- `Clarc/Views/TaskUpdateCard.swift`
- `Packages/Tests/ClarcCoreTests/TaskUpdateMessageTests.swift`
- `Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift`
- `Packages/Tests/ClarcCoreTests/TaskProgressStoreTests.swift`

### Modified
- `Packages/Sources/ClarcCore/Models/ChatMessage.swift` — extend `MessageBlock` + Codable migration path
- `Packages/Sources/ClarcChatKit/MessageBubble.swift` — add card-render branch in `ForEach(visibleBlocks)`
- `Clarc/App/WindowState.swift` — add `taskProgressStore` property
- `Clarc/App/AppState.swift` — call `TaskUpdateParser.extract` before `appendText` in `processStream`; route parsed updates through `store.upsert` and into `msg.blocks`
- `Packages/Sources/ClarcChatKit/ChatBridge.swift` — expose `taskProgressStore` for tool-direct access

## Testing

- Library + parser + store tests run via `swift test --filter` on the `ClarcCore` target.
- The card view itself is exercised manually in Xcode (the spec allows this; there's no UI test target).
- Manual matrix after build:
  1. Assistant streams text containing ```` ```json { "type": "task_update", ... } ``` ```` → a card appears mid-message, then mutates in place on a follow-up with the same id and `status: "done"`.
  2. Assistant streams text containing `<task-update ...>...</task-update>` → same flow, XML path.
  3. Tool calls `bridge.taskProgressStore?.start(...)` / `finish(...)` directly → a card appears/disappears in the assistant's response.
  4. Click chevron on a `.done` card → expands; click again → collapses; navigate away and back within the same session → the manual choice is remembered.
  5. Reload the conversation (Codable round-trip) → cards re-render with the right state; running cards resume ticking.
  6. Old message (no `taskUpdate` field anywhere) → still renders as text, no crash.

## Open Items

- None. The spec'd JSON and XML formats are both implemented; the spec explicitly allowed skipping XML but the user opted to include it.
