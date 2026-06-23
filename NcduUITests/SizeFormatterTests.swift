import XCTest
@testable import NcduUI

final class SizeFormatterTests: XCTestCase {

    func testShortZeroBytes() {
        XCTAssertEqual(SizeFormatter.short(0), "0 B")
    }

    func testShortBytesBelowThreshold() {
        XCTAssertEqual(SizeFormatter.short(999), "999 B")
        XCTAssertEqual(SizeFormatter.short(1), "1 B")
    }

    func testShortIECUnits() {
        XCTAssertEqual(SizeFormatter.short(1024), "1.0 KiB")
        XCTAssertEqual(SizeFormatter.short(1_048_576), "1.0 MiB")
        XCTAssertEqual(SizeFormatter.short(1_073_741_824), "1.0 GiB")
    }

    func testShortSIUnits() {
        XCTAssertEqual(SizeFormatter.short(1000, si: true), "1.0 kB")
        XCTAssertEqual(SizeFormatter.short(1_000_000, si: true), "1.0 MB")
        XCTAssertEqual(SizeFormatter.short(1_000_000_000, si: true), "1.0 GB")
    }

    func testShortNegativeValues() {
        let result = SizeFormatter.short(-1024)
        XCTAssertTrue(result.contains("KiB") || result.contains("B"))
    }

    func testShortLargeValues() {
        let piB = Int64(1_125_899_906_842_624)
        XCTAssertEqual(SizeFormatter.short(piB), "1.0 PiB")
    }

    func testFullFormatting() {
        XCTAssertTrue(SizeFormatter.full(0).hasSuffix(" B"))
        XCTAssertTrue(SizeFormatter.full(1234).contains("234"))
        XCTAssertTrue(SizeFormatter.full(1_000_000).contains("000"))
    }
}
