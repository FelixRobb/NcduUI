import XCTest
@testable import NcduUI

@MainActor
final class ScanViewModelTests: XCTestCase {

    private var viewModel: ScanViewModel!

    override func setUp() async throws {
        viewModel = ScanViewModel()
    }

    // MARK: - Hidden items

    func testIsHiddenDelegatesToNodeSorting() {
        let hidden = FileNodeFixtures.file(name: ".config", size: 100)
        let normal = FileNodeFixtures.file(name: "config", size: 100)
        XCTAssertTrue(viewModel.isHidden(hidden))
        XCTAssertFalse(viewModel.isHidden(normal))
    }

    // MARK: - Column children / sorting

    func testColumnChildrenSortsBySize() {
        viewModel.root = FileNodeFixtures.sampleDirectory()
        viewModel.path = [viewModel.root!]
        viewModel.phase = .ready
        viewModel.options.sortColumn = .size
        viewModel.options.sortDescending = true

        let children = viewModel.columnChildren(of: viewModel.root!, isLast: true)
        XCTAssertEqual(children.first?.name, "Projects")
    }

    func testColumnChildrenFiltersHiddenWhenDisabled() {
        viewModel.root = FileNodeFixtures.sampleDirectory()
        viewModel.path = [viewModel.root!]
        viewModel.phase = .ready
        viewModel.options.showHidden = false

        let children = viewModel.columnChildren(of: viewModel.root!, isLast: true)
        let names = Set(children.map(\.name))
        XCTAssertFalse(names.contains(".hidden"))
        XCTAssertFalse(names.contains("notes.txt~"))
    }

    func testColumnChildrenSearchFilterOnlyOnLastColumn() {
        viewModel.root = FileNodeFixtures.sampleDirectory()
        viewModel.path = [viewModel.root!]
        viewModel.phase = .ready
        viewModel.searchText = "large"

        let lastColumn = viewModel.columnChildren(of: viewModel.root!, isLast: true)
        XCTAssertEqual(lastColumn.count, 1)
        XCTAssertEqual(lastColumn.first?.name, "large.bin")

        let notLast = viewModel.columnChildren(of: viewModel.root!, isLast: false)
        XCTAssertGreaterThan(notLast.count, 1)
    }

    func testSortCacheReusedAcrossCalls() {
        viewModel.root = FileNodeFixtures.sampleDirectory()
        viewModel.path = [viewModel.root!]
        viewModel.phase = .ready

        let first = viewModel.columnChildren(of: viewModel.root!, isLast: false)
        let second = viewModel.columnChildren(of: viewModel.root!, isLast: false)
        XCTAssertEqual(first.map(\.name), second.map(\.name))
    }

    // MARK: - Navigation

    func testNavigateUp() {
        let root = FileNodeFixtures.sampleDirectory()
        let sub = root.children.first { $0.name == "Projects" }!
        viewModel.root = root
        viewModel.path = [root, sub]
        viewModel.focusedNode = sub
        viewModel.phase = .ready

        viewModel.navigateUp()
        XCTAssertEqual(viewModel.path.count, 1)
        XCTAssertTrue(viewModel.focusedNode === sub)
    }

    func testNavigateToCrumb() {
        let root = FileNodeFixtures.sampleDirectory()
        let sub = root.children.first { $0.name == "Projects" }!
        viewModel.root = root
        viewModel.path = [root, sub]
        viewModel.phase = .ready

        viewModel.navigate(toCrumb: 0)
        XCTAssertEqual(viewModel.path.count, 1)
        XCTAssertTrue(viewModel.focusedNode === root)
    }

    func testSelectDirectoryExtendsPath() {
        let root = FileNodeFixtures.sampleDirectory()
        let sub = root.children.first { $0.name == "Projects" }!
        viewModel.root = root
        viewModel.path = [root]
        viewModel.phase = .ready

        viewModel.select(sub, inColumnAt: 0)
        XCTAssertEqual(viewModel.path.count, 2)
        XCTAssertEqual(viewModel.path[1].name, "Projects")
    }

    func testSelectFileDoesNotExtendPath() {
        let root = FileNodeFixtures.sampleDirectory()
        let file = root.children.first { $0.name == "small.txt" }!
        viewModel.root = root
        viewModel.path = [root]
        viewModel.phase = .ready

        viewModel.select(file, inColumnAt: 0)
        XCTAssertEqual(viewModel.path.count, 1)
        XCTAssertTrue(viewModel.focusedNode === file)
    }

    func testSelectionInColumn() {
        let root = FileNodeFixtures.sampleDirectory()
        let sub = root.children.first { $0.name == "Projects" }!
        viewModel.root = root
        viewModel.path = [root, sub]
        viewModel.phase = .ready

        XCTAssertTrue(viewModel.selection(inColumnAt: 0) === sub)
    }

    func testRevealInBrowser() {
        let root = FileNodeFixtures.sampleDirectory()
        let sub = root.children.first { $0.name == "Projects" }!
        let file = sub.children.first { $0.name == "main.swift" }!
        viewModel.root = root
        viewModel.phase = .ready

        viewModel.revealInBrowser(file)
        XCTAssertEqual(viewModel.path.map(\.name), ["/scan", "Projects"])
        XCTAssertTrue(viewModel.focusedNode === file)
        XCTAssertEqual(viewModel.browseMode, .browse)
    }

    func testNavigateColumnSelectionRight() {
        let root = FileNodeFixtures.sampleDirectory()
        viewModel.root = root
        viewModel.path = [root]
        viewModel.phase = .ready
        viewModel.options.sortColumn = .size
        viewModel.options.sortDescending = true

        let first = viewModel.columnChildren(of: root, isLast: true).first!
        viewModel.select(first, inColumnAt: 0)

        viewModel.navigateColumnSelection(.right)
        XCTAssertEqual(viewModel.path.count, 2)
        XCTAssertNotNil(viewModel.focusedNode)
    }

    func testCanNavigateUp() {
        viewModel.path = [FileNodeFixtures.directory(name: "a")]
        XCTAssertFalse(viewModel.canNavigateUp)

        viewModel.path.append(FileNodeFixtures.directory(name: "b"))
        XCTAssertTrue(viewModel.canNavigateUp)
    }

    // MARK: - Size display

    func testSizeUsesSelectedMode() {
        let node = FileNodeFixtures.file(name: "f", size: 1000, asize: 5000)
        viewModel.options.sizeMode = .disk
        XCTAssertEqual(viewModel.size(of: node), 1000)

        viewModel.options.sizeMode = .apparent
        XCTAssertEqual(viewModel.size(of: node), 5000)
    }

    func testMaxChildSize() {
        let root = FileNodeFixtures.sampleDirectory()
        viewModel.options.sizeMode = .disk
        XCTAssertEqual(viewModel.maxChildSize(of: root), 50_000_000)
    }

    // MARK: - Trash eligibility

    func testCanTrashFocusedItemRequiresParent() {
        viewModel.phase = .ready
        let root = FileNodeFixtures.directory(name: "/root")
        viewModel.root = root
        viewModel.focusedNode = root
        XCTAssertFalse(viewModel.canTrashFocusedItem)

        let child = FileNodeFixtures.file(name: "child", size: 100, parent: root)
        root.children.append(child)
        child.parent = root
        viewModel.focusedNode = child
        XCTAssertTrue(viewModel.canTrashFocusedItem)
    }
}
