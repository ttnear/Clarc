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
