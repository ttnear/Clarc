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

    func testSafeSegmentCheckCanCoverPartOfACompoundCommand() {
        let r = rules(allow: ["Bash(cd *)"])
        let cmd = "cd .. && git status --short x && grep -n y x"
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: cmd))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: cmd, isSafeSegment: { $0.hasPrefix("git status") || $0.hasPrefix("grep") }))
    }

    func testSafeSegmentCheckNeverOverridesDeny() {
        let r = rules(allow: ["Bash(cd *)"], deny: ["Bash(git status *)"])
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "cd .. && git status -s", isSafeSegment: { _ in true }))
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

    // MARK: - Scratch redirects, loops, assignments

    func testRedirectsToLiteralTmpPathsAreIgnored() {
        let r = rules(allow: ["Bash(maestro *)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "maestro task list --json > /tmp/x.json 2>/dev/null"))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "maestro task list >> /tmp/x"))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "maestro task list 2>/tmp/e"))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "maestro task list >/private/tmp/x"))
    }

    func testOtherRedirectsStillBlockApproval() {
        let r = rules(allow: ["Bash(maestro *)"])
        for target in ["~/x", "/tmp/../etc/x", "/tmp/$X", "\"/tmp/x\"", "/etc/x", "/tmp/a*", "/tmp/a$X", "/tmp/", "\"/tmp/../x\""] {
            XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "maestro task list > \(target)"), target)
        }
    }

    func testForLoopScaffoldingIsIgnored() {
        let r = rules(allow: ["Bash(echo *)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "for id in a b; do echo $id; done"))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "for id in a b\ndo\n  echo $id\ndone"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "for id in a b; do rm $id; done"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "for id in $(ls); do echo $id; done"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "for id in $X; do echo $id; done"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "while true; do echo x; done"))
    }

    func testBareAssignmentsAreIgnored() {
        let r = rules(allow: ["Bash(cat *)"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "d=.maestro/x; cat $d/y"))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "d=\"a b\"; cat $d"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "d=$(find .) ; cat $d"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "d=$HOME; cat $d"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "PATH=/tmp/bin; cat x"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "d=x rm y; cat z"))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "d=x"))
    }

    // MARK: - Scratch redirects, loops and assignments x isSafeSegment

    /// Stands in for the BashSafety read-only whitelist: approves `cat` / `grep` segments only.
    private let readOnly: (String) -> Bool = { $0.hasPrefix("cat ") || $0.hasPrefix("grep ") }

    /// Records the segments the safe check is asked about, approving them with `readOnly`.
    private final class SegmentRecorder {
        var seen: [String] = []
    }

    func testScratchRedirectIsStrippedBeforeTheSafeSegmentCheck() {
        let r = rules()
        let rec = SegmentRecorder()
        let ok = r.autoApproves(toolName: "Bash", command: "cat x.json > /tmp/o.json 2>&1 && grep k /tmp/o.json", isSafeSegment: { rec.seen.append($0); return self.readOnly($0) })
        XCTAssertTrue(ok)
        XCTAssertTrue(rec.seen == ["cat x.json", "grep k /tmp/o.json"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "cat x >/private/tmp/o", isSafeSegment: readOnly))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "cat x 2>/tmp/e", isSafeSegment: readOnly))
    }

    func testStrictRedirectTargetsNeverReachApprovalWithSafeSegments() {
        let r = rules()
        for target in ["/tmp/", "/tmp/a$X", "/tmp/a*", "/tmp/../etc/x", "~/x", "/etc/x", "\"/tmp/x\""] {
            XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "cat x > \(target)", isSafeSegment: { _ in true }), target)
        }
    }

    func testDenyStillBlocksASegmentWhoseScratchRedirectWasStripped() {
        let r = rules(deny: ["Bash(cat *)"])
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "cat x > /tmp/o", isSafeSegment: { _ in true }))
        let asked = rules(ask: ["Bash(cat *)"])
        XCTAssertFalse(asked.autoApproves(toolName: "Bash", command: "cat x > /tmp/o", isSafeSegment: { _ in true }))
    }

    func testForLoopBodyIsJudgedByTheSafeSegmentCheck() {
        let r = rules()
        let rec = SegmentRecorder()
        let ok = r.autoApproves(toolName: "Bash", command: "for f in a b; do cat $f; done", isSafeSegment: { rec.seen.append($0); return self.readOnly($0) })
        XCTAssertTrue(ok)
        XCTAssertTrue(rec.seen == ["cat $f"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "for f in a b\ndo\n  grep k $f\ndone", isSafeSegment: readOnly))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "for f in a b; do rm $f; done", isSafeSegment: readOnly))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "for f in a b; do cat $f; rm $f; done", isSafeSegment: readOnly))
    }

    func testUnplainForLoopHeadersAndOtherLoopsAreNotCoveredBySafeSegments() {
        let r = rules()
        for cmd in ["for f in $(ls); do cat $f; done", "for f in $X; do cat $f; done", "for f in *; do cat $f; done",
                    "while true; do cat x; done", "until false; do cat x; done"] {
            XCTAssertFalse(r.autoApproves(toolName: "Bash", command: cmd, isSafeSegment: readOnly), cmd)
        }
    }

    func testSensitiveAssignmentsAreNotIgnoredBySafeSegments() {
        let r = rules()
        let names = ["PATH", "IFS", "BASH_ENV", "ENV", "SHELLOPTS", "PS4", "PROMPT_COMMAND",
                     "LD_PRELOAD", "LD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH"]
        for name in names {
            XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "\(name)=/tmp/x; cat y", isSafeSegment: readOnly), name)
        }
        // The assignment segment is what the safe check sees (and rejects), not silently dropped.
        let rec = SegmentRecorder()
        _ = r.autoApproves(toolName: "Bash", command: "PATH=/tmp/bin; cat y", isSafeSegment: { rec.seen.append($0); return self.readOnly($0) })
        XCTAssertTrue(rec.seen.first == "PATH=/tmp/bin")
    }

    func testHarmlessAssignmentIsDroppedBeforeTheSafeSegmentCheck() {
        let r = rules()
        let rec = SegmentRecorder()
        let ok = r.autoApproves(toolName: "Bash", command: "d=.maestro/x; cat $d/y", isSafeSegment: { rec.seen.append($0); return self.readOnly($0) })
        XCTAssertTrue(ok)
        XCTAssertTrue(rec.seen == ["cat $d/y"])
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: "d=\"a b\"; cat $d", isSafeSegment: readOnly))
    }

    func testAssignmentValuesWithExpansionWhitespaceOrRedirectsAreNotIgnored() {
        let r = rules()
        for cmd in ["d=$HOME; cat x", "d=\"$HOME\"; cat x", "d=a$X; cat x", "d=x y; cat x", "d=a<b; cat x", "d=x rm y; cat x", "d=a>b; cat x"] {
            XCTAssertFalse(r.autoApproves(toolName: "Bash", command: cmd, isSafeSegment: readOnly), cmd)
        }
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: "d=x", isSafeSegment: readOnly))
    }

    func testScratchRedirectLoopAndAssignmentCombine() {
        let r = rules()
        let cmd = "d=/tmp/work; for f in a b; do cat $d/$f > /tmp/out-$f 2>&1; done; grep k /tmp/out-a"
        // `/tmp/out-$f` has a variable, so the redirect is not stripped and nothing is approved.
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: cmd, isSafeSegment: readOnly))
        let ok = "d=/tmp/work; for f in a b; do cat $d/$f > /tmp/out.txt 2>&1; done; grep k /tmp/out.txt"
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: ok, isSafeSegment: readOnly))
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: ok + "; rm /tmp/out.txt", isSafeSegment: readOnly))
    }

    func testRulesAndSafeCheckMixWithScaffolding() {
        let r = rules(allow: ["Bash(maestro *)"])
        let cmd = "d=x; for id in a b; do maestro task show $id > /tmp/t.json; cat /tmp/t.json; done"
        XCTAssertFalse(r.autoApproves(toolName: "Bash", command: cmd))
        XCTAssertTrue(r.autoApproves(toolName: "Bash", command: cmd, isSafeSegment: readOnly))
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
