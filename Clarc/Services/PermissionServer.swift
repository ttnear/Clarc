import Foundation
import ClarcCore
import Network
import os

// MARK: - PermissionServer

/// An actor that runs a local HTTP server using NWListener to receive
/// PreToolUse hook requests from the Claude CLI and hold connections
/// open until the UI responds with allow/deny.
actor PermissionServer {

    // MARK: - Constants

    private static let basePort: UInt16 = 19836
    private static let maxPort: UInt16 = 19846
    private static let timeoutSeconds: UInt64 = 300 // 5 minutes

    // MARK: - Properties

    private var listener: NWListener?
    private(set) var port: UInt16 = PermissionServer.basePort
    private let appSecret = UUID().uuidString
    private var runToken = UUID().uuidString
    private let logger = Logger(subsystem: "com.claudework", category: "PermissionServer")

    /// toolUseId → the continuations and routing context for that request.
    /// On CLI retry, multiple continuations may accumulate under the same toolUseId.
    private struct Pending {
        var continuations: [CheckedContinuation<PermissionDecision, Never>]
        let sessionId: String?
        let toolName: String
    }
    private var pending: [String: Pending] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    /// Session-scope allow keys. When a session is allowed, all tools in that session are auto-approved.
    private var scopedAllows: Set<String> = []

    private static func sessionKey(_ sessionId: String) -> String {
        "session:\(sessionId)"
    }

    /// Per-subscriber broadcast continuations. One is issued per window via subscribe().
    private var subscribers: [UUID: AsyncStream<PermissionRequest>.Continuation] = [:]

    // MARK: - Init

    init() {}

    // MARK: - Subscription

    /// Called by a UI window to subscribe to the permission request stream. Must unsubscribe using the returned token.
    func subscribe() -> (token: UUID, stream: AsyncStream<PermissionRequest>) {
        let token = UUID()
        let stream = AsyncStream<PermissionRequest> { continuation in
            self.subscribers[token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unsubscribe(token: token) }
            }
        }
        return (token, stream)
    }

    func unsubscribe(token: UUID) {
        subscribers.removeValue(forKey: token)?.finish()
    }

    private func broadcast(_ request: PermissionRequest) {
        for continuation in subscribers.values {
            continuation.yield(request)
        }
    }

    // MARK: - Lifecycle

    /// Start the TCP listener, auto-incrementing the port on conflict.
    func start() async throws {
        for candidatePort in Self.basePort...Self.maxPort {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredInterfaceType = .loopback
                let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: candidatePort)!)
                self.port = candidatePort
                self.listener = l

                // Use a detached task to handle state updates since NWListener
                // callbacks are on an internal queue.
                let serverPort = candidatePort
                let logger = self.logger

                l.stateUpdateHandler = { [weak l] state in
                    switch state {
                    case .ready:
                        logger.info("PermissionServer listening on port \(serverPort)")
                    case .failed(let error):
                        logger.error("Listener failed: \(error.localizedDescription)")
                        l?.cancel()
                    default:
                        break
                    }
                }

                l.newConnectionHandler = { [weak self] connection in
                    guard let self else { return }
                    Task { await self.handleConnection(connection) }
                }

                l.start(queue: .global(qos: .userInitiated))
                logger.info("Attempting to listen on port \(serverPort)")
                return
            } catch {
                logger.warning("Port \(candidatePort) unavailable, trying next…")
                continue
            }
        }
        throw PermissionServerError.noAvailablePort
    }

    /// Stop the listener and deny all pending requests.
    func stop() {
        listener?.cancel()
        listener = nil

        for (id, entry) in pending {
            logger.info("Denying \(entry.continuations.count) pending request(s) for \(id) on server stop")
            for continuation in entry.continuations {
                continuation.resume(returning: .deny)
            }
        }
        pending.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    // MARK: - Public API

    /// Called by the UI when the user makes a decision.
    func respond(toolUseId: String, decision: PermissionDecision) {
        timeoutTasks.removeValue(forKey: toolUseId)?.cancel()

        guard let entry = pending.removeValue(forKey: toolUseId) else {
            logger.warning("No pending continuation for toolUseId \(toolUseId)")
            return
        }

        let resolved: PermissionDecision
        if decision == .allowSession {
            if let sid = entry.sessionId {
                scopedAllows.insert(Self.sessionKey(sid))
                logger.info("Session-allowed all tools for \(sid.prefix(8))")
            } else {
                logger.warning("allowSession without sessionId for \(toolUseId) — falling back to allow")
            }
            resolved = .allow
        } else {
            resolved = decision
        }

        for continuation in entry.continuations {
            continuation.resume(returning: resolved)
        }
    }

    // MARK: - Auto-approve

    /// Determines whether the request should be auto-approved. Returns a reason string if approved, or nil otherwise.
    private func autoApproveReason(for req: HookRequestBody) -> String? {
        if let sid = req.sessionId,
           scopedAllows.contains(Self.sessionKey(sid)) {
            return "Allowed for session by user"
        }

        if req.toolName == "Bash",
           let command = req.toolInput["command"]?.stringValue,
           BashSafety.isSafeReadOnly(command: command) {
            return "Safe read-only command"
        }

        return nil
    }

    /// Refresh the run token (call at the start of each CLI session).
    func refreshRunToken() {
        runToken = UUID().uuidString
    }

    /// The current run token for building the hook URL.
    func currentRunToken() -> String {
        runToken
    }

    // MARK: - Hook Settings

    /// Generate the hook settings JSON that should be passed to `claude --settings`.
    func generateHookSettings() -> String {
        let url = "http://127.0.0.1:\(port)/hook/pre-tool-use/\(appSecret)/\(runToken)"
        let settings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "^(Bash|Edit|Write|MultiEdit|mcp__.*)$",
                        "hooks": [
                            [
                                "type": "http",
                                "url": url,
                                "timeout": 300
                            ]
                        ]
                    ]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Write hook settings to a temporary file and return its path.
    func writeHookSettingsFile() throws -> String {
        let json = generateHookSettings()
        let tempDir = FileManager.default.temporaryDirectory
        let filePath = tempDir.appendingPathComponent("claudework-hooks-\(UUID().uuidString).json")
        try json.write(to: filePath, atomically: true, encoding: .utf8)
        return filePath.path
    }

    // MARK: - Connection Handling

    /// Handle a single inbound TCP connection.
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        Task {
            do {
                let rawRequest = try await readHTTPRequest(connection)
                let (method, path, body) = try parseHTTPRequest(rawRequest)

                guard method == "POST" else {
                    await sendHTTPResponse(connection, status: "405 Method Not Allowed", body: #"{"error":"method not allowed"}"#)
                    return
                }

                // Validate path: /hook/pre-tool-use/{appSecret}/{runToken}
                let components = path.split(separator: "/").map(String.init)
                guard components.count == 4,
                      components[0] == "hook",
                      components[1] == "pre-tool-use",
                      components[2] == appSecret,
                      components[3] == runToken else {
                    logger.warning("Invalid path or secret: \(path)")
                    await sendHTTPResponse(connection, status: "403 Forbidden", body: #"{"error":"invalid path"}"#)
                    return
                }

                // Parse the JSON body.
                guard let bodyData = body.data(using: .utf8) else {
                    await sendHTTPResponse(connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
                    return
                }

                let hookRequest = try JSONDecoder().decode(HookRequestBody.self, from: bodyData)

                if let autoReason = autoApproveReason(for: hookRequest) {
                    try await sendHookResponse(connection, decision: "allow", reason: autoReason)
                    return
                }

                let permissionRequest = PermissionRequest(
                    id: hookRequest.toolUseId,
                    toolName: hookRequest.toolName,
                    toolInput: hookRequest.toolInput,
                    runToken: runToken
                )

                let decision = await waitForDecision(
                    toolUseId: hookRequest.toolUseId,
                    sessionId: hookRequest.sessionId,
                    toolName: hookRequest.toolName,
                    emit: permissionRequest
                )

                try await sendHookResponse(
                    connection,
                    decision: decision.rawValue,
                    reason: decision == .allow ? "User approved" : "User denied"
                )

            } catch {
                logger.error("Error handling connection: \(error.localizedDescription)")
                await sendHTTPResponse(connection, status: "500 Internal Server Error", body: #"{"error":"internal error"}"#)
            }
        }
    }

    /// Wait for a UI decision with a 5-minute timeout.
    /// The first requester emits to the UI stream and sets the timeout. CLI retries join the same entry.
    private func waitForDecision(
        toolUseId: String,
        sessionId: String?,
        toolName: String,
        emit request: PermissionRequest
    ) async -> PermissionDecision {
        let isFirst = pending[toolUseId] == nil
        if isFirst {
            broadcast(request)
        }

        let decision: PermissionDecision = await withCheckedContinuation { continuation in
            if var entry = pending[toolUseId] {
                entry.continuations.append(continuation)
                pending[toolUseId] = entry
            } else {
                pending[toolUseId] = Pending(
                    continuations: [continuation],
                    sessionId: sessionId,
                    toolName: toolName
                )
                timeoutTasks[toolUseId] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.cancelPendingIfNeeded(toolUseId: toolUseId)
                }
            }
        }
        timeoutTasks.removeValue(forKey: toolUseId)?.cancel()
        return decision
    }

    /// Remove and resume all pending continuations with .deny (timeout case).
    private func cancelPendingIfNeeded(toolUseId: String) {
        guard let entry = pending.removeValue(forKey: toolUseId) else { return }
        for continuation in entry.continuations {
            continuation.resume(returning: .deny)
        }
    }

    private func sendHookResponse(_ connection: NWConnection, decision: String, reason: String) async throws {
        let body = HookResponseBody(
            hookSpecificOutput: .init(
                hookEventName: "PreToolUse",
                permissionDecision: decision,
                permissionDecisionReason: reason
            )
        )
        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        await sendHTTPResponse(connection, status: "200 OK", body: json)
    }

    // MARK: - TCP / HTTP Helpers

    /// Read raw bytes from the connection until we have a complete HTTP request.
    private func readHTTPRequest(_ connection: NWConnection) async throws -> Data {
        var buffer = Data()
        let headerEnd = Data("\r\n\r\n".utf8)

        // Phase 1: Read until we find the end of headers.
        while !buffer.contains(headerEnd) {
            let chunk = try await readChunk(connection, maxLength: 8192)
            guard !chunk.isEmpty else { throw PermissionServerError.connectionClosed }
            buffer.append(chunk)
        }

        // Phase 2: If there's a Content-Length, read the body too.
        guard let headerRange = buffer.range(of: headerEnd) else {
            throw PermissionServerError.malformedRequest
        }
        let headerData = buffer[buffer.startIndex..<headerRange.lowerBound]
        let headerString = String(data: headerData, encoding: .utf8) ?? ""
        let contentLength = parseContentLength(from: headerString)

        if contentLength > 0 {
            let bodyStart = headerRange.upperBound
            let bodyBytesRead = buffer.count - buffer.distance(from: buffer.startIndex, to: bodyStart)
            var remaining = contentLength - bodyBytesRead
            while remaining > 0 {
                let chunk = try await readChunk(connection, maxLength: min(remaining, 8192))
                guard !chunk.isEmpty else { throw PermissionServerError.connectionClosed }
                buffer.append(chunk)
                remaining -= chunk.count
            }
        }

        return buffer
    }

    /// Read a single chunk from the connection.
    private func readChunk(_ connection: NWConnection, maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    /// Parse the HTTP request into method, path, and body.
    private func parseHTTPRequest(_ data: Data) throws -> (method: String, path: String, body: String) {
        let headerEnd = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: headerEnd) else {
            throw PermissionServerError.malformedRequest
        }

        let headerData = data[data.startIndex..<headerRange.lowerBound]
        let bodyData = data[headerRange.upperBound...]

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw PermissionServerError.malformedRequest
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw PermissionServerError.malformedRequest
        }

        // "POST /hook/pre-tool-use/{secret}/{token} HTTP/1.1"
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            throw PermissionServerError.malformedRequest
        }

        let method = parts[0]
        let path = parts[1]
        let body = String(data: bodyData, encoding: .utf8) ?? ""

        return (method, path, body)
    }

    /// Extract Content-Length from raw headers string.
    private func parseContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    /// Send a complete HTTP response and close the connection.
    private func sendHTTPResponse(_ connection: NWConnection, status: String, body: String) async {
        let bodyData = Data(body.utf8)
        let response = [
            "HTTP/1.1 \(status)",
            "Content-Type: application/json",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var payload = Data(response.utf8)
        payload.append(bodyData)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
                continuation.resume()
            })
        }
    }
}

// MARK: - Data Extension

private extension Data {
    nonisolated func contains(_ other: Data) -> Bool {
        range(of: other) != nil
    }
}

// MARK: - Request / Response Codables

/// The JSON body sent by the Claude CLI hook.
private struct HookRequestBody: Decodable {
    let hookEventName: String
    let toolName: String
    let toolInput: [String: JSONValue]
    let toolUseId: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case sessionId = "session_id"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try c.decode(String.self, forKey: .hookEventName)
        toolName = try c.decode(String.self, forKey: .toolName)
        toolInput = try c.decode([String: JSONValue].self, forKey: .toolInput)
        toolUseId = try c.decode(String.self, forKey: .toolUseId)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
    }
}

/// The JSON response body returned to the Claude CLI.
private struct HookResponseBody: Encodable {
    let hookSpecificOutput: HookOutput

    struct HookOutput: Encodable {
        let hookEventName: String
        let permissionDecision: String
        let permissionDecisionReason: String

        nonisolated func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(hookEventName, forKey: .hookEventName)
            try c.encode(permissionDecision, forKey: .permissionDecision)
            try c.encode(permissionDecisionReason, forKey: .permissionDecisionReason)
        }

        enum CodingKeys: String, CodingKey {
            case hookEventName, permissionDecision, permissionDecisionReason
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hookSpecificOutput, forKey: .hookSpecificOutput)
    }

    enum CodingKeys: String, CodingKey {
        case hookSpecificOutput
    }
}

// MARK: - Errors

enum PermissionServerError: LocalizedError {
    case noAvailablePort
    case connectionClosed
    case malformedRequest

    var errorDescription: String? {
        switch self {
        case .noAvailablePort: return "No available port in range 19836–19846"
        case .connectionClosed: return "Connection closed unexpectedly"
        case .malformedRequest: return "Malformed HTTP request"
        }
    }
}
