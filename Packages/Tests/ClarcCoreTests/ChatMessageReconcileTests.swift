import Testing
import Foundation
@testable import ClarcCore

// When a stream ends, reloadCommittedFromDisk replaces the live messages (random
// ids) with a fresh parse of the CLI jsonl (uuid-derived ids). reconcilingIdentity
// keeps the prior render's ids where messages line up so SwiftUI doesn't re-key
// every row and flicker the chat.

@Suite("ChatMessage.reconcilingIdentity")
struct ChatMessageReconcileTests {

    @Test("Carries prior message and text-block ids when role/order line up")
    func carriesIdentity() {
        let priorId = UUID()
        let prior = ChatMessage(id: priorId, role: .assistant,
                                blocks: [.text("hello", id: "live-block")])
        let fresh = ChatMessage(role: .assistant,
                                blocks: [.text("hello", id: "disk#0")])

        let result = ChatMessage.reconcilingIdentity([fresh], from: [prior])

        #expect(result[0].id == priorId)
        #expect(result[0].blocks[0].id == "live-block")
        #expect(result[0].content == "hello") // content still comes from disk
    }

    @Test("Keeps disk id when roles diverge at an index")
    func divergentRoleKeepsDiskId() {
        let prior = ChatMessage(role: .user, blocks: [.text("hi")])
        let freshId = UUID()
        let fresh = ChatMessage(id: freshId, role: .assistant, blocks: [.text("yo")])

        let result = ChatMessage.reconcilingIdentity([fresh], from: [prior])

        #expect(result[0].id == freshId)
    }

    @Test("Empty previous returns incoming unchanged")
    func emptyPrevious() {
        let fresh = ChatMessage(role: .user, blocks: [.text("hi")])
        let result = ChatMessage.reconcilingIdentity([fresh], from: [])
        #expect(result == [fresh])
    }

    @Test("Tool-call blocks keep their stable CLI id")
    func toolBlocksUnaffected() {
        let prior = ChatMessage(role: .assistant,
                                blocks: [.toolCall(ToolCall(id: "toolu_1", name: "bash"))])
        let fresh = ChatMessage(role: .assistant,
                                blocks: [.toolCall(ToolCall(id: "toolu_1", name: "bash"))])

        let result = ChatMessage.reconcilingIdentity([fresh], from: [prior])

        #expect(result[0].blocks[0].toolCall?.id == "toolu_1")
        #expect(result[0].blocks[0].id == "toolu_1")
    }

    @Test("Extra incoming messages beyond previous keep their disk ids")
    func extraIncomingUntouched() {
        let prior = ChatMessage(id: UUID(), role: .user, blocks: [.text("q")])
        let keptId = prior.id
        let answerId = UUID()
        let incoming = [
            ChatMessage(role: .user, blocks: [.text("q", id: "d#0")]),
            ChatMessage(id: answerId, role: .assistant, blocks: [.text("a", id: "d#1")])
        ]

        let result = ChatMessage.reconcilingIdentity(incoming, from: [prior])

        #expect(result[0].id == keptId)   // lines up → carried
        #expect(result[1].id == answerId) // no prior counterpart → disk id
    }
}
