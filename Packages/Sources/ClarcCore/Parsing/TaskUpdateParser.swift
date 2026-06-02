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

    private static func parseDate(_ v: JSONValue?) -> Date? {
        guard case .string(let s) = v else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let basic = ISO8601DateFormatter()
        return basic.date(from: s)
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
        case "filesChanged":
            inFilesContainer = true
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
        case "testResults":
            inTestsContainer = true
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
        // We need to know the parent; elementStack still contains the parent at this point
        // because we pop AFTER this switch.
        let parent = elementStack.dropLast().last
        switch elementName {
        case "summary" where parent == "task-update":
            summary = trimmed
        case "details" where parent == "task-update":
            details = trimmed
        default:
            break
        }
        if elementName == "filesChanged" { inFilesContainer = false }
        if elementName == "testResults" { inTestsContainer = false }
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
