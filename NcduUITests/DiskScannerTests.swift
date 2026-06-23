import XCTest
@testable import NcduUI

final class DiskScannerTests: XCTestCase {

    func testScanSimpleTree() async throws {
        let tmp = try TempDirectory(prefix: "scan-simple")
        try tmp.file("a.txt", contents: "hello")
        try tmp.file("b.txt", contents: "hello world longer content")
        try tmp.directory("subdir")
        try tmp.file("subdir/nested.txt", contents: "nested")

        let scanner = DiskScanner()
        let result = await scanner.scan(rootPath: tmp.url.path, filters: ScanFilters()) { _ in }

        XCTAssertNil(result.errorMessage)
        XCTAssertFalse(result.wasCancelled)
        guard let root = result.root else {
            XCTFail("Expected root node")
            return
        }

        XCTAssertEqual(root.name, tmp.url.path)
        XCTAssertEqual(root.children.count, 3)
        XCTAssertGreaterThan(root.size, 0)
        XCTAssertEqual(root.items, 4) // a.txt, b.txt, subdir, nested.txt
    }

    func testScanExcludePatterns() async throws {
        let tmp = try TempDirectory(prefix: "scan-exclude")
        try tmp.file("keep.txt", contents: "keep")
        try tmp.file("drop.log", contents: "log data")
        try tmp.directory("node_modules")
        try tmp.file("node_modules/pkg.js", contents: "package")

        var filters = ScanFilters()
        filters.excludePatterns = ["*.log", "node_modules"]

        let scanner = DiskScanner()
        let result = await scanner.scan(rootPath: tmp.url.path, filters: filters) { _ in }

        guard let root = result.root else {
            XCTFail("Expected root")
            return
        }

        let names = Set(root.children.map(\.name))
        XCTAssertTrue(names.contains("keep.txt"))
        XCTAssertTrue(names.contains("drop.log"))
        XCTAssertTrue(names.contains("node_modules"))

        let logNode = root.children.first { $0.name == "drop.log" }
        XCTAssertTrue(logNode?.isExcluded == true)
        XCTAssertEqual(logNode?.ownSize, 0)

        let nmNode = root.children.first { $0.name == "node_modules" }
        XCTAssertTrue(nmNode?.isExcluded == true)
        XCTAssertTrue(nmNode?.children.isEmpty == true)
    }

    func testScanExcludeCaches() async throws {
        let tmp = try TempDirectory(prefix: "scan-cache")
        try tmp.directory("cached")
        try tmp.cacheDirTag(in: "cached")
        try tmp.file("cached/data.bin", contents: Data(repeating: 0xAB, count: 10_000))
        try tmp.file("normal.txt", contents: "ok")

        var filters = ScanFilters()
        filters.excludeCaches = true

        let scanner = DiskScanner()
        let result = await scanner.scan(rootPath: tmp.url.path, filters: filters) { _ in }

        guard let root = result.root else {
            XCTFail("Expected root")
            return
        }

        let cached = root.children.first { $0.name == "cached" }
        XCTAssertTrue(cached?.isExcluded == true)
        XCTAssertEqual(cached?.ownSize, 0)
    }

    func testScanHardLinksCountedOnce() async throws {
        let tmp = try TempDirectory(prefix: "scan-hlink")
        try tmp.file("original.txt", contents: Data(repeating: 0xFF, count: 8192))
        try tmp.hardLink(from: "original.txt", to: "link.txt")

        let scanner = DiskScanner()
        let result = await scanner.scan(rootPath: tmp.url.path, filters: ScanFilters()) { _ in }

        guard let root = result.root else {
            XCTFail("Expected root")
            return
        }

        XCTAssertEqual(root.children.count, 2)
        let linkSizes = root.children.map(\.ownSize).sorted(by: >)
        XCTAssertEqual(linkSizes[0], linkSizes[1])

        // Parent total counts the shared inode once, not twice.
        XCTAssertEqual(root.size, linkSizes[0])
        XCTAssertLessThan(root.size, linkSizes[0] + linkSizes[1])
    }

    func testScanCancellation() async throws {
        let tmp = try TempDirectory(prefix: "scan-cancel")
        for i in 0..<50 {
            try tmp.file("file\(i).txt", contents: Data(repeating: UInt8(i), count: 4096))
        }

        let scanner = DiskScanner()
        let task = Task {
            await scanner.scan(rootPath: tmp.url.path, filters: ScanFilters()) { _ in
                scanner.cancel()
            }
        }
        let result = await task.value
        XCTAssertTrue(result.wasCancelled)
    }

    func testScanNonDirectoryReturnsError() async {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-dir-\(UUID().uuidString)")
        try? "hello".write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let scanner = DiskScanner()
        let result = await scanner.scan(rootPath: tmpURL.path, filters: ScanFilters()) { _ in }

        XCTAssertNotNil(result.errorMessage)
        XCTAssertNil(result.root)
    }

    func testScanMissingPathReturnsError() async {
        let scanner = DiskScanner()
        let result = await scanner.scan(
            rootPath: "/nonexistent/path/\(UUID().uuidString)",
            filters: ScanFilters()
        ) { _ in }

        XCTAssertNotNil(result.errorMessage)
        XCTAssertNil(result.root)
    }

    func testScanReportsProgress() async throws {
        let tmp = try TempDirectory(prefix: "scan-progress")
        for i in 0..<20 {
            try tmp.file("f\(i).txt", contents: "data \(i)")
        }

        var progressUpdates: [ScanProgress] = []
        let scanner = DiskScanner()
        _ = await scanner.scan(rootPath: tmp.url.path, filters: ScanFilters()) { progress in
            progressUpdates.append(progress)
        }

        XCTAssertFalse(progressUpdates.isEmpty)
        XCTAssertTrue(progressUpdates.contains { $0.items > 0 })
    }

    func testScanSymlinkNotFollowedByDefault() async throws {
        let tmp = try TempDirectory(prefix: "scan-symlink")
        try tmp.file("target.txt", contents: "target content")
        let linkPath = tmp.url.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(
            at: linkPath,
            withDestinationURL: tmp.url.appendingPathComponent("target.txt")
        )

        let scanner = DiskScanner()
        let result = await scanner.scan(rootPath: tmp.url.path, filters: ScanFilters()) { _ in }

        guard let root = result.root else {
            XCTFail("Expected root")
            return
        }

        let link = root.children.first { $0.name == "link.txt" }
        XCTAssertEqual(link?.kind, .symlink)
        XCTAssertNotNil(link?.symlinkTarget)
    }
}
