import XCTest
@testable import NcduUI

final class PathMatchingTests: XCTestCase {

    func testMatchesFullPath() {
        XCTAssertTrue(PathMatching.matchesExclude("/tmp/test.log", patterns: ["/tmp/*"]))
        XCTAssertTrue(PathMatching.matchesExclude("/Users/foo/project/file.log", patterns: ["*.log"]))
    }

    func testMatchesSubPathBasename() {
        // Basename patterns match at any path segment (ncdu exclude behavior).
        XCTAssertTrue(PathMatching.matchesExclude("/a/b/node_modules", patterns: ["node_modules"]))
        XCTAssertTrue(PathMatching.matchesExclude("/home/user/.cache", patterns: [".cache"]))
    }

    func testDoesNotMatchUnrelatedPaths() {
        XCTAssertFalse(PathMatching.matchesExclude("/Users/foo/Documents/report.pdf", patterns: ["node_modules"]))
        XCTAssertFalse(PathMatching.matchesExclude("/tmp/readme.txt", patterns: ["*.log"]))
    }

    func testEmptyPatternsNeverMatch() {
        XCTAssertFalse(PathMatching.matchesExclude("/anything", patterns: []))
        XCTAssertFalse(PathMatching.matchesExclude("/anything", patterns: ["", ""]))
    }

    func testGlobStarPatterns() {
        XCTAssertTrue(PathMatching.matchesExclude("/a/b/c/d.log", patterns: ["*.log"]))
        XCTAssertTrue(PathMatching.matchesExclude("/build/output.o", patterns: ["*.o"]))
    }

    func testQuestionMarkGlob() {
        XCTAssertTrue(PathMatching.matchesExclude("/tmp/a1", patterns: ["a?"]))
        XCTAssertTrue(PathMatching.matchesExclude("/tmp/ab", patterns: ["a?"]))
        XCTAssertFalse(PathMatching.matchesExclude("/tmp/abc", patterns: ["a?"]))
    }

    func testHasCacheDirTagPositive() throws {
        let tmp = try TempDirectory(prefix: "cache-tag")
        try tmp.directory("cached")
        try tmp.cacheDirTag(in: "cached")
        let path = tmp.url.appendingPathComponent("cached").path
        XCTAssertTrue(PathMatching.hasCacheDirTag(path))
    }

    func testHasCacheDirTagMissing() throws {
        let tmp = try TempDirectory(prefix: "no-cache-tag")
        try tmp.directory("plain")
        let path = tmp.url.appendingPathComponent("plain").path
        XCTAssertFalse(PathMatching.hasCacheDirTag(path))
    }

    func testHasCacheDirTagWrongSignature() throws {
        let tmp = try TempDirectory(prefix: "bad-cache-tag")
        let dir = try tmp.directory("bad")
        try "wrong signature".write(to: dir.appendingPathComponent("CACHEDIR.TAG"), atomically: true, encoding: .utf8)
        XCTAssertFalse(PathMatching.hasCacheDirTag(dir.path))
    }
}
