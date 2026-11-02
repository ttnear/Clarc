import XCTest
@testable import Clarc

final class ClaudeSettingsPermissionsTests: XCTestCase {

    private func rules(allow: [String] = [], deny: [String] = [], ask: [String] = []) -> ClaudeSettingsPermissions {
        ClaudeSettingsPermissions(
            allow: allow.compactMap(ClaudeSettingsPermissions.Rule.init),
            deny: deny.compactMap(ClaudeSettingsPermissions.Rule.init),
            ask: ask.compactMap(ClaudeSettingsPermissions.Rule.init)
        )
    }

    // MARK: - MCP / plain tool names

    func testExactToolNameIsApproved() {
        let r = rules(allow: ["mcp__sheets__get_values"])
        XCTAssertTrue(r.autoApproves(toolName: "mcp__sheets__get_values", command: nil))
        XCTAssertFalse(r.autoApproves(toolName: "mcp__sheets__update_values", command: nil))
    }

    func testWildcardToolName() {
        let r = rules(allow: ["mcp__sheets__set_value*"])
        XCTAssertTrue(r.autoApproves(toolName: "mcp__sheets__set_values", command: nil))
        XCTAssertFalse(r.autoApproves(toolName: "mcp__sheets__get_values", command: nil))
    }

    func testServerLevelRuleCoversAllServerTools() {
        let r = rules(allow: ["mcp__sheets"])
        XCTAssertTrue(r.autoApproves(toolName: "mcp__sheets__get_values", command: nil))
        XCTAssertFalse(r.autoApproves(toolName: "mcp__sheets2__get_values", command: nil))
    }

    func testDenyAndAskBeatAllow() {
        let r = rules(allow: ["mcp__sheets__*"], deny: ["mcp__sheets__delete"], ask: ["mcp__sheets__update_values"])
        XCTAssertTrue(r.autoApproves(toolName: "mcp__sheets__get_values", command: nil))
        XCTAssertFalse(r.autoApproves(toolName: "mcp__sheets__delete", command: nil))
        XCTAssertFalse(r.autoApproves(toolName: "mcp__sheets__update_values", command: nil))
    }

    func testSpecifierRulesOnNonBashToolsDoNotGrantApproval() {
        let r = rules(allow: ["Edit(**/.maestro/cards/*)"])
        XCTAssertFalse(r.autoApproves(toolName: "Edit", command: nil))
    }

    // MARK: - Bash

    func testBashPrefixPattern() {
        let r = rules(allow: ["Bash(cd *)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "cd /tmp"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "cd"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "cdx /tmp"))
    }

    func testLegacyColonStarSyntax() {
        let r = rules(allow: ["Bash(maestro:*)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "maestro status"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "maestrox status"))
    }

    func testEveryCompoundSegmentMustBeAllowed() {
        let r = rules(allow: ["Bash(cd *)", "Bash(clasp status)", "Bash(tail *)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "cd /x && clasp status 2>&1 | tail -1"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "cd /x && rm -rf y"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "cd /x; rm -rf y"))
    }

    func testDenyRuleBlocksAnySegment() {
        let r = rules(allow: ["Bash(*)"], deny: ["Bash(rm *)"])
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "ls && rm -rf y"))
    }

    func testSeparatorsInsideQuotesDoNotSplit() {
        let r = rules(allow: ["Bash(maestro task note *)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: #"maestro task note t1 "a; b && c | d""#))
    }

    func testUnjudgeableSyntaxIsNeverApproved() {
        let r = rules(allow: ["Bash(echo *)", "Bash(cd *)"])
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "echo $(rm -rf /)"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "echo `whoami`"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "echo hi > out.txt"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "echo hi &"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: #"echo "unterminated"#))
    }

    func testHarmlessRedirectsAreAllowed() {
        let r = rules(allow: ["Bash(echo *)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "echo hi 2>&1"))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "echo hi >/dev/null 2>&1"))
    }

    // MARK: - Loading

    func testLoadMergesUserAndProjectSettings() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("clarc-perm-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try #"{"permissions":{"allow":["mcp__a__read"]}}"#
            .write(to: home.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8)
        try #"{"permissions":{"allow":["Bash(ls *)"],"deny":["mcp__a__write"]}}"#
            .write(to: project.appendingPathComponent(".claude/settings.local.json"), atomically: true, encoding: .utf8)

        let r = ClaudeSettingsPermissions.load(projectPath: project.path, homeDirectory: home)
        XCTAssertTrue(r.autoApproves(toolName: "mcp__a__read", command: nil))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "ls -la"))
        XCTAssertFalse(r.autoApproves(toolName: "mcp__a__write", command: nil))
    }

    func testMissingFilesYieldNoRules() {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("clarc-none-\(UUID().uuidString)")
        let r = ClaudeSettingsPermissions.load(projectPath: nowhere.path, homeDirectory: nowhere)
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "ls"))
    }
}
