import XCTest
@testable import NcduUI

final class ScanOptionsTests: XCTestCase {

    func testScanFiltersEmpty() {
        XCTAssertTrue(ScanFilters().isEmpty)
    }

    func testScanFiltersNotEmptyWithPatterns() {
        var filters = ScanFilters()
        filters.excludePatterns = ["*.log"]
        XCTAssertFalse(filters.isEmpty)
    }

    func testScanFiltersNotEmptyWithFlags() {
        var filters = ScanFilters()
        filters.excludeCaches = true
        XCTAssertFalse(filters.isEmpty)

        filters = ScanFilters()
        filters.sameFilesystem = true
        XCTAssertFalse(filters.isEmpty)

        filters = ScanFilters()
        filters.followSymlinks = true
        XCTAssertFalse(filters.isEmpty)
    }

    func testScanOptionsEquatable() {
        var a = ScanOptions()
        var b = ScanOptions()
        XCTAssertEqual(a, b)

        a.sortDescending = false
        XCTAssertNotEqual(a, b)
    }

    func testMinimumSizeLabels() {
        XCTAssertEqual(MinimumSize.all.label, "Any size")
        XCTAssertEqual(MinimumSize.oneMB.label, "≥ 1 MB")
    }

    func testSizeModeLabels() {
        XCTAssertEqual(SizeMode.disk.label, "Disk Usage")
        XCTAssertEqual(SizeMode.apparent.label, "Apparent Size")
    }

    func testSortColumnLabels() {
        XCTAssertEqual(SortColumn.name.label, "Name")
        XCTAssertEqual(SortColumn.items.label, "Item Count")
    }
}
