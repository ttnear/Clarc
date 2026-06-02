import Foundation
import Testing
@testable import ClarcCore

@Suite("CustomAdapter")
struct CustomAdapterTests {

    @Test("Walks dotted key path and returns numeric value")
    func dottedKey() async throws {
        let data = #"{"five_hour": {"utilization": 42}, "seven_day": {"utilization": 7}}"#.data(using: .utf8)!
        let outcome = try await CustomAdapter.parseResponse(
            data: data,
            httpStatus: 200,
            endpointURL: "x",
            fiveHourPath: "five_hour.utilization",
            sevenDayPath: "seven_day.utilization"
        )
        #expect(outcome.usage.fiveHourPercent == 42)
        #expect(outcome.usage.sevenDayPercent == 7)
    }

    @Test("Walks bracket index into array")
    func bracketIndex() async throws {
        let data = #"{"values": [{"v": 10}, {"v": 20}]}"#.data(using: .utf8)!
        let outcome = try await CustomAdapter.parseResponse(
            data: data,
            httpStatus: 200,
            endpointURL: "x",
            fiveHourPath: "values[1].v",
            sevenDayPath: "values[0].v"
        )
        #expect(outcome.usage.fiveHourPercent == 20)
        #expect(outcome.usage.sevenDayPercent == 10)
    }

    @Test("Missing path throws UsageError.missingField")
    func missingPath() async {
        let data = #"{"a": 1}"#.data(using: .utf8)!
        await #expect(throws: UsageError.self) {
            _ = try await CustomAdapter.parseResponse(
                data: data, httpStatus: 200, endpointURL: "x",
                fiveHourPath: "a.b", sevenDayPath: "a"
            )
        }
    }

    @Test("Non-numeric leaf throws UsageError.missingField")
    func nonNumericLeaf() async {
        let data = #"{"a": "hello"}"#.data(using: .utf8)!
        await #expect(throws: UsageError.self) {
            _ = try await CustomAdapter.parseResponse(
                data: data, httpStatus: 200, endpointURL: "x",
                fiveHourPath: "a", sevenDayPath: "a"
            )
        }
    }

    @Test("Reset times are not parsed (Custom adapter returns nil resets)")
    func noResets() async throws {
        let data = #"{"a": 5, "b": 7}"#.data(using: .utf8)!
        let outcome = try await CustomAdapter.parseResponse(
            data: data, httpStatus: 200, endpointURL: "x",
            fiveHourPath: "a", sevenDayPath: "b"
        )
        #expect(outcome.usage.fiveHourResetsAt == nil)
        #expect(outcome.usage.sevenDayResetsAt == nil)
    }
}
