import Testing
import Foundation
@testable import ClarcCore

// Mapping the same jsonl lines twice must yield identical ChatMessages —
// otherwise reloadCommittedFromDisk replaces the whole committed list on every
// reload (IDs differ → Equatable mismatch), forcing SwiftUI to rebuild every row
// and visibly flicker the chat. Message identity must derive from the CLI line's
// stable `uuid`, not a fresh random UUID per parse.

@Suite("CLILineToBlocksMapper deterministic identity")
struct CLILineToBlocksMapperTests {

    private func decodeLines(_ json: String) throws -> [CLISessionLine] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try json.split(separator: "\n").map {
            try decoder.decode(CLISessionLine.self, from: Data($0.utf8))
        }
    }

    private let sample = """
    {"type":"user","uuid":"11111111-1111-1111-1111-111111111111","timestamp":"2026-06-02T10:00:00Z","message":{"role":"user","content":"hello"}}
    {"type":"assistant","uuid":"22222222-2222-2222-2222-222222222222","timestamp":"2026-06-02T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"hi there"}]}}
    """

    @Test("Re-mapping identical lines produces identical messages (IDs stable)")
    func stableAcrossReparse() throws {
        let lines = try decodeLines(sample)
        let first = CLILineToBlocksMapper.map(lines: lines)
        let second = CLILineToBlocksMapper.map(lines: lines)
        #expect(first == second)
    }

    @Test("Message and text-block IDs derive from the CLI line uuid")
    func idsDeriveFromLineUuid() throws {
        let lines = try decodeLines(sample)
        let messages = CLILineToBlocksMapper.map(lines: lines)
        #expect(messages.count == 2)
        // Stable across reparse means non-empty, deterministic block IDs too.
        let blockIDs = messages.flatMap { $0.blocks.map(\.id) }
        let remapped = CLILineToBlocksMapper.map(lines: lines).flatMap { $0.blocks.map(\.id) }
        #expect(blockIDs == remapped)
    }
}
