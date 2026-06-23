import XCTest
@testable import NcduUI

final class FileNodeTests: XCTestCase {

    func testIsDirectory() {
        let dir = FileNodeFixtures.directory(name: "dir")
        let file = FileNodeFixtures.file(name: "file", size: 100)
        XCTAssertTrue(dir.isDirectory)
        XCTAssertFalse(file.isDirectory)
    }

    func testHasErrorFlags() {
        var file = FileNodeFixtures.file(name: "file", size: 100)
        XCTAssertFalse(file.hasError)

        file.flags.insert(.err)
        XCTAssertTrue(file.hasError)

        file.flags.remove(.err)
        file.flags.insert(.subErr)
        XCTAssertTrue(file.hasError)
    }

    func testIsExcluded() {
        var dir = FileNodeFixtures.directory(name: "dir")
        XCTAssertFalse(dir.isExcluded)

        dir.flags.insert(.excluded)
        XCTAssertTrue(dir.isExcluded)

        dir.flags.remove(.excluded)
        dir.flags.insert(.othFS)
        XCTAssertTrue(dir.isExcluded)
    }

    func testHardLinkCandidate() {
        let single = FileNodeFixtures.file(name: "a", size: 100, nlink: 1)
        let linked = FileNodeFixtures.file(name: "b", size: 100, nlink: 2)
        XCTAssertFalse(single.isHardLinkCandidate)
        XCTAssertTrue(linked.isHardLinkCandidate)
    }

    func testMtimeDate() {
        let node = FileNodeFixtures.file(name: "f", size: 100, mtime: 1_700_000_000)
        XCTAssertNotNil(node.mtimeDate)
        XCTAssertEqual(node.mtimeDate!.timeIntervalSince1970, 1_700_000_000, accuracy: 1)

        let zero = FileNodeFixtures.file(name: "z", size: 100, mtime: 0)
        XCTAssertNil(zero.mtimeDate)
    }

    func testIdentityEquality() {
        let a = FileNodeFixtures.file(name: "a", size: 100)
        let b = FileNodeFixtures.file(name: "b", size: 200)
        XCTAssertEqual(a, a)
        XCTAssertNotEqual(a, b)
    }

    func testURLFromPath() {
        let node = FileNodeFixtures.file(name: "test.txt", path: "/tmp/test.txt", size: 100)
        XCTAssertEqual(node.url.path, "/tmp/test.txt")
    }

    func testParentChildRelationship() {
        let child = FileNodeFixtures.file(name: "child", size: 100)
        let parent = FileNodeFixtures.directory(name: "parent", children: [child])
        XCTAssertTrue(child.parent === parent)
        XCTAssertTrue(parent.children.first === child)
    }
}
