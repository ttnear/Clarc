import Foundation
import Testing
@testable import ClarcCore

@Suite("MiniMaxAdapter")
struct MiniMaxAdapterTests {

    private let sampleWithGeneral = """
    {
      "model_remains": [
        { "model_name": "other", "current_interval_remaining_percent": 70, "current_weekly_remaining_percent": 80,
          "end_time": 1748889600000, "weekly_end_time": 1750108800000 },
        { "model_name": "general", "current_interval_remaining_percent": 98, "current_weekly_remaining_percent": 100,
          "end_time": 1748889600000, "weekly_end_time": 1750108800000 }
      ]
    }
    """.data(using: .utf8)!

    private let sampleNoGeneral = """
    {
      "model_remains": [
        { "model_name": "alpha", "current_interval_remaining_percent": 50, "current_weekly_remaining_percent": 60,
          "end_time": 1748889600000, "weekly_end_time": 1750108800000 }
      ]
    }
    """.data(using: .utf8)!

    private let sampleMissingReset = """
    {
      "model_remains": [
        { "model_name": "general", "current_interval_remaining_percent": 98, "current_weekly_remaining_percent": 100 }
      ]
    }
    """.data(using: .utf8)!

    @Test("Prefers the element with model_name == \"general\"")
    func preferGeneral() async throws {
        let outcome = try await MiniMaxAdapter.parseResponse(
            data: sampleWithGeneral, httpStatus: 200, endpointURL: "x"
        )
        #expect(outcome.usage.fiveHourPercent == 2.0)   // 100 - 98
        #expect(outcome.usage.sevenDayPercent == 0.0)   // 100 - 100
    }

    @Test("Falls back to first element when no general")
    func fallbackFirst() async throws {
        let outcome = try await MiniMaxAdapter.parseResponse(
            data: sampleNoGeneral, httpStatus: 200, endpointURL: "x"
        )
        #expect(outcome.usage.fiveHourPercent == 50.0)
        #expect(outcome.usage.sevenDayPercent == 40.0)
    }

    @Test("Reset times are parsed from ms timestamps to Date")
    func parseResetTimes() async throws {
        let outcome = try await MiniMaxAdapter.parseResponse(
            data: sampleWithGeneral, httpStatus: 200, endpointURL: "x"
        )
        let expected = Date(timeIntervalSince1970: 1748889600)
        #expect(outcome.usage.fiveHourResetsAt == expected)
    }

    @Test("Missing reset fields are nil, not an error")
    func missingReset() async throws {
        let outcome = try await MiniMaxAdapter.parseResponse(
            data: sampleMissingReset, httpStatus: 200, endpointURL: "x"
        )
        #expect(outcome.usage.fiveHourResetsAt == nil)
        #expect(outcome.usage.sevenDayResetsAt == nil)
    }

    @Test("Missing utilization throws UsageError.missingField")
    func missingUtilization() async {
        let data = """
        { "model_remains": [
          { "model_name": "general" }
        ]}
        """.data(using: .utf8)!
        await #expect(throws: UsageError.self) {
            _ = try await MiniMaxAdapter.parseResponse(
                data: data, httpStatus: 200, endpointURL: "x"
            )
        }
    }

    @Test("Out-of-range utilization is clamped to 0-100")
    func clampOutOfRange() async throws {
        let data = """
        { "model_remains": [
          { "model_name": "general", "current_interval_remaining_percent": -10, "current_weekly_remaining_percent": 200 }
        ]}
        """.data(using: .utf8)!
        let outcome = try await MiniMaxAdapter.parseResponse(
            data: data, httpStatus: 200, endpointURL: "x"
        )
        // 100 - (-10) = 110 → clamp to 100; 100 - 200 = -100 → clamp to 0
        #expect(outcome.usage.fiveHourPercent == 100.0)
        #expect(outcome.usage.sevenDayPercent == 0.0)
    }
}
