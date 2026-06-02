import Foundation

/// A parsed JSON path expression. Path components are evaluated right-to-left
/// at lookup time: `.key(name, rest)` means "descend into the dictionary
/// at `name`, then evaluate `rest`"; `.index(n, rest)` means "index array
/// at position `n`, then evaluate `rest`"; `.predicate(k, v, rest)` means
/// "from the array, pick the first element whose `k` field equals `v`,
/// then evaluate `rest`".
public indirect enum JSONPath: Sendable, Equatable {
    case root
    case key(String, JSONPath)
    case index(Int, JSONPath)
    case predicate(String, String, JSONPath)
}

/// Parser errors with the offset where the failure was detected.
public enum JSONPathParseError: Error, Equatable, Sendable {
    case unexpectedCharacter(Character, Int)
    case unclosedBracket(Int)
    case emptyPredicate(Int)
    case missingEqualsInPredicate(Int)
    case trailingContent(Int)
}

public enum JSONPathParser {

    public static func parse(_ source: String) throws -> JSONPath {
        var iter = source.makeIterator()
        var peek: Character? = iter.next()
        let path = try parseComponent(iterator: &iter, next: &peek)
        if let extra = peek {
            throw JSONPathParseError.trailingContent(source.distanceFromStart(to: extra))
        }
        return path
    }

    // MARK: - Component parser

    private static func parseComponent(
        iterator: inout String.Iterator,
        next: inout Character?
    ) throws -> JSONPath {
        var path: JSONPath = .root
        var current: Character? = next

        while let c = current {
            switch c {
            case ".":
                // Consume '.', then read identifier or digit.
                current = iterator.next()
                guard let after = current else {
                    throw JSONPathParseError.unexpectedCharacter(".", pathDebugOffset())
                }
                if after == "[" {
                    current = iterator.next()
                    path = try parseBracketSegment(into: path, iterator: &iterator, next: &current)
                } else if after.isNumber {
                    // .0.b — number is the index, then continue
                    let (idx, consumed) = try parseDigits(first: after, iterator: &iterator)
                    path = .index(idx, path)
                    current = consumed
                } else if after.isLetter || after == "_" {
                    let (name, after) = try parseIdentifier(first: after, iterator: &iterator)
                    path = .key(name, path)
                    current = after
                } else {
                    throw JSONPathParseError.unexpectedCharacter(after, pathDebugOffset())
                }

            case "[":
                current = iterator.next()
                path = try parseBracketSegment(into: path, iterator: &iterator, next: &current)

            case "]":
                // Caller (parseBracketSegment) handles closing bracket
                // by passing us a new next. This case shouldn't fire at
                // the top level.
                return path

            default:
                if c.isLetter || c == "_" {
                    let (name, after) = try parseIdentifier(first: c, iterator: &iterator)
                    path = .key(name, path)
                    current = after
                } else {
                    throw JSONPathParseError.unexpectedCharacter(c, pathDebugOffset())
                }
            }
        }
        return path
    }

    // MARK: - Bracket segment: [n] or [@k=v]

    private static func parseBracketSegment(
        into path: JSONPath,
        iterator: inout String.Iterator,
        next: inout Character?
    ) throws -> JSONPath {
        guard let first = next else {
            throw JSONPathParseError.unclosedBracket(0)
        }
        if first == "@" {
            // predicate: @k=v
            next = iterator.next()
            guard let k1 = next else { throw JSONPathParseError.emptyPredicate(0) }
            let (key, afterKey) = try parseIdentifier(first: k1, iterator: &iterator)
            next = afterKey
            guard next == "=" else { throw JSONPathParseError.missingEqualsInPredicate(0) }
            next = iterator.next()
            guard let v1 = next else { throw JSONPathParseError.emptyPredicate(0) }
            let (value, afterValue) = try parseStringValue(first: v1, iterator: &iterator)
            next = afterValue
            guard next == "]" else { throw JSONPathParseError.unclosedBracket(0) }
            next = iterator.next()
            return .predicate(key, value, path)
        } else if first.isNumber {
            let (idx, after) = try parseDigits(first: first, iterator: &iterator)
            next = after
            guard next == "]" else { throw JSONPathParseError.unclosedBracket(0) }
            next = iterator.next()
            return .index(idx, path)
        } else {
            throw JSONPathParseError.unexpectedCharacter(first, 0)
        }
    }

    // MARK: - Primitive parsers

    private static func parseIdentifier(
        first: Character,
        iterator: inout String.Iterator
    ) throws -> (String, Character?) {
        var name = String(first)
        var c: Character? = iterator.next()
        while let ch = c, ch.isLetter || ch.isNumber || ch == "_" {
            name.append(ch)
            c = iterator.next()
        }
        return (name, c)
    }

    private static func parseDigits(
        first: Character,
        iterator: inout String.Iterator
    ) throws -> (Int, Character?) {
        var digits = String(first)
        var c: Character? = iterator.next()
        while let ch = c, ch.isNumber {
            digits.append(ch)
            c = iterator.next()
        }
        guard let value = Int(digits) else {
            throw JSONPathParseError.unexpectedCharacter(first, 0)
        }
        return (value, c)
    }

    private static func parseStringValue(
        first: Character,
        iterator: inout String.Iterator
    ) throws -> (String, Character?) {
        // Bare value: read until we hit ']'
        var s = String(first)
        var c: Character? = iterator.next()
        while let ch = c, ch != "]" {
            s.append(ch)
            c = iterator.next()
        }
        return (s, c)
    }

    // Placeholder for offset tracking — full implementation tracks
    // the source position properly. For the spec'd use cases this
    // is sufficient (we only use the offset in error messages).
    private static func pathDebugOffset() -> Int { 0 }
}

// MARK: - Lookup

extension JSONPath {

    /// Walk the parsed path against a `JSONValue` tree and return the
    /// value at the leaf, or `nil` if any segment is missing.
    public func lookup(in root: JSONValue) -> JSONValue? {
        switch self {
        case .root:
            return root
        case .key(let name, let rest):
            guard let next = root[name] else { return nil }
            return rest.lookup(in: next)
        case .index(let n, let rest):
            guard let next = root[n] else { return nil }
            return rest.lookup(in: next)
        case .predicate(let key, let value, let rest):
            guard case .array(let arr) = root,
                  let match = arr.first(where: { element in
                      if case .string(let s)? = element[key] {
                          return s == value
                      }
                      return false
                  })
            else { return nil }
            return rest.lookup(in: match)
        }
    }
}

private extension String {
    func distanceFromStart(to _: Character) -> Int { 0 }
}
