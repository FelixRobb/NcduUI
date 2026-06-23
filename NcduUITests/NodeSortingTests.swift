import XCTest
@testable import NcduUI

final class NodeSortingTests: XCTestCase {

    func testIsHiddenDotPrefix() {
        let hidden = FileNodeFixtures.file(name: ".gitignore", size: 100)
        XCTAssertTrue(NodeSorting.isHidden(hidden))
    }

    func testIsHiddenTildeSuffix() {
        let backup = FileNodeFixtures.file(name: "file.txt~", size: 100)
        XCTAssertTrue(NodeSorting.isHidden(backup))
    }

    func testIsHiddenNormalName() {
        let normal = FileNodeFixtures.file(name: "README.md", size: 100)
        XCTAssertFalse(NodeSorting.isHidden(normal))
    }

    func testSortBySizeDescending() {
        var options = ScanOptions()
        options.sortColumn = .size
        options.sortDescending = true

        let small = FileNodeFixtures.file(name: "a", size: 100)
        let large = FileNodeFixtures.file(name: "b", size: 10_000)
        let root = FileNodeFixtures.directory(name: "root", children: [small, large])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["b", "a"])
    }

    func testSortBySizeAscending() {
        var options = ScanOptions()
        options.sortColumn = .size
        options.sortDescending = false

        let small = FileNodeFixtures.file(name: "a", size: 100)
        let large = FileNodeFixtures.file(name: "b", size: 10_000)
        let root = FileNodeFixtures.directory(name: "root", children: [small, large])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["a", "b"])
    }

    func testSortByNameNatural() {
        var options = ScanOptions()
        options.sortColumn = .name
        options.sortDescending = false
        options.naturalSort = true

        let f2 = FileNodeFixtures.file(name: "file2", size: 100)
        let f10 = FileNodeFixtures.file(name: "file10", size: 100)
        let f1 = FileNodeFixtures.file(name: "file1", size: 100)
        let root = FileNodeFixtures.directory(name: "root", children: [f2, f10, f1])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["file1", "file2", "file10"])
    }

    func testSortByNameLexicographic() {
        var options = ScanOptions()
        options.sortColumn = .name
        options.sortDescending = false
        options.naturalSort = false

        let f2 = FileNodeFixtures.file(name: "file2", size: 100)
        let f10 = FileNodeFixtures.file(name: "file10", size: 100)
        let root = FileNodeFixtures.directory(name: "root", children: [f2, f10])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["file10", "file2"])
    }

    func testGroupDirectoriesFirst() {
        var options = ScanOptions()
        options.sortColumn = .size
        options.sortDescending = true
        options.groupDirectoriesFirst = true

        let file = FileNodeFixtures.file(name: "huge.bin", size: 1_000_000_000)
        let dir = FileNodeFixtures.directory(name: "small-dir", size: 100)
        let root = FileNodeFixtures.directory(name: "root", children: [file, dir])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.first?.name, "small-dir")
    }

    func testFilterHiddenItems() {
        var options = ScanOptions()
        options.showHidden = false

        let visible = FileNodeFixtures.file(name: "visible.txt", size: 100)
        let hidden = FileNodeFixtures.file(name: ".hidden", size: 100)
        let root = FileNodeFixtures.directory(name: "root", children: [visible, hidden])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["visible.txt"])
    }

    func testMinimumSizeFilterKeepsLargeDirectories() {
        var options = ScanOptions()
        options.minimumSize = 1_000_000
        options.sortColumn = .name

        let tiny = FileNodeFixtures.file(name: "tiny.txt", size: 10)
        let bigDir = FileNodeFixtures.directory(name: "BigProject", size: 5_000_000, items: 1)
        let root = FileNodeFixtures.directory(name: "root", children: [tiny, bigDir])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["BigProject"])
    }

    func testMinimumSizeFilterUsesApparentSizeMode() {
        var options = ScanOptions()
        options.sizeMode = .apparent
        options.minimumSize = 5000
        options.sortColumn = .name

        let sparse = FileNodeFixtures.file(name: "sparse", size: 512, asize: 10_000)
        let root = FileNodeFixtures.directory(name: "root", children: [sparse])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.count, 1)
    }

    func testSortByMtime() {
        var options = ScanOptions()
        options.sortColumn = .mtime
        options.sortDescending = true

        let old = FileNodeFixtures.file(name: "old", size: 100, mtime: 1000)
        let recent = FileNodeFixtures.file(name: "recent", size: 100, mtime: 9000)
        let root = FileNodeFixtures.directory(name: "root", children: [old, recent])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["recent", "old"])
    }

    func testSortByItems() {
        var options = ScanOptions()
        options.sortColumn = .items
        options.sortDescending = true

        let few = FileNodeFixtures.directory(name: "few", items: 2)
        let many = FileNodeFixtures.directory(name: "many", items: 100)
        let root = FileNodeFixtures.directory(name: "root", children: [few, many])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        XCTAssertEqual(sorted.map(\.name), ["many", "few"])
    }

    func testTieBreakByNameWhenSizesEqual() {
        var options = ScanOptions()
        options.sortColumn = .size
        options.sortDescending = true

        let b = FileNodeFixtures.file(name: "b", size: 1000)
        let a = FileNodeFixtures.file(name: "a", size: 1000)
        let root = FileNodeFixtures.directory(name: "root", children: [b, a])

        let sorted = NodeSorting.filterAndSort(children: root.children, options: options)
        // With descending primary sort, the name tie-break is also reversed.
        XCTAssertEqual(sorted.map(\.name), ["b", "a"])
    }
}
