import XCTest
@testable import NcduUI

final class JunkAnalyzerTests: XCTestCase {

    // MARK: - classify

    func testClassifyDependencyDirectories() {
        for name in ["node_modules", "Node_Modules", "pods", ".venv", "venv"] {
            let node = FileNodeFixtures.directory(name: name)
            XCTAssertEqual(JunkAnalyzer.classify(node), .dependencies, "Expected dependencies for \(name)")
        }
    }

    func testClassifyBuildOutput() {
        for name in ["DerivedData", "build", ".build", "dist", "__pycache__"] {
            let node = FileNodeFixtures.directory(name: name)
            XCTAssertEqual(JunkAnalyzer.classify(node), .buildOutput, "Expected buildOutput for \(name)")
        }
    }

    func testClassifyCaches() {
        for name in [".npm", ".yarn", ".cache", "caches", ".gradle"] {
            let node = FileNodeFixtures.directory(name: name)
            XCTAssertEqual(JunkAnalyzer.classify(node), .caches, "Expected caches for \(name)")
        }
    }

    func testClassifyTrashDirectories() {
        for name in [".trash", ".trashes"] {
            let node = FileNodeFixtures.directory(name: name)
            XCTAssertEqual(JunkAnalyzer.classify(node), .trash)
        }
    }

    func testClassifyLogAndTempFiles() {
        for name in ["app.log", "debug.LOG", "scratch.tmp", "data.temp"] {
            let node = FileNodeFixtures.file(name: name, size: 1000)
            XCTAssertEqual(JunkAnalyzer.classify(node), .logsAndTemp, "Expected logsAndTemp for \(name)")
        }
    }

    func testClassifySystemCruft() {
        for name in [".DS_Store", ".ds_store", "Thumbs.db", ".localized"] {
            let node = FileNodeFixtures.file(name: name, size: 1000)
            XCTAssertEqual(JunkAnalyzer.classify(node), .systemCruft, "Expected systemCruft for \(name)")
        }
    }

    func testClassifyBuildArtifactsBySuffix() {
        let pyc = FileNodeFixtures.file(name: "module.pyc", size: 1000)
        XCTAssertEqual(JunkAnalyzer.classify(pyc), .buildOutput)
    }

    func testClassifyNormalFilesReturnsNil() {
        let node = FileNodeFixtures.file(name: "README.md", size: 1000)
        XCTAssertNil(JunkAnalyzer.classify(node))
    }

    func testClassifyNormalDirectoriesReturnsNil() {
        let node = FileNodeFixtures.directory(name: "Documents")
        XCTAssertNil(JunkAnalyzer.classify(node))
    }

    // MARK: - analyze

    func testAnalyzeGroupsByCategory() {
        let nm = FileNodeFixtures.directory(name: "node_modules", size: 200_000)
        let logs = FileNodeFixtures.file(name: "debug.log", size: 100_000)
        let normal = FileNodeFixtures.file(name: "source.swift", size: 50_000)
        let root = FileNodeFixtures.directory(name: "/root", children: [nm, logs, normal])

        let report = JunkAnalyzer.analyze(root: root, minSize: 64 * 1024)

        XCTAssertEqual(report.groups.count, 2)
        XCTAssertEqual(report.groups.map(\.category), [.dependencies, .logsAndTemp])
        XCTAssertEqual(report.totalReclaimable, 300_000)
    }

    func testAnalyzeDoesNotDescendIntoMatchedFolder() {
        let nested = FileNodeFixtures.file(name: "nested.log", size: 500_000)
        let nm = FileNodeFixtures.directory(name: "node_modules", size: 1_000_000, children: [nested])
        let root = FileNodeFixtures.directory(name: "/root", children: [nm])

        let report = JunkAnalyzer.analyze(root: root, minSize: 64 * 1024)

        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups[0].nodes.count, 1)
        XCTAssertEqual(report.groups[0].nodes[0].name, "node_modules")
    }

    func testAnalyzeRespectsMinSize() {
        let tiny = FileNodeFixtures.file(name: "tiny.log", size: 100)
        let root = FileNodeFixtures.directory(name: "/root", children: [tiny])

        let report = JunkAnalyzer.analyze(root: root, minSize: 64 * 1024)
        XCTAssertTrue(report.groups.isEmpty)
    }

    func testAnalyzeLargestFilesAndFolders() {
        let bigFile = FileNodeFixtures.file(name: "big.dat", size: 50_000_000)
        let smallFile = FileNodeFixtures.file(name: "small.dat", size: 1000)
        let bigDir = FileNodeFixtures.directory(name: "BigProject", size: 100_000_000, children: [bigFile])
        let root = FileNodeFixtures.directory(name: "/root", children: [bigDir, smallFile])

        let report = JunkAnalyzer.analyze(root: root, minSize: 0)

        XCTAssertEqual(report.largestFiles.first?.name, "big.dat")
        XCTAssertEqual(report.largestFolders.first?.name, "BigProject")
        XCTAssertLessThanOrEqual(report.largestFiles.count, 8)
        XCTAssertLessThanOrEqual(report.largestFolders.count, 8)
    }

    func testAnalyzeSortsGroupsByTotalSize() {
        let logs = FileNodeFixtures.file(name: "a.log", size: 500_000)
        let nm = FileNodeFixtures.directory(name: "node_modules", size: 2_000_000)
        let root = FileNodeFixtures.directory(name: "/root", children: [logs, nm])

        let report = JunkAnalyzer.analyze(root: root, minSize: 64 * 1024)

        XCTAssertEqual(report.groups.first?.category, .dependencies)
    }
}
