import Testing
@testable import ClarcCore

@Suite("JSONPath")
struct JSONPathTests {

    // MARK: Parser

    @Test("Empty path parses as root")
    func emptyPath() throws {
        #expect(try JSONPathParser.parse("") == .root)
    }

    @Test("Single key parses as key(\"a\", root)")
    func singleKey() throws {
        #expect(try JSONPathParser.parse("a") == .key("a", .root))
    }

    @Test("Dotted keys chain")
    func dottedKeys() throws {
        #expect(try JSONPathParser.parse("a.b.c") == .key("c", .key("b", .key("a", .root))))
    }

    @Test("Dot-number indexes an array")
    func dotIndex() throws {
        #expect(try JSONPathParser.parse("a.0.b") == .key("b", .index(0, .key("a", .root))))
    }

    @Test("Bracket index is equivalent to dot-index")
    func bracketIndex() throws {
        #expect(try JSONPathParser.parse("a[0].b") == .key("b", .index(0, .key("a", .root))))
    }

    @Test("Predicate selects an array element by key=value")
    func predicate() throws {
        #expect(try JSONPathParser.parse("a[@k=v].x")
            == .key("x", .predicate("k", "v", .key("a", .root))))
    }

    @Test("Missing close bracket throws")
    func unclosedBracket() {
        #expect(throws: JSONPathParseError.self) {
            _ = try JSONPathParser.parse("a[0")
        }
    }

    @Test("Predicate without @ throws")
    func predicateNoMarker() {
        #expect(throws: JSONPathParseError.self) {
            _ = try JSONPathParser.parse("a[k=v].x")
        }
    }

    // MARK: Lookup

    private func makeObject(_ pairs: (String, JSONValue)...) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: pairs))
    }

    @Test("Lookup walks dotted keys")
    func lookupDotted() throws {
        let json = makeObject(("a", makeObject(("b", .number(42)))))
        let path = try JSONPathParser.parse("a.b")
        #expect(path.lookup(in: json) == .number(42))
    }

    @Test("Lookup walks dot-index into array")
    func lookupDotIndex() throws {
        let json = makeObject(("a", .array([.number(1), .number(2)])))
        let path = try JSONPathParser.parse("a.1")
        #expect(path.lookup(in: json) == .number(2))
    }

    @Test("Lookup walks bracket-index")
    func lookupBracketIndex() throws {
        let json = makeObject(("a", .array([.string("x"), .string("y")])))
        let path = try JSONPathParser.parse("a[0]")
        #expect(path.lookup(in: json) == .string("x"))
    }

    @Test("Lookup with predicate picks matching element")
    func lookupPredicate() throws {
        let elements: [JSONValue] = [
            makeObject(("name", .string("a")), ("v", .number(1))),
            makeObject(("name", .string("b")), ("v", .number(2))),
        ]
        let json = makeObject(("items", .array(elements)))
        let path = try JSONPathParser.parse("items[@name=b].v")
        #expect(path.lookup(in: json) == .number(2))
    }

    @Test("Lookup returns nil when key missing")
    func lookupMissing() throws {
        let path = try JSONPathParser.parse("a.b")
        #expect(path.lookup(in: .object(["x": .number(1)])) == nil)
    }

    @Test("Lookup returns nil when index out of range")
    func lookupOutOfRange() throws {
        let path = try JSONPathParser.parse("a.5")
        #expect(path.lookup(in: makeObject(("a", .array([.number(1)])))) == nil)
    }
}
