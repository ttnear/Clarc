import Foundation
import ClarcCore
import os

actor RateLimitService {

    static let shared = RateLimitService()

    private let logger = Logger(subsystem: "com.claudework", category: "RateLimitService")

    private struct OAuthTokens {
        let accessToken: String
        let refreshToken: String?
        let rawOauth: [String: Any]
    }

    private var cached: RateLimitUsage?
    private var cachedAt: Date?
    private let cacheTTL: TimeInterval = 300  // 5 minutes
    private var authFailed = false

    /// Fetch current rate-limit usage.
    ///
    /// - Parameters:
    ///   - forceRefresh: bypass the 5-minute cache when true.
    ///   - customEndpoint: when non-nil, use this URL instead of the default
    ///     Anthropic oauth/usage endpoint.
    ///   - customBearerToken: when `customEndpoint` is set, this token is sent
    ///     in the `Authorization: Bearer <token>` header. Ignored when
    ///     `customEndpoint` is nil (the default endpoint always uses the
    ///     OAuth access token read from Keychain).
    ///   - customFiveHourPath: dotted JSON path inside the custom response
    ///     body that yields the 5h utilization (0-100). Defaults to
    ///     `five_hour.utilization` (Anthropic shape). Set to e.g.
    ///     `data.five_hour_plan_remains_percent` for a MiniMax-shaped
    ///     proxy.
    ///   - customSevenDayPath: see `customFiveHourPath` but for the 7d
    ///     window. Defaults to `seven_day.utilization`.
    func fetchUsage(
        forceRefresh: Bool = false,
        customEndpoint: String? = nil,
        customBearerToken: String? = nil,
        customFiveHourPath: String? = nil,
        customSevenDayPath: String? = nil
    ) async -> RateLimitUsage? {
        if !forceRefresh, let c = cached, let at = cachedAt, Date().timeIntervalSince(at) < cacheTTL {
            return c
        }

        // Custom endpoint path: skip OAuth / Keychain entirely. The user
        // supplied their own URL and bearer; we just hit it.
        if let endpoint = customEndpoint, !endpoint.isEmpty {
            return await callAPI(
                token: customBearerToken ?? "",
                urlOverride: endpoint,
                isCustom: true,
                fiveHourPath: customFiveHourPath,
                sevenDayPath: customSevenDayPath
            )
        }

        if authFailed && !forceRefresh {
            return cached
        }

        guard let tokens = await readOAuthTokens() else {
            logger.debug("[RateLimit] OAuth token not found in Keychain")
            return cached
        }

        // If the token is expired, attempt to refresh it first
        let accessToken: String
        if isExpired(tokens.rawOauth) {
            logger.info("[RateLimit] Access token expired, attempting refresh...")
            if let refreshed = await refreshAccessToken(tokens) {
                accessToken = refreshed
            } else {
                logger.debug("[RateLimit] Token refresh failed, cannot fetch usage")
                authFailed = true
                return cached
            }
        } else {
            accessToken = tokens.accessToken
        }

        logger.info("[RateLimit] Token ready, calling API...")

        guard let usage = await callAPI(
            token: accessToken,
            urlOverride: nil,
            isCustom: false,
            fiveHourPath: customFiveHourPath,
            sevenDayPath: customSevenDayPath
        ) else {
            logger.debug("[RateLimit] API call returned nil")
            return cached
        }
        logger.info("[RateLimit] 5h=\(usage.fiveHourPercent)% 7d=\(usage.sevenDayPercent)%")

        authFailed = false
        cached = usage
        cachedAt = Date()
        return usage
    }

    // MARK: - Keychain

    private func readOAuthTokens() async -> OAuthTokens? {
        guard let raw = await MainActor.run(body: { KeychainHelper.readString(service: "Claude Code-credentials") }) else {
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String
        else { return nil }

        let refreshToken = oauth["refreshToken"] as? String
        return OAuthTokens(accessToken: accessToken, refreshToken: refreshToken, rawOauth: oauth)
    }

    private func isExpired(_ oauth: [String: Any]) -> Bool {
        guard let expiresAt = oauth["expiresAt"] else { return false }

        var expiryDate: Date?
        if let ms = expiresAt as? Double {
            let seconds = ms > 1e10 ? ms / 1000 : ms
            expiryDate = Date(timeIntervalSince1970: seconds)
        } else if let str = expiresAt as? String {
            expiryDate = Self.isoFormatter.date(from: str) ?? Self.isoFormatterFallback.date(from: str)
        }
        guard let expiry = expiryDate else { return false }
        // Consider expired 30 seconds before the actual expiry
        return Date() >= expiry.addingTimeInterval(-30)
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(_ tokens: OAuthTokens) async -> String? {
        guard let refreshToken = tokens.refreshToken else {
            logger.debug("[RateLimit] No refresh token available")
            return nil
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/token") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.debug("[RateLimit] Token refresh returned status \(code)")
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String
            else {
                logger.debug("[RateLimit] Token refresh response parse failed")
                return nil
            }

            logger.info("[RateLimit] Token refreshed successfully")
            // Skip Keychain write since account is unknown — use in-memory cache only
            return newAccessToken
        } catch {
            logger.debug("[RateLimit] Token refresh error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - API

    /// Hit either the default Anthropic oauth/usage endpoint or a user-supplied
    /// custom endpoint. The default Anthropic response shape is:
    /// `{ "five_hour": { "utilization": <0-100>, "resets_at": "..." },
    ///    "seven_day": { "utilization": <0-100>, "resets_at": "..." } }`
    /// Custom endpoints can be normalized by passing dotted JSON paths
    /// via `fiveHourPath` / `sevenDayPath` (defaults preserved).
    ///
    /// - Parameters:
    ///   - token: bearer token. Required for the default endpoint (OAuth
    ///     access token); optional for custom endpoints (skipped if empty).
    ///   - urlOverride: when non-nil, use this URL instead of the default
    ///     Anthropic endpoint.
    ///   - isCustom: true when `urlOverride` is a user-supplied custom URL.
    ///     In that case we do not send the `anthropic-beta` header (which
    ///     is Anthropic-specific) and do not auth-fail on 401.
    ///   - fiveHourPath: dotted JSON path to the 5h utilization number
    ///     (0-100). Defaults to `five_hour.utilization`.
    ///   - sevenDayPath: see `fiveHourPath` but for 7d. Defaults to
    ///     `seven_day.utilization`.
    private func callAPI(
        token: String,
        urlOverride: String?,
        isCustom: Bool,
        fiveHourPath: String? = nil,
        sevenDayPath: String? = nil
    ) async -> RateLimitUsage? {
        let resolvedURL: String = urlOverride ?? "https://api.anthropic.com/api/oauth/usage"
        guard let url = URL(string: resolvedURL) else {
            logger.warning("[RateLimit] Invalid URL: \(resolvedURL, privacy: .public)")
            return nil
        }

        var request = URLRequest(url: url)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Only the default Anthropic endpoint understands the beta header.
        if !isCustom {
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                if code == 401 && !isCustom {
                    logger.debug("[RateLimit] API returned 401 — token invalid")
                    authFailed = true
                } else {
                    logger.warning("[RateLimit] API returned status \(code) for \(isCustom ? "custom" : "default") endpoint")
                }
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("[RateLimit] Response is not a JSON object")
                return nil
            }

            let fiveHourValue = lookupNumeric(
                in: json,
                path: fiveHourPath ?? "five_hour.utilization"
            )
            let sevenDayValue = lookupNumeric(
                in: json,
                path: sevenDayPath ?? "seven_day.utilization"
            )
            let fiveHourResetsAt = lookupString(
                in: json,
                path: "five_hour.resets_at"
            ).flatMap(parseISO8601)
            let sevenDayResetsAt = lookupString(
                in: json,
                path: "seven_day.resets_at"
            ).flatMap(parseISO8601)

            return RateLimitUsage(
                fiveHourPercent: fiveHourValue ?? 0,
                sevenDayPercent: sevenDayValue ?? 0,
                fiveHourResetsAt: fiveHourResetsAt,
                sevenDayResetsAt: sevenDayResetsAt
            )
        } catch {
            logger.error("Rate limit fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Walk a dotted JSON path inside a JSON object and return the
    /// numeric value at that leaf, if any. Components are matched
    /// against dictionary keys; if any segment is missing or the leaf
    /// is not numeric, returns nil. Handles both `Int` and `Double`
    /// JSON numbers and treats `NSNumber`-wrapped values uniformly.
    private func lookupNumeric(in root: [String: Any], path: String) -> Double? {
        let segments = path.split(separator: ".").map(String.init)
        var current: Any = root
        for segment in segments {
            if let dict = current as? [String: Any], let next = dict[segment] {
                current = next
            } else {
                return nil
            }
        }
        if let d = (current as? NSNumber)?.doubleValue {
            return d
        }
        if let i = current as? Int { return Double(i) }
        if let d = current as? Double { return d }
        return nil
    }

    /// Walk a dotted JSON path and return the string at the leaf, if
    /// the leaf is a `String`. Otherwise nil.
    private func lookupString(in root: [String: Any], path: String) -> String? {
        let segments = path.split(separator: ".").map(String.init)
        var current: Any = root
        for segment in segments {
            if let dict = current as? [String: Any], let next = dict[segment] {
                current = next
            } else {
                return nil
            }
        }
        return current as? String
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterFallback = ISO8601DateFormatter()

    private func parseISO8601(_ str: String?) -> Date? {
        guard let str else { return nil }
        return Self.isoFormatter.date(from: str) ?? Self.isoFormatterFallback.date(from: str)
    }
}
