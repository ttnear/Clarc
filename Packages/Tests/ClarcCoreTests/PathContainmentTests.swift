import XCTest
@testable import ClarcCore

final class PathContainmentTests: XCTestCase {

    func test_childEqualsParent_returnsTrue() {
        XCTAssertTrue(PathContainment.isInside(parent: "/Users/me/proj", child: "/Users/me/proj"))
    }

    func test_directFileInside_returnsTrue() {
        XCTAssertTrue(PathContainment.isInside(parent: "/Users/me/proj", child: "/Users/me/proj/README.md"))
    }

    func test_deeplyNestedFileInside_returnsTrue() {
        XCTAssertTrue(PathContainment.isInside(
            parent: "/Users/me/proj",
            child:  "/Users/me/proj/Sources/Foo/Bar.swift"))
    }

    func test_siblingWithSharedPrefix_returnsFalse() {
        // Guard against /proj being treated as parent of /projbackup.
        XCTAssertFalse(PathContainment.isInside(
            parent: "/Users/me/proj",
            child:  "/Users/me/projbackup/x"))
    }

    func test_unrelatedPath_returnsFalse() {
        XCTAssertFalse(PathContainment.isInside(parent: "/Users/me/proj", child: "/etc/passwd"))
    }

    func test_trailingSlashOnParent_isNormalized() {
        XCTAssertTrue(PathContainment.isInside(
            parent: "/Users/me/proj/",
            child:  "/Users/me/proj/x.swift"))
    }

    func test_dotSegmentInChild_isNormalized() {
        XCTAssertTrue(PathContainment.isInside(
            parent: "/Users/me/proj",
            child:  "/Users/me/proj/./src/x.swift"))
    }

    func test_doubleDotInChild_escapesProject_returnsFalse() {
        // NSString.standardizingPath resolves ".." lexically, so this
        // collapses to /Users/me/proj2/x.swift, which is outside /proj.
        XCTAssertFalse(PathContainment.isInside(
            parent: "/Users/me/proj",
            child:  "/Users/me/proj/../proj2/x.swift"))
    }

    func test_emptyParent_returnsFalse() {
        XCTAssertFalse(PathContainment.isInside(parent: "", child: "/x"))
    }

    func test_emptyChild_returnsFalse() {
        XCTAssertFalse(PathContainment.isInside(parent: "/x", child: ""))
    }

    func test_bothEmpty_returnsFalse() {
        XCTAssertFalse(PathContainment.isInside(parent: "", child: ""))
    }

    func test_relativeChildIsNotInsideAbsoluteParent() {
        // No resolution is performed; "src/x.swift" is not lexically under
        // the absolute parent.
        XCTAssertFalse(PathContainment.isInside(
            parent: "/Users/me/proj",
            child:  "src/x.swift"))
    }
}
