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
        // fresh UUIDs that are not pre-existing
        #expect(update1.id != UUID())
        #expect(update2.id != UUID())
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
}
