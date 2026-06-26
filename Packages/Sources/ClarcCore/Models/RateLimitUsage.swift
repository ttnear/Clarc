import Foundation

/// Rate limit usage data passed through ChatBridge to avoid direct RateLimitService dependency in ClarcChatKit.
public struct RateLimitUsage: Sendable, Codable {
    public let fiveHourPercent: Double
    public let sevenDayPercent: Double
    public let fiveHourResetsAt: Date?
    public let sevenDayResetsAt: Date?

    public init(
        fiveHourPercent: Double,
        sevenDayPercent: Double,
        fiveHourResetsAt: Date?,
        sevenDayResetsAt: Date?
    ) {
        self.fiveHourPercent = fiveHourPercent
        self.sevenDayPercent = sevenDayPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayResetsAt = sevenDayResetsAt
    }
}
