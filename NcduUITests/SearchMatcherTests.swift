import XCTest
@testable import NcduUI

final class SearchMatcherTests: XCTestCase {

    func testAsciiCaseInsensitiveMatch() {
        XCTAssertTrue(SearchMatcher.matches(name: "HelloWorld.swift", query: "world"))
        XCTAssertTrue(SearchMatcher.matches(name: "HelloWorld.swift", query: "HELLO"))
        XCTAssertTrue(SearchMatcher.matches(name: "HelloWorld.swift", query: "HelloWorld"))
    }

    func testAsciiNoMatch() {
        XCTAssertFalse(SearchMatcher.matches(name: "main.swift", query: "test"))
    }

    func testEmptyQueryMatchesAll() {
        XCTAssertTrue(SearchMatcher.matches(name: "anything", query: ""))
    }

    func testPartialMatchAtStart() {
        XCTAssertTrue(SearchMatcher.matches(name: "node_modules", query: "node"))
    }

    func testPartialMatchAtEnd() {
        XCTAssertTrue(SearchMatcher.matches(name: "package.json", query: ".json"))
    }

    func testAsciiFastPathEdgeCases() {
        let haystack = "abc".utf8
        let needle = "b".utf8
        XCTAssertTrue(SearchMatcher.asciiCaseInsensitiveContains(haystack: haystack, needle: needle))
    }

    func testNeedleLongerThanHaystack() {
        let haystack = "ab".utf8
        let needle = "abcd".utf8
        XCTAssertFalse(SearchMatcher.asciiCaseInsensitiveContains(haystack: haystack, needle: needle))
    }

    func testUnicodeFallback() {
        // Non-ASCII name uses locale-aware comparison.
        XCTAssertTrue(SearchMatcher.matches(name: "café.txt", query: "café"))
    }
}
