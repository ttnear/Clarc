# Task Update UI (Codex-style Phase Cards) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Codex-style per-phase task-update cards to the chat UI: a `TaskUpdateMessage` model, a JSON+XML parser, a `@MainActor` store, a SwiftUI card view with live duration, and wire it into `MessageBubble` + `AppState.processStream`.

**Architecture:** Extend `MessageBlock` with a `taskUpdate: TaskUpdateMessage?` field. A new `TaskProgressStore` tracks lifecycle and manual expand/collapse state. `TaskUpdateParser` extracts `task_update` JSON/XML from streaming text. `TaskUpdateCard` renders the card and drives a 1-second ticker for running phases. `AppState` runs the parser before `appendText` and routes updates into the message's blocks.

**Tech Stack:** Swift 6.2, SwiftUI, Foundation `XMLParser`, Swift Testing (`@Test`).

---

## File Structure

### New files (ClarcCore)

| Path | Responsibility |
|---|---|
| `Packages/Sources/ClarcCore/Models/TaskUpdateMessage.swift` | `TaskUpdateStatus` + `TaskUpdateMessage` + `TaskFileChange` + `TaskTestResult` + `formatDuration(_:)` |
| `Packages/Sources/ClarcCore/Stores/TaskProgressStore.swift` | `@MainActor ObservableObject` — `start/update/finish/fail/upsert/isExpanded` |
| `Packages/Sources/ClarcCore/Parsing/TaskUpdateParser.swift` | JSON + XML parsers + `extract(from:)` text scanner |

### New files (ClarcChatKit)

| Path | Responsibility |
|---|---|
| `Packages/Sources/ClarcChatKit/Views/TaskUpdateCard.swift` | SwiftUI card view (header, details, files, tests) |

### New tests

| Path | Coverage |
|---|---|
| `Packages/Tests/ClarcCoreTests/TaskUpdateMessageTests.swift` | `formatDuration` cases; Codable; default fields; done-state auto-duration |
| `Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift` | JSON; XML; `extract` for code-fence / bare object / XML; negative cases |
| `Packages/Tests/ClarcCoreTests/TaskProgressStoreTests.swift` | lifecycle; same-id upsert preserves startTime; running→done writes duration; expansion defaults + override |

### Modified files

| Path | Change |
|---|---|
| `Packages/Sources/ClarcCore/Models/ChatMessage.swift` | `MessageBlock` gains `taskUpdate: TaskUpdateMessage?` + `isTaskUpdate` + `static func .taskUpdate(_:)`; Codable migration |
| `Packages/Sources/ClarcCore/WindowState.swift` | Add `taskProgressStore: TaskProgressStore` |
| `Packages/Sources/ClarcChatKit/ChatBridge.swift` | Expose `taskProgressStore` accessor |
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | Render `TaskUpdateCard` in the `ForEach(visibleBlocks)` loop |
| `Clarc/App/AppState.swift` | In `processStream`, run `TaskUpdateParser.extract` before `appendText`; route through `store.upsert` into `msg.blocks` |

---

## Task 1: `TaskUpdateMessage` model + `formatDuration`

**Files:**
- Create: `Packages/Sources/ClarcCore/Models/TaskUpdateMessage.swift`
- Test: `Packages/Tests/ClarcCoreTests/TaskUpdateMessageTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Packages/Tests/ClarcCoreTests/TaskUpdateMessageTests.swift`:

```swift
import Foundation
import Testing
@testable import ClarcCore

@Suite("TaskUpdateMessage")
struct TaskUpdateMessageTests {

    @Test("formatDuration: 5s")
    func formatUnderMinute() {
        #expect(formatDuration(5) == "5s")
    }

    @Test("formatDuration: 65s = 1m 5s")
    func formatMinutes() {
        #expect(formatDuration(65) == "1m 5s")
    }

    @Test("formatDuration: 3660s = 1h 1m")
    func formatHours() {
        #expect(formatDuration(3660) == "1h 1m")
    }

    @Test("formatDuration: 0s")
    func formatZero() {
        #expect(formatDuration(0) == "0s")
    }

    @Test("formatDuration: negative input clamps to 0s")
    func formatNegative() {
        #expect(formatDuration(-1) == "0s")
        #expect(formatDuration(-300) == "0s")
    }

    @Test("formatDuration: exactly 60s is 1m 0s")
    func formatExactlyMinute() {
        #expect(formatDuration(60) == "1m 0s")
    }

    @Test("formatDuration: exactly 3600s is 1h 0m")
    func formatExactlyHour() {
        #expect(formatDuration(3600) == "1h 0m")
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = TaskUpdateMessage(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Implementation",
            summary: "in progress",
            details: "long details",
            status: .done,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_300),
            durationSeconds: 300,
            filesChanged: [
                TaskFileChange(path: "Foo.swift", additions: 10, deletions: 2, changeType: "modified")
            ],
            testResults: [
                TaskTestResult(name: "FooTests", status: "passed", durationSeconds: 1.5)
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskUpdateMessage.self, from: data)
        #expect(decoded == original)
    }

    @Test("Default fields: empty collections, status running, startTime = Date()")
    func defaultFields() {
        let now = Date()
        let msg = TaskUpdateMessage(title: "X", summary: "y", startTime: now)
        #expect(msg.details.isEmpty)
        #expect(msg.status == .running)
        #expect(msg.endTime == nil)
        #expect(msg.durationSeconds == nil)
        #expect(msg.filesChanged.isEmpty)
        #expect(msg.testResults.isEmpty)
        #expect(msg.startTime == now)
    }
}
```

- [ ] **Step 2: Build to verify failure**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD FAILS — `TaskUpdateMessage`, `formatDuration`, `TaskFileChange`, `TaskTestResult` not defined.

- [ ] **Step 3: Implement the model**

Create `Packages/Sources/ClarcCore/Models/TaskUpdateMessage.swift`:

```swift
import Foundation

// MARK: - Status

public enum TaskUpdateStatus: String, Codable, Sendable, CaseIterable {
    case running
    case done
    case failed
}

// MARK: - Task Update Message

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
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.details = details
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.filesChanged = filesChanged
        self.testResults = testResults
    }
}

// MARK: - File Change

public struct TaskFileChange: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var path: String
    public var additions: Int?
    public var deletions: Int?
    public var changeType: String?

    public init(
        id: UUID = UUID(),
        path: String,
        additions: Int? = nil,
        deletions: Int? = nil,
        changeType: String? = nil
    ) {
        self.id = id
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.changeType = changeType
    }
}

// MARK: - Test Result

public struct TaskTestResult: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var status: String
    public var durationSeconds: TimeInterval?
    public var output: String?

    public init(
        id: UUID = UUID(),
        name: String,
        status: String,
        durationSeconds: TimeInterval? = nil,
        output: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.durationSeconds = durationSeconds
        self.output = output
    }
}

// MARK: - Duration Formatting

/// Format a duration in seconds as a human-readable short string.
/// Negative values clamp to "0s". Examples: `5` → "5s", `65` → "1m 5s",
/// `3660` → "1h 1m".
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

- [ ] **Step 4: Build to verify pass**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/ClarcCore/Models/TaskUpdateMessage.swift \
        Packages/Tests/ClarcCoreTests/TaskUpdateMessageTests.swift
git commit -m "feat(task-update-ui): add TaskUpdateMessage model and formatDuration helper"
```

---

## Task 2: Extend `MessageBlock` with `taskUpdate` field

**Files:**
- Modify: `Packages/Sources/ClarcCore/Models/ChatMessage.swift`

This task doesn't add new tests — the field is mechanically integrated with the existing Codable migration path. Existing tests cover the decode/encode round-trip.

- [ ] **Step 1: Add the field, predicate, and factory**

In `Packages/Sources/ClarcCore/Models/ChatMessage.swift`, modify `MessageBlock` (around line 11). Add the new field alongside the existing `text` / `toolCall` / `thinking` family:

```swift
public struct MessageBlock: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var text: String?
    public var toolCall: ToolCall?
    public var thinking: String?
    public var thinkingDuration: TimeInterval?
    public var isThinkingRedacted: Bool
    public var taskUpdate: TaskUpdateMessage?

    public var isText: Bool { text != nil }
    public var isToolCall: Bool { toolCall != nil }
    public var isThinking: Bool { thinking != nil || isThinkingRedacted }
    public var isTaskUpdate: Bool { taskUpdate != nil }

    public init(
        id: String,
        text: String? = nil,
        toolCall: ToolCall? = nil,
        thinking: String? = nil,
        thinkingDuration: TimeInterval? = nil,
        isThinkingRedacted: Bool = false,
        taskUpdate: TaskUpdateMessage? = nil
    ) {
        self.id = id
        self.text = text
        self.toolCall = toolCall
        self.thinking = thinking
        self.thinkingDuration = thinkingDuration
        self.isThinkingRedacted = isThinkingRedacted
        self.taskUpdate = taskUpdate
    }

    public static func text(_ text: String, id: String = UUID().uuidString) -> MessageBlock {
        MessageBlock(id: id, text: text)
    }

    public static func toolCall(_ toolCall: ToolCall) -> MessageBlock {
        MessageBlock(id: toolCall.id, toolCall: toolCall)
    }

    public static func thinking(
        _ thinking: String,
        duration: TimeInterval? = nil,
        id: String = UUID().uuidString
    ) -> MessageBlock {
        MessageBlock(id: id, thinking: thinking, thinkingDuration: duration)
    }

    public static func redactedThinking(id: String = UUID().uuidString) -> MessageBlock {
        MessageBlock(id: id, isThinkingRedacted: true)
    }

    public static func taskUpdate(_ update: TaskUpdateMessage, id: String = UUID().uuidString) -> MessageBlock {
        MessageBlock(id: id, taskUpdate: update)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, toolCall, thinking, thinkingDuration, isThinkingRedacted, taskUpdate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        toolCall = try c.decodeIfPresent(ToolCall.self, forKey: .toolCall)
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        thinkingDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .thinkingDuration)
        isThinkingRedacted = try c.decodeIfPresent(Bool.self, forKey: .isThinkingRedacted) ?? false
        taskUpdate = try c.decodeIfPresent(TaskUpdateMessage.self, forKey: .taskUpdate)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(toolCall, forKey: .toolCall)
        try c.encodeIfPresent(thinking, forKey: .thinking)
        try c.encodeIfPresent(thinkingDuration, forKey: .thinkingDuration)
        if isThinkingRedacted { try c.encode(true, forKey: .isThinkingRedacted) }
        try c.encodeIfPresent(taskUpdate, forKey: .taskUpdate)
    }
}
```

- [ ] **Step 2: Add a convenience accessor on `ChatMessage`**

After the existing `var toolCalls: [ToolCall]` accessor (around line 195), add:

```swift
public var taskUpdates: [TaskUpdateMessage] {
    blocks.compactMap(\.taskUpdate)
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD SUCCEEDS.

- [ ] **Step 4: Commit**

```bash
git add Packages/Sources/ClarcCore/Models/ChatMessage.swift
git commit -m "feat(task-update-ui): extend MessageBlock with taskUpdate field"
```

---

## Task 3: `TaskUpdateParser` — JSON object + `extract` code-fence / bare-object extraction

**Files:**
- Create: `Packages/Sources/ClarcCore/Parsing/TaskUpdateParser.swift`
- Test: `Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift`:

```swift
import Foundation
import Testing
@testable import ClarcCore

@Suite("TaskUpdateParser")
struct TaskUpdateParserTests {

    private let sampleJSON: [String: Any] = [
        "type": "task_update",
        "id": "11111111-2222-3333-4444-555555555555",
        "title": "Implementation",
        "status": "done",
        "summary": "完成 MiniMaxAdapter 实现",
        "details": "新增 UsageAdapter、MiniMaxAdapter 和 JSONPath。",
        "filesChanged": [
            ["path": "MiniMaxAdapter.swift", "additions": 120, "deletions": 4, "changeType": "added"]
        ],
        "testResults": [
            ["name": "MiniMaxAdapterTests", "status": "passed", "durationSeconds": 3.2]
        ]
    ]

    private func jsonValue(_ dict: [String: Any]) -> JSONValue {
        JSONValue(any: dict)
    }

    @Test("parse(jsonObject:) reads all fields from a complete task_update")
    func parseFullJSON() throws {
        let update = try #require(
            TaskUpdateParser.parse(jsonObject: jsonValue(sampleJSON))
        )
        #expect(update.id == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        #expect(update.title == "Implementation")
        #expect(update.status == .done)
        #expect(update.summary == "完成 MiniMaxAdapter 实现")
        #expect(update.details == "新增 UsageAdapter、MiniMaxAdapter 和 JSONPath。")
        #expect(update.filesChanged.count == 1)
        #expect(update.filesChanged[0].path == "MiniMaxAdapter.swift")
        #expect(update.filesChanged[0].additions == 120)
        #expect(update.filesChanged[0].deletions == 4)
        #expect(update.filesChanged[0].changeType == "added")
        #expect(update.testResults.count == 1)
        #expect(update.testResults[0].name == "MiniMaxAdapterTests")
        #expect(update.testResults[0].status == "passed")
        #expect(update.testResults[0].durationSeconds == 3.2)
    }

    @Test("parse(jsonObject:) returns nil for non-task_update type")
    func parseNonTaskUpdate() {
        let update = TaskUpdateParser.parse(
            jsonObject: jsonValue(["type": "text", "title": "x"])
        )
        #expect(update == nil)
    }

    @Test("parse(jsonObject:) returns nil when title is missing")
    func parseMissingTitle() {
        let update = TaskUpdateParser.parse(
            jsonObject: jsonValue(["type": "task_update", "summary": "x"])
        )
        #expect(update == nil)
    }

    @Test("parse(jsonObject:) defaults status to running for unknown value")
    func parseUnknownStatus() throws {
        let update = try #require(
            TaskUpdateParser.parse(
                jsonObject: jsonValue(["type": "task_update", "title": "x", "status": "weird"])
            )
        )
        #expect(update.status == .running)
    }

    @Test("parse(jsonObject:) auto-fills durationSeconds from endTime-startTime when done and duration is missing")
    func parseAutoDuration() throws {
        let dict: [String: Any] = [
            "type": "task_update",
            "title": "x",
            "status": "done",
            "startTime": "2026-06-02T10:00:00Z",
            "endTime": "2026-06-02T10:05:00Z"
        ]
        let update = try #require(TaskUpdateParser.parse(jsonObject: jsonValue(dict)))
        #expect(update.durationSeconds == 300)
    }

    @Test("parse(jsonObject:) does not auto-fill duration when running")
    func parseNoAutoDurationWhenRunning() throws {
        let dict: [String: Any] = [
            "type": "task_update",
            "title": "x",
            "status": "running",
            "startTime": "2026-06-02T10:00:00Z",
            "endTime": "2026-06-02T10:05:00Z"
        ]
        let update = try #require(TaskUpdateParser.parse(jsonObject: jsonValue(dict)))
        #expect(update.durationSeconds == nil)
    }

    @Test("parse(jsonObject:) generates a fresh UUID when id is missing or invalid")
    func parseMissingOrBadID() throws {
        let update1 = try #require(
            TaskUpdateParser.parse(
                jsonObject: jsonValue(["type": "task_update", "title": "x"])
            )
        )
        let update2 = try #require(
            TaskUpdateParser.parse(
                jsonObject: jsonValue(["type": "task_update", "title": "x", "id": "not-a-uuid"])
            )
        )
        #expect(update1.id != UUID())
        // not-a-uuid falls through to a fresh UUID, not the same as update1
        #expect(update2.id != update1.id)
    }

    @Test("extract: code-fence-wrapped JSON task_update is parsed and removed")
    func extractFromCodeFence() {
        let input = """
        Some prose before.
        ```json
        {"type": "task_update", "title": "Inside", "status": "done"}
        ```
        Some prose after.
        """
        let (updates, remaining) = TaskUpdateParser.extract(from: input)
        #expect(updates.count == 1)
        #expect(updates[0].title == "Inside")
        #expect(updates[0].status == .done)
        #expect(!remaining.contains("task_update"))
        #expect(remaining.contains("Some prose before."))
        #expect(remaining.contains("Some prose after."))
    }

    @Test("extract: bare JSON object is parsed and removed")
    func extractBareObject() {
        let input = #"Hello {"type": "task_update", "title": "Bare", "status": "running"} world"#
        let (updates, remaining) = TaskUpdateParser.extract(from: input)
        #expect(updates.count == 1)
        #expect(updates[0].title == "Bare")
        #expect(updates[0].status == .running)
        #expect(!remaining.contains("task_update"))
        #expect(remaining.contains("Hello "))
        #expect(remaining.contains(" world"))
    }

    @Test("extract: plain text without task_update markers passes through")
    func extractPlainText() {
        let input = "Just some regular text with no markers."
        let (updates, remaining) = TaskUpdateParser.extract(from: input)
        #expect(updates.isEmpty)
        #expect(remaining == input)
    }

    @Test("extract: empty string yields no updates and empty remaining")
    func extractEmpty() {
        let (updates, remaining) = TaskUpdateParser.extract(from: "")
        #expect(updates.isEmpty)
        #expect(remaining.isEmpty)
    }

    @Test("extract: a JSON object whose type is not task_update is NOT extracted as a bare object")
    func extractRejectsNonTaskUpdateBareObject() {
        let input = #"some {"type": "text", "title": "x"} text"#
        let (updates, remaining) = TaskUpdateParser.extract(from: input)
        #expect(updates.isEmpty)
        #expect(remaining == input)
    }
}
```

- [ ] **Step 2: Build to verify failure**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD FAILS — `TaskUpdateParser` not defined.

- [ ] **Step 3: Implement the parser (JSON + extract, no XML yet)**

Create `Packages/Sources/ClarcCore/Parsing/TaskUpdateParser.swift`:

```swift
import Foundation

/// Parses `task_update` JSON / XML fragments embedded in streamed
/// assistant text. The parser is stateless and pure — the caller is
/// responsible for routing the resulting `TaskUpdateMessage` into a
/// `TaskProgressStore` and a `MessageBlock`.
public enum TaskUpdateParser {

    // MARK: - Public API

    /// Try to extract one or more `task_update` blocks from a chunk
    /// of text. Three extractors run in order against the running
    /// `remaining` so a JSON object inside a code fence is not also
    /// matched as a bare object.
    public static func extract(from text: String) -> (updates: [TaskUpdateMessage], remaining: String) {
        var updates: [TaskUpdateMessage] = []
        var remaining = text

        // 1. Code-fence JSON
        remaining = extractCodeFenceJSON(from: remaining, into: &updates)

        // 2. XML — implemented in Task 4. For Task 3, this is a no-op.
        remaining = extractXML(from: remaining, into: &updates)

        // 3. Bare JSON object
        remaining = extractBareJSONObject(from: remaining, into: &updates)

        return (updates, remaining)
    }

    /// Parse a single JSON object. Returns nil when the object is not
    /// a `task_update` (wrong `type` field) or is missing the required
    /// `title` field.
    public static func parse(jsonObject: JSONValue) -> TaskUpdateMessage? {
        guard case .object(let dict) = jsonObject else { return nil }
        guard let type = stringValue(dict["type"]), type == "task_update" else { return nil }
        guard let title = stringValue(dict["title"]), !title.isEmpty else { return nil }

        let id = parseID(dict["id"])
        let summary = stringValue(dict["summary"]) ?? ""
        let details = stringValue(dict["details"]) ?? ""
        let status = parseStatus(dict["status"])
        let startTime = parseDate(dict["startTime"]) ?? Date()
        let endTime = parseDate(dict["endTime"])
        var durationSeconds = parseDouble(dict["durationSeconds"])
        if durationSeconds == nil, status == .done, let end = endTime {
            durationSeconds = end.timeIntervalSince(startTime)
        }
        let filesChanged = parseFiles(dict["filesChanged"])
        let testResults = parseTests(dict["testResults"])

        return TaskUpdateMessage(
            id: id,
            title: title,
            summary: summary,
            details: details,
            status: status,
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSeconds,
            filesChanged: filesChanged,
            testResults: testResults
        )
    }

    /// Parse a `<task-update ...>...</task-update>` XML fragment.
    /// Implemented in Task 4. Returns nil for now.
    public static func parse(xmlFragment: String) -> TaskUpdateMessage? {
        nil
    }

    // MARK: - Private helpers (JSON path)

    private static func extractCodeFenceJSON(
        from text: String,
        into updates: inout [TaskUpdateMessage]
    ) -> String {
        var result = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            // Find the opening ```
            guard let fenceStart = text.range(of: "```", range: cursor..<text.endIndex) else {
                result.append(contentsOf: text[cursor..<text.endIndex])
                break
            }
            // Append everything up to the fence
            result.append(contentsOf: text[cursor..<fenceStart.lowerBound])
            // Expect json right after ```
            let afterFence = fenceStart.upperBound
            let jsonTag = text[afterFence..<text.endIndex].prefix(4)
            let isJSONFence = jsonTag.lowercased() == "json"
            if !isJSONFence {
                // Not a json fence — keep the fence in the remaining text
                result.append(contentsOf: text[fenceStart.lowerBound..<afterFence])
                cursor = afterFence
                continue
            }
            // Find the closing ```
            let searchStart = text.index(afterFence, offsetBy: 4)
            guard let fenceEnd = text.range(of: "```", range: searchStart..<text.endIndex) else {
                // Unterminated fence — bail, leave the rest as-is
                result.append(contentsOf: text[fenceStart.lowerBound..<text.endIndex])
                return result
            }
            let inner = String(text[searchStart..<fenceEnd.lowerBound])
            if let data = inner.data(using: .utf8),
               let any = try? JSONSerialization.jsonObject(with: data),
               let update = parse(jsonObject: JSONValue(any: any)) {
                updates.append(update)
            } else {
                // Not a valid task_update — keep the fence
                result.append(contentsOf: text[fenceStart.lowerBound..<fenceEnd.upperBound])
            }
            cursor = fenceEnd.upperBound
        }
        return result
    }

    private static func extractBareJSONObject(
        from text: String,
        into updates: inout [TaskUpdateMessage]
    ) -> String {
        var result = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard let openIdx = text[cursor...].firstIndex(of: "{") else {
                result.append(contentsOf: text[cursor..<text.endIndex])
                break
            }
            // Append everything up to the {
            result.append(contentsOf: text[cursor..<openIdx])
            // Find the matching close brace (depth counting, skip strings)
            guard let closeIdx = findMatchingBrace(in: text, from: openIdx) else {
                // Unmatched brace — append and stop
                result.append(contentsOf: text[openIdx..<text.endIndex])
                return result
            }
            let candidate = String(text[openIdx...closeIdx])
            if let data = candidate.data(using: .utf8),
               let any = try? JSONSerialization.jsonObject(with: data),
               let update = parse(jsonObject: JSONValue(any: any)) {
                updates.append(update)
            } else {
                // Not a valid task_update — keep the brace range in the output
                result.append(contentsOf: text[openIdx...closeIdx])
            }
            cursor = text.index(after: closeIdx)
        }
        return result
    }

    /// Stub: returns `text` unchanged. Task 4 implements XML extraction.
    private static func extractXML(
        from text: String,
        into updates: inout [TaskUpdateMessage]
    ) -> String {
        return text
    }

    private static func findMatchingBrace(in text: String, from openIdx: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escape = false
        var idx = openIdx
        while idx < text.endIndex {
            let c = text[idx]
            if escape {
                escape = false
            } else if c == "\\" {
                escape = true
            } else if c == "\"" {
                inString.toggle()
            } else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return idx }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    // MARK: - Field parsers

    private static func parseID(_ v: JSONValue?) -> UUID {
        if case .string(let s) = v, let u = UUID(uuidString: s) {
            return u
        }
        return UUID()
    }

    private static func parseStatus(_ v: JSONValue?) -> TaskUpdateStatus {
        guard case .string(let s) = v else { return .running }
        return TaskUpdateStatus(rawValue: s) ?? .running
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterFallback = ISO8601DateFormatter()

    private static func parseDate(_ v: JSONValue?) -> Date? {
        guard case .string(let s) = v else { return nil }
        return isoFormatter.date(from: s) ?? isoFormatterFallback.date(from: s)
    }

    private static func parseDouble(_ v: JSONValue?) -> TimeInterval? {
        if case .number(let n) = v { return n }
        return nil
    }

    private static func stringValue(_ v: JSONValue?) -> String? {
        if case .string(let s) = v { return s }
        return nil
    }

    private static func parseFiles(_ v: JSONValue?) -> [TaskFileChange] {
        guard case .array(let arr) = v else { return [] }
        return arr.compactMap { item -> TaskFileChange? in
            guard case .object(let dict) = item else { return nil }
            guard let path = stringValue(dict["path"]) else { return nil }
            return TaskFileChange(
                path: path,
                additions: parseInt(dict["additions"]),
                deletions: parseInt(dict["deletions"]),
                changeType: stringValue(dict["changeType"])
            )
        }
    }

    private static func parseTests(_ v: JSONValue?) -> [TaskTestResult] {
        guard case .array(let arr) = v else { return [] }
        return arr.compactMap { item -> TaskTestResult? in
            guard case .object(let dict) = item else { return nil }
            guard let name = stringValue(dict["name"]) else { return nil }
            return TaskTestResult(
                name: name,
                status: stringValue(dict["status"]) ?? "unknown",
                durationSeconds: parseDouble(dict["durationSeconds"]),
                output: stringValue(dict["output"])
            )
        }
    }

    private static func parseInt(_ v: JSONValue?) -> Int? {
        if case .number(let n) = v { return Int(n) }
        return nil
    }
}

// MARK: - JSONValue init from Any (used by extract to bridge JSONSerialization)

private extension JSONValue {
    init(any: Any) {
        if let n = any as? NSNumber {
            self = .number(n.doubleValue)
        } else if let s = any as? String {
            self = .string(s)
        } else if let b = any as? Bool {
            self = .bool(b)
        } else if let arr = any as? [Any] {
            self = .array(arr.map { JSONValue(any: $0) })
        } else if let dict = any as? [String: Any] {
            self = .object(dict.mapValues { JSONValue(any: $0) })
        } else {
            self = .null
        }
    }
}
```

- [ ] **Step 4: Build to verify pass**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/ClarcCore/Parsing/TaskUpdateParser.swift \
        Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift
git commit -m "feat(task-update-ui): add TaskUpdateParser with JSON and extract"
```

---

## Task 4: `TaskUpdateParser` — XML extraction

**Files:**
- Modify: `Packages/Sources/ClarcCore/Parsing/TaskUpdateParser.swift` (replace the XML stub)
- Modify: `Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift` (add XML tests)

- [ ] **Step 1: Add failing XML tests**

Append to `Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift`:

```swift
    private let sampleXML = """
    <task-update id="phase-1" title="Implementation" status="done">
      <summary>完成 MiniMaxAdapter 实现</summary>
      <details>新增 UsageAdapter、MiniMaxAdapter 和 JSONPath。</details>
      <filesChanged>
        <file path="MiniMaxAdapter.swift" changeType="added" additions="120" deletions="4"/>
      </filesChanged>
      <testResults>
        <test name="MiniMaxAdapterTests" status="passed" durationSeconds="3.2"/>
      </testResults>
    </task-update>
    """

    @Test("parse(xmlFragment:) reads attributes and child elements")
    func parseFullXML() throws {
        let update = try #require(TaskUpdateParser.parse(xmlFragment: sampleXML))
        #expect(update.title == "Implementation")
        #expect(update.status == .done)
        #expect(update.summary == "完成 MiniMaxAdapter 实现")
        #expect(update.details == "新增 UsageAdapter、MiniMaxAdapter 和 JSONPath。")
        #expect(update.filesChanged.count == 1)
        #expect(update.filesChanged[0].path == "MiniMaxAdapter.swift")
        #expect(update.filesChanged[0].additions == 120)
        #expect(update.filesChanged[0].deletions == 4)
        #expect(update.filesChanged[0].changeType == "added")
        #expect(update.testResults.count == 1)
        #expect(update.testResults[0].name == "MiniMaxAdapterTests")
        #expect(update.testResults[0].status == "passed")
        #expect(update.testResults[0].durationSeconds == 3.2)
    }

    @Test("parse(xmlFragment:) returns nil when title is missing")
    func parseXMLMissingTitle() {
        let xml = "<task-update id=\"x\" status=\"running\"></task-update>"
        #expect(TaskUpdateParser.parse(xmlFragment: xml) == nil)
    }

    @Test("parse(xmlFragment:) returns nil for malformed XML")
    func parseMalformedXML() {
        #expect(TaskUpdateParser.parse(xmlFragment: "<not-task-update>") == nil)
    }

    @Test("parse(xmlFragment:) uses a fresh UUID when id is missing or unparseable")
    func parseXMLBadID() throws {
        let xml = "<task-update title=\"x\"></task-update>"
        let update = try #require(TaskUpdateParser.parse(xmlFragment: xml))
        #expect(update.id != UUID())
    }

    @Test("extract: XML block is parsed and removed from the surrounding text")
    func extractXML() {
        let input = "Before <task-update title=\"X\" status=\"done\"></task-update> after"
        let (updates, remaining) = TaskUpdateParser.extract(from: input)
        #expect(updates.count == 1)
        #expect(updates[0].title == "X")
        #expect(updates[0].status == .done)
        #expect(!remaining.contains("<task-update"))
        #expect(remaining.contains("Before"))
        #expect(remaining.contains("after"))
    }
```

- [ ] **Step 2: Build to verify failure**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD SUCCEEDS for compile (no symbol error) but tests for `parse(xmlFragment:)` fail at runtime because the stub returns nil.

`swift test` is not runnable on this CommandLineTools-only machine — see the env note at the end of this plan. Verify the code compiles and trace the test paths by hand.

- [ ] **Step 3: Implement XML parsing + extraction**

Replace the XML stub in `Packages/Sources/ClarcCore/Parsing/TaskUpdateParser.swift`. First, replace the public `parse(xmlFragment:)` with:

```swift
    public static func parse(xmlFragment: String) -> TaskUpdateMessage? {
        let parser = XMLParser(data: Data(xmlFragment.utf8))
        let delegate = TaskUpdateXMLDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }
        guard let title = delegate.title, !title.isEmpty else { return nil }
        return TaskUpdateMessage(
            id: delegate.id ?? UUID(),
            title: title,
            summary: delegate.summary ?? "",
            details: delegate.details ?? "",
            status: TaskUpdateStatus(rawValue: delegate.status ?? "") ?? .running,
            startTime: Date(),
            endTime: nil,
            durationSeconds: nil,
            filesChanged: delegate.files,
            testResults: delegate.tests
        )
    }
```

Then replace the `extractXML` stub with:

```swift
    private static func extractXML(
        from text: String,
        into updates: inout [TaskUpdateMessage]
    ) -> String {
        var result = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard let openRange = text.range(of: "<task-update", range: cursor..<text.endIndex) else {
                result.append(contentsOf: text[cursor..<text.endIndex])
                break
            }
            result.append(contentsOf: text[cursor..<openRange.lowerBound])
            // Find the matching </task-update> close
            let afterOpen = openRange.upperBound
            guard let closeRange = text.range(of: "</task-update>", range: afterOpen..<text.endIndex) else {
                // Unterminated — keep everything as-is
                result.append(contentsOf: text[openRange.lowerBound..<text.endIndex])
                return result
            }
            let fragment = String(text[openRange.lowerBound..<closeRange.upperBound])
            if let update = parse(xmlFragment: fragment) {
                updates.append(update)
            } else {
                result.append(contentsOf: fragment)
            }
            cursor = closeRange.upperBound
        }
        return result
    }
```

Then add the delegate class at the bottom of the file (file scope):

```swift
// MARK: - XML Delegate

private final class TaskUpdateXMLDelegate: NSObject, XMLParserDelegate {
    var id: UUID?
    var title: String?
    var status: String?
    var summary: String?
    var details: String?
    var files: [TaskFileChange] = []
    var tests: [TaskTestResult] = []

    private var elementStack: [String] = []
    private var currentText = ""
    private var inFilesContainer = false
    private var inTestsContainer = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "task-update":
            if let idStr = attributeDict["id"], let u = UUID(uuidString: idStr) {
                id = u
            }
            title = attributeDict["title"]
            status = attributeDict["status"]
        case "file":
            if inFilesContainer,
               let path = attributeDict["path"] {
                files.append(TaskFileChange(
                    path: path,
                    additions: intValue(attributeDict["additions"]),
                    deletions: intValue(attributeDict["deletions"]),
                    changeType: attributeDict["changeType"]
                ))
            }
        case "test":
            if inTestsContainer,
               let name = attributeDict["name"] {
                tests.append(TaskTestResult(
                    name: name,
                    status: attributeDict["status"] ?? "unknown",
                    durationSeconds: doubleValue(attributeDict["durationSeconds"])
                ))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "summary" where elementStack.dropLast().last == "task-update":
            summary = trimmed
        case "details" where elementStack.dropLast().last == "task-update":
            details = trimmed
        case "filesChanged":
            inFilesContainer = false
        case "testResults":
            inTestsContainer = false
        default:
            break
        }
        if elementName == "filesChanged" { inFilesContainer = true }
        if elementName == "testResults" { inTestsContainer = true }
        if !elementStack.isEmpty { elementStack.removeLast() }
        currentText = ""
    }

    private func intValue(_ s: String?) -> Int? {
        guard let s, !s.isEmpty else { return nil }
        return Int(s)
    }

    private func doubleValue(_ s: String?) -> TimeInterval? {
        guard let s, !s.isEmpty else { return nil }
        return Double(s)
    }
}
```

Note: the `inFilesContainer` / `inTestsContainer` flags are toggled on didEndElement by name. The intent is to enable the `<file>` / `<test>` child-element handling inside `<filesChanged>` / `<testResults>`. To be safe, set these on `didStartElement` instead — adjust by replacing the `if elementName == "filesChanged" { inFilesContainer = true }` lines with `didStartElement` handling:

Update the `didStartElement` switch in the delegate to also set the flags:

```swift
        case "filesChanged":
            inFilesContainer = true
        case "testResults":
            inTestsContainer = true
```

And remove the corresponding toggles in `didEndElement`.

- [ ] **Step 4: Build to verify**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/ClarcCore/Parsing/TaskUpdateParser.swift \
        Packages/Tests/ClarcCoreTests/TaskUpdateParserTests.swift
git commit -m "feat(task-update-ui): add XML extraction to TaskUpdateParser"
```

---

## Task 5: `TaskProgressStore`

**Files:**
- Create: `Packages/Sources/ClarcCore/Stores/TaskProgressStore.swift`
- Test: `Packages/Tests/ClarcCoreTests/TaskProgressStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Packages/Tests/ClarcCoreTests/TaskProgressStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import ClarcCore

@MainActor
@Suite("TaskProgressStore")
struct TaskProgressStoreTests {

    @Test("start creates a running task and returns its id")
    func start() {
        let store = TaskProgressStore()
        let id = store.start(title: "Implementation", summary: "in progress")
        let task = store.tasks[id]
        #expect(task != nil)
        #expect(task?.title == "Implementation")
        #expect(task?.summary == "in progress")
        #expect(task?.status == .running)
    }

    @Test("update fills only the non-nil fields")
    func updatePartial() async {
        let store = TaskProgressStore()
        let id = store.start(title: "T", summary: "s")
        try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
        store.update(id: id, summary: "new", details: nil, filesChanged: nil, testResults: nil)
        let task = store.tasks[id]
        #expect(task?.summary == "new")
        #expect(task?.details == "")
    }

    @Test("finish sets endTime and durationSeconds")
    func finishSetsDuration() async {
        let store = TaskProgressStore()
        let id = store.start(title: "T", summary: "s")
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        store.finish(id: id, summary: "done", details: nil, status: .done)
        let task = store.tasks[id]
        #expect(task?.status == .done)
        #expect(task?.endTime != nil)
        #expect((task?.durationSeconds ?? 0) > 0)
    }

    @Test("fail is finish with .failed")
    func failSetsFailed() {
        let store = TaskProgressStore()
        let id = store.start(title: "T", summary: "s")
        store.fail(id: id, summary: "oops", details: nil)
        #expect(store.tasks[id]?.status == .failed)
        #expect(store.tasks[id]?.summary == "oops")
    }

    @Test("upsert with a new id is wasNew=true and the message goes in unchanged")
    func upsertNew() {
        let store = TaskProgressStore()
        let update = TaskUpdateMessage(title: "T", summary: "s", status: .running)
        let (wasNew, merged) = store.upsert(update)
        #expect(wasNew == true)
        #expect(merged == update)
        #expect(store.tasks[update.id] == update)
    }

    @Test("upsert with an existing id preserves startTime and writes duration when done")
    func upsertPreservesStartTime() async {
        let store = TaskProgressStore()
        let id = store.start(title: "T", summary: "s")
        try? await Task.sleep(nanoseconds: 50_000_000)
        let endTime = Date()
        let update = TaskUpdateMessage(
            id: id, title: "T", summary: "done",
            status: .done, startTime: Date(timeIntervalSince1970: 0),
            endTime: endTime
        )
        let (wasNew, merged) = store.upsert(update)
        #expect(wasNew == false)
        // Original startTime is preserved
        #expect(merged.startTime == store.tasks[id]?.startTime)
        // duration is recomputed because status is done
        #expect(merged.durationSeconds != nil)
    }

    @Test("isExpanded defaults: running=true, done=false, failed=true")
    func isExpandedDefaults() {
        let store = TaskProgressStore()
        let runningID = store.start(title: "R", summary: "")
        let doneID = store.start(title: "D", summary: "")
        store.finish(id: doneID, summary: nil, details: nil, status: .done)
        let failedID = store.start(title: "F", summary: "")
        store.fail(id: failedID, summary: nil, details: nil)

        #expect(store.isExpanded(store.tasks[runningID]!) == true)
        #expect(store.isExpanded(store.tasks[doneID]!) == false)
        #expect(store.isExpanded(store.tasks[failedID]!) == true)
    }

    @Test("isExpanded respects manual override")
    func isExpandedOverride() {
        let store = TaskProgressStore()
        let id = store.start(title: "R", summary: "")
        // Default: running → true
        #expect(store.isExpanded(store.tasks[id]!) == true)
        // User collapses
        store.setExpanded(false, for: id)
        #expect(store.isExpanded(store.tasks[id]!) == false)
        // User re-expands
        store.setExpanded(true, for: id)
        #expect(store.isExpanded(store.tasks[id]!) == true)
    }
}
```

- [ ] **Step 2: Build to verify failure**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD FAILS — `TaskProgressStore` not defined.

- [ ] **Step 3: Implement the store**

Create `Packages/Sources/ClarcCore/Stores/TaskProgressStore.swift`:

```swift
import Foundation
import Combine

/// Tracks the lifecycle of `TaskUpdateMessage` instances — which
/// `id`s we've already seen, their current state, and the user's
/// manual expand/collapse choices.
///
/// This is **not** the render source. `MessageBlock.taskUpdate` is
/// the canonical render source. The store exists so the streaming
/// layer can ask "have I already seen this id?" and so Swift code
/// outside the stream can drive the lifecycle directly.
@MainActor
public final class TaskProgressStore: ObservableObject {

    @Published public private(set) var tasks: [UUID: TaskUpdateMessage] = [:]
    @Published public private(set) var manualExpansion: [UUID: Bool] = [:]

    public init() {}

    // MARK: - Lifecycle

    @discardableResult
    public func start(title: String, summary: String) -> UUID {
        let message = TaskUpdateMessage(title: title, summary: summary, status: .running)
        tasks[message.id] = message
        return message.id
    }

    public func update(
        id: UUID,
        summary: String?,
        details: String?,
        filesChanged: [TaskFileChange]?,
        testResults: [TaskTestResult]?
    ) {
        guard var existing = tasks[id] else { return }
        if let summary { existing.summary = summary }
        if let details { existing.details = details }
        if let filesChanged { existing.filesChanged = filesChanged }
        if let testResults { existing.testResults = testResults }
        tasks[id] = existing
    }

    public func finish(
        id: UUID,
        summary: String?,
        details: String?,
        status: TaskUpdateStatus
    ) {
        guard var existing = tasks[id] else { return }
        existing.status = status
        if let summary { existing.summary = summary }
        if let details { existing.details = details }
        existing.endTime = Date()
        existing.durationSeconds = existing.endTime?.timeIntervalSince(existing.startTime)
        tasks[id] = existing
    }

    public func fail(id: UUID, summary: String?, details: String?) {
        finish(id: id, summary: summary, details: details, status: .failed)
    }

    // MARK: - Parser integration

    /// Insert a `TaskUpdateMessage` from the parser. If the id is
    /// already tracked, preserve the original `startTime` and
    /// recompute `durationSeconds` when applicable.
    public func upsert(_ update: TaskUpdateMessage) -> (wasNew: Bool, merged: TaskUpdateMessage) {
        if let existing = tasks[update.id] {
            var merged = update
            merged.startTime = existing.startTime
            if merged.status != .running, let end = merged.endTime {
                merged.durationSeconds = end.timeIntervalSince(merged.startTime)
            }
            tasks[update.id] = merged
            return (false, merged)
        } else {
            tasks[update.id] = update
            return (true, update)
        }
    }

    // MARK: - Expansion state

    public func isExpanded(_ update: TaskUpdateMessage) -> Bool {
        if let manual = manualExpansion[update.id] { return manual }
        switch update.status {
        case .running, .failed: return true
        case .done: return false
        }
    }

    public func setExpanded(_ expanded: Bool, for id: UUID) {
        manualExpansion[id] = expanded
    }
}
```

- [ ] **Step 4: Build to verify pass**

Run: `cd Packages && swift build --target ClarcCore`
Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/ClarcCore/Stores/TaskProgressStore.swift \
        Packages/Tests/ClarcCoreTests/TaskProgressStoreTests.swift
git commit -m "feat(task-update-ui): add TaskProgressStore with start/finish/upsert/expansion"
```

---

## Task 6: `TaskUpdateCard` view

**Files:**
- Create: `Packages/Sources/ClarcChatKit/Views/TaskUpdateCard.swift`

This task doesn't add new tests — the card is exercised manually in Xcode.

- [ ] **Step 1: Implement the card**

Create `Packages/Sources/ClarcChatKit/Views/TaskUpdateCard.swift`:

```swift
import SwiftUI
import ClarcCore

/// A single Codex-style phase card. Renders inline (not inside an
/// assistant bubble) with a status icon, title, summary, live or
/// frozen duration, and an expandable detail region.
struct TaskUpdateCard: View {
    let update: TaskUpdateMessage
    @Binding var isExpanded: Bool
    @State private var now: Date = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                if !update.details.isEmpty { detailsSection }
                if !update.filesChanged.isEmpty { filesSection }
                if !update.testResults.isEmpty { testsSection }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .onReceive(ticker) { _ in
            if update.status == .running { now = Date() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            statusIcon
                .frame(width: 16, height: 16)
            Text(update.title)
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .semibold))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !update.summary.isEmpty {
                Text(update.summary)
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(formatDuration(liveDuration))
                .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced).monospacedDigit())
                .foregroundStyle(ClaudeTheme.textTertiary)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: ClaudeTheme.messageSize(10), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var detailsSection: some View {
        Text(update.details)
            .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
            .foregroundStyle(ClaudeTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Changed Files")
            ForEach(update.filesChanged) { change in
                HStack(spacing: 6) {
                    Image(systemName: fileIcon(change.changeType))
                        .font(.system(size: 11))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    Text(change.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let adds = change.additions {
                        Text("+\(adds)")
                            .font(.system(size: 11, design: .monospaced).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if let dels = change.deletions {
                        Text("-\(dels)")
                            .font(.system(size: 11, design: .monospaced).monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var testsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Tests")
            ForEach(update.testResults) { result in
                HStack(spacing: 6) {
                    Image(systemName: testIcon(result.status))
                        .font(.system(size: 11))
                        .foregroundStyle(testColor(result.status))
                    Text(result.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let dur = result.durationSeconds {
                        Text(formatDuration(dur))
                            .font(.system(size: 11, design: .monospaced).monospacedDigit())
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ClaudeTheme.textSecondary)
    }

    // MARK: - Status icon

    @ViewBuilder
    private var statusIcon: some View {
        switch update.status {
        case .running:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ClaudeTheme.statusSuccess)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(ClaudeTheme.statusWarning)
        }
    }

    // MARK: - Live duration

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

    // MARK: - Icons

    private func fileIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "added": return "doc.badge.plus"
        case "deleted": return "doc.badge.minus"
        case "renamed": return "doc.badge.arrow.up"
        default: return "doc"
        }
    }

    private func testIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "passed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        default: return "minus.circle"
        }
    }

    private func testColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "passed": return ClaudeTheme.statusSuccess
        case "failed": return ClaudeTheme.statusWarning
        default: return ClaudeTheme.textSecondary
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd Packages && swift build --target ClarcChatKit 2>&1 | tail -20` (or the parent project build)
Expected: BUILD SUCCEEDS. If the package's `ClarcChatKit` target fails due to the Xcode-only `#Preview` macro, that's pre-existing — the ClarcCore build is the gate.

- [ ] **Step 3: Commit**

```bash
git add Packages/Sources/ClarcChatKit/Views/TaskUpdateCard.swift
git commit -m "feat(task-update-ui): add TaskUpdateCard view with live duration"
```

---

## Task 7: `WindowState.taskProgressStore` + `ChatBridge` accessor

**Files:**
- Modify: `Packages/Sources/ClarcCore/WindowState.swift`
- Modify: `Packages/Sources/ClarcChatKit/ChatBridge.swift`

- [ ] **Step 1: Add the property to `WindowState`**

In `Packages/Sources/ClarcCore/WindowState.swift`, add the store as a `let` property (so it lives for the lifetime of the window):

```swift
public let taskProgressStore = TaskProgressStore()
```

Add it next to the other window-identity properties (around line 44-46).

- [ ] **Step 2: Expose on `ChatBridge`**

In `Packages/Sources/ClarcChatKit/ChatBridge.swift`, add an optional store reference. The store is reachable from `WindowState`, but the bridge is the path used by `MessageBubble`, so the bridge needs a reference too:

```swift
public weak var taskProgressStore: TaskProgressStore?
```

(weak because the bridge may outlive a particular window's WindowState; the store is owned by the window.)

- [ ] **Step 3: Wire the bridge reference at `AppState` setup**

In `Clarc/App/AppState.swift`, where the bridge handlers are wired (around line 737, near `bridge.fetchRateLimitHandler`), add:

```swift
bridge.taskProgressStore = windowState.taskProgressStore
```

Find the existing line `bridge.fetchRateLimitHandler = { ... }` and add the assignment nearby.

- [ ] **Step 4: Build to verify**

Run: `cd Packages && swift build --target ClarcCore 2>&1 | tail -10`
Expected: BUILD SUCCEEDS for ClarcCore. The Clarc app target build verification requires full Xcode; not runnable on CommandLineTools.

- [ ] **Step 5: Commit**

```bash
git add Packages/Sources/ClarcCore/WindowState.swift \
        Packages/Sources/ClarcChatKit/ChatBridge.swift \
        Clarc/App/AppState.swift
git commit -m "feat(task-update-ui): wire TaskProgressStore through WindowState and ChatBridge"
```

---

## Task 8: `MessageBubble` render branch

**Files:**
- Modify: `Packages/Sources/ClarcChatKit/MessageBubble.swift`

- [ ] **Step 1: Add the card-render branch**

In `Packages/Sources/ClarcChatKit/MessageBubble.swift`, in the `ForEach(visibleBlocks)` loop (around line 71-88), add a new branch after the `isThinking` check:

```swift
                        if let taskUpdate = block.taskUpdate,
                           let store = chatBridge.taskProgressStore {
                            TaskUpdateCard(
                                update: taskUpdate,
                                isExpanded: Binding(
                                    get: { store.isExpanded(taskUpdate) },
                                    set: { store.setExpanded($0, for: taskUpdate.id) }
                                )
                            )
                        }
```

- [ ] **Step 2: Build to verify**

Run: `cd Packages && swift build --target ClarcChatKit 2>&1 | tail -20` (or the parent project build)
Expected: BUILD SUCCEEDS. Pre-existing `#Preview` macro warnings are OK.

- [ ] **Step 3: Commit**

```bash
git add Packages/Sources/ClarcChatKit/MessageBubble.swift
git commit -m "feat(task-update-ui): render TaskUpdateCard in MessageBubble"
```

---

## Task 9: `AppState` stream integration

**Files:**
- Modify: `Clarc/App/AppState.swift`

- [ ] **Step 1: Add the extraction call**

In `Clarc/App/AppState.swift`, find the text-delta handling block (around line 1820-1832). It currently looks like:

```swift
            let buffered = tail.textDeltaBuffer
            tail.textDeltaBuffer = ""

            if tail.needsNewMessage {
                if let idx = tail.messages.indices.last(where: { tail.messages[$0].isStreaming }) {
                    tail.messages[idx].isStreaming = false
                    tail.messages[idx].finalizeToolCalls()
                    Self.stripNoOpText(at: idx, in: &tail.messages)
                }
                tail.needsNewMessage = false
                tail.messages.append(ChatMessage(role: .assistant, content: buffered, isStreaming: true))
            } else if let idx = tail.messages.indices.last(where: { tail.messages[$0].isStreaming && tail.messages[$0].role == .assistant }) {
                tail.messages[idx].appendText(buffered)
            } else {
                tail.messages.append(ChatMessage(role: .assistant, content: buffered, isStreaming: true))
            }
```

Restructure the `else if` branch and the trailing `else` branch so that the buffered text is first passed through `TaskUpdateParser.extract` before being appended. Specifically, replace the `if/else if/else` chain with:

```swift
            let (extracted, remainingBuffered) = TaskUpdateParser.extract(from: buffered)

            if tail.needsNewMessage {
                if let idx = tail.messages.indices.last(where: { tail.messages[$0].isStreaming }) {
                    tail.messages[idx].isStreaming = false
                    tail.messages[idx].finalizeToolCalls()
                    Self.stripNoOpText(at: idx, in: &tail.messages)
                }
                tail.needsNewMessage = false
                tail.messages.append(ChatMessage(role: .assistant, content: remainingBuffered, isStreaming: true))
            } else if let idx = tail.messages.indices.last(where: { tail.messages[$0].isStreaming && tail.messages[$0].role == .assistant }) {
                // Route extracted task_updates into the store and into the message blocks
                for parsed in extracted {
                    let (wasNew, merged) = windowState.taskProgressStore.upsert(parsed)
                    if wasNew {
                        tail.messages[idx].blocks.append(.taskUpdate(merged))
                    } else if let blockIdx = tail.messages[idx].blocks.firstIndex(where: { $0.taskUpdate?.id == merged.id }) {
                        tail.messages[idx].blocks[blockIdx].taskUpdate = merged
                    }
                }
                if !remainingBuffered.isEmpty {
                    tail.messages[idx].appendText(remainingBuffered)
                }
            } else {
                tail.messages.append(ChatMessage(role: .assistant, content: remainingBuffered, isStreaming: true))
            }
```

Note: `windowState` is the per-window state for the current stream. Find how it's threaded into this function — the streaming handler should have a `WindowState` in scope. If it doesn't, you'll need to capture the `key` (session identifier) and look up the window's `WindowState` from `AppState`'s windows collection. Inspect the surrounding code to find the right path.

If the streaming context doesn't have a `WindowState` in scope, the simplest fallback is to look up `state.windowState` from the per-session state struct. Add a `windowState: WindowState?` field to the session state and populate it when the window is set up.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Clarc.xcodeproj -scheme Clarc -configuration Debug build 2>&1 | tail -30` (or, if xcodebuild is unavailable, verify by source inspection + ClarcCore build).
Expected: BUILD SUCCEEDS.

If there are compile errors, the most likely culprit is `windowState` not being in scope at the right place — look at how `tail` and `state` are populated and add a `windowState` capture if needed.

- [ ] **Step 3: Commit**

```bash
git add Clarc/App/AppState.swift
git commit -m "feat(task-update-ui): extract task_update from streamed text into message blocks"
```

---

## Task 10: Full verification

- [ ] **Step 1: Run the ClarcCore test suite**

Run: `cd Packages && swift build --target ClarcCore 2>&1 | tail -10`
Expected: BUILD SUCCEEDS.

(This machine has only CommandLineTools — `swift test` cannot resolve the `Testing` module. Tests run on a full-Xcode machine via `xcodebuild test`. The library build is the gate we can run locally.)

- [ ] **Step 2: Manual matrix**

Open the app, run a session, and verify:

1. Default state — open Settings, look at the chat. The card UI doesn't appear in the empty state.
2. Run a session that triggers the model to emit ```` ```json { "type": "task_update", "title": "X", "status": "running" } ``` ```` mid-message. A card appears with a spinner, "X" title, and a live duration.
3. The same model emits a follow-up with the same id and `status: "done"`. The card mutates in place (same start time), the icon becomes a green check, the duration freezes.
4. Click the chevron on a `.done` card → expands; click again → collapses.
5. Reload the session (Cmd+R or close-and-reopen the app) → cards re-render with the right state.
6. Open a pre-existing session (saved before this feature) → text still renders, no crash.
7. Tools can call `bridge.taskProgressStore?.start(...)` / `finish(...)` from Swift code → a card appears/disappears in the assistant's response.

- [ ] **Step 3: Defer push**

Per the saved memory `defer-push-task-update-ui`, do **not** `git push` at the end of this work. Stop after the local commits and wait for the user to confirm.

---

## Self-Review

**Spec coverage check** (each spec section → plan task):

| Spec section | Plan tasks |
|---|---|
| Data model: `TaskUpdateMessage` / `TaskFileChange` / `TaskTestResult` | Task 1 |
| `formatDuration(_:)` | Task 1 |
| `MessageBlock` extension | Task 2 |
| `TaskProgressStore` start/update/finish/fail | Task 5 |
| `TaskProgressStore.upsert(_:)` (returns `(wasNew, merged)`) | Task 5 |
| `TaskProgressStore.isExpanded` defaults + override | Task 5 |
| Parser: `parse(jsonObject:)` | Task 3 |
| Parser: `parse(xmlFragment:)` | Task 4 |
| Parser: `extract(from:)` code-fence / XML / bare-object | Tasks 3, 4 |
| Parser: auto-fill duration when done + endTime | Task 3 |
| `TaskUpdateCard` view with live duration | Task 6 |
| `WindowState.taskProgressStore` | Task 7 |
| `ChatBridge.taskProgressStore` | Task 7 |
| `MessageBubble` render branch | Task 8 |
| `AppState.processStream` extraction | Task 9 |
| Codable compatibility for old messages | Task 2 (`decodeIfPresent`) |
| `formatDuration` negative input clamps | Task 1 |
| Tests for parser, store, formatDuration | Tasks 1, 3, 4, 5 |

All spec sections covered.

**Placeholder scan:** No "TBD" / "TODO" / "implement later" patterns. Every code step includes the full code. Every command includes expected output. The `extractXML` stub in Task 3 is explicit and replaced in Task 4.

**Type consistency:**
- `TaskUpdateMessage` (Task 1) → used in Tasks 2, 3, 4, 5, 6, 8 ✓
- `TaskUpdateStatus.running/done/failed` (Task 1) → used in Tasks 3, 4, 5, 6 ✓
- `TaskFileChange` (Task 1) → used in Tasks 3, 4, 6 ✓
- `TaskTestResult` (Task 1) → used in Tasks 3, 4, 6 ✓
- `formatDuration(_:)` (Task 1) → used in Tasks 6 ✓
- `MessageBlock.taskUpdate` (Task 2) → used in Tasks 6, 8, 9 ✓
- `TaskUpdateParser.extract/parse` (Tasks 3, 4) → used in Task 9 ✓
- `TaskProgressStore` (Task 5) → used in Tasks 7, 8, 9 ✓
- `TaskProgressStore.upsert` returns `(wasNew: Bool, merged: TaskUpdateMessage)` (Task 5) → used in Task 9 ✓
- `WindowState.taskProgressStore` (Task 7) → used in Task 7 (AppState wiring) and Task 9 ✓
- `ChatBridge.taskProgressStore` (Task 7) → used in Task 8 ✓
- `TaskUpdateCard` (Task 6) → used in Task 8 ✓

No type drift detected.

**Test env note:** This repository's tests use Swift Testing (`@Test` / `#expect`). On a CommandLineTools-only toolchain (no full Xcode), `swift test` cannot resolve the `Testing` module and fails. The library build (`swift build --target ClarcCore`) is the gate we can verify locally. On a machine with full Xcode, `xcodebuild test` runs all tests including the new ones.

**Task 9 caveat:** The exact insertion point depends on the streaming state struct. The plan shows the right pattern but the implementer must inspect the surrounding code in `AppState.swift` to thread `windowState` into scope. If a `WindowState` isn't reachable at this site, the implementer should add a `windowState: WindowState?` field to the per-session state and populate it during window setup.
