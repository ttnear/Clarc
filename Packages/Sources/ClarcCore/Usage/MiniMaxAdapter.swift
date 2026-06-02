import Foundation
import os

/// Adapter for the MiniMax token-plan endpoint. The endpoint returns
/// a `model_remains` array; we pick the element with `model_name ==
/// "general"`, falling back to the first element when not present.
/// Utilization is computed as `100 - current_*_remaining_percent`.
public struct MiniMaxAdapter: UsageAdapter {

    private static let logger = Logger(subsystem: "com.claudework", category: "MiniMaxAdapter")

    public init() {}

    public func fetch(config: UsageQueryConfig) async throws -> UsageFetchOutcome {
        let urlString = config.endpoint ?? UsageProvider.minimax.defaultEndpoint!
        guard let url = URL(string: urlString) else { throw UsageError.invalidURL }

        var request = URLRequest(url: url)
        if let token = config.bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.http(status: -1, body: data)
        }
        guard http.statusCode == 200 else {
            throw UsageError.http(status: http.statusCode, body: data)
        }
        return try Self.parseResponse(data: data, httpStatus: 200, endpointURL: urlString)
    }

    /// Pure parser, exposed for tests. Element selection and field
    /// mapping live here so they can be exercised without HTTP.
    public static func parseResponse(
        data: Data,
        httpStatus: Int,
        endpointURL: String
    ) throws -> UsageFetchOutcome {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["model_remains"] as? [[String: Any]],
              let element = pickElement(arr) else {
            throw UsageError.missingField("model_remains")
        }

        guard let intervalRemain = numericValue(element["current_interval_remaining_percent"]) else {
            throw UsageError.missingField("model_remains[].current_interval_remaining_percent")
        }
        guard let weeklyRemain = numericValue(element["current_weekly_remaining_percent"]) else {
            throw UsageError.missingField("model_remains[].current_weekly_remaining_percent")
        }

        let fiveHour = clampUtilization(100 - intervalRemain)
        let sevenDay = clampUtilization(100 - weeklyRemain)
        let fiveHourResetsAt = parseMilliseconds(element["end_time"])
        let sevenDayResetsAt = parseMilliseconds(element["weekly_end_time"])

        let usage = RateLimitUsage(
            fiveHourPercent: fiveHour,
            sevenDayPercent: sevenDay,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt
        )
        return UsageFetchOutcome(usage: usage, rawJSON: data, httpStatus: httpStatus, endpointURL: endpointURL)
    }

    private static func pickElement(_ arr: [[String: Any]]) -> [String: Any]? {
        if let general = arr.first(where: { ($0["model_name"] as? String) == "general" }) {
            return general
        }
        return arr.first
    }

    private static func numericValue(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func clampUtilization(_ v: Double) -> Double {
        if v < 0 {
            logger.warning("MiniMax utilization < 0 after inversion, clamping: \(v)")
            return 0
        }
        if v > 100 {
            logger.warning("MiniMax utilization > 100 after inversion, clamping: \(v)")
            return 100
        }
        return v
    }

    private static func parseMilliseconds(_ v: Any?) -> Date? {
        guard let n = v as? NSNumber else { return nil }
        let ms = n.doubleValue
        guard ms.isFinite, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
