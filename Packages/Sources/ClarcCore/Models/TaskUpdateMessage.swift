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
