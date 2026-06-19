import Foundation
import Observation
import AppKit

/// Drives the whole app: scanning, navigation, sorting, and file actions.
@MainActor
@Observable
final class ScanViewModel {

    enum Phase: Equatable {
        case welcome
        case scanning
        case ready
        case error(String)
    }

    enum BrowseMode: String, CaseIterable, Identifiable {
        case overview
        case browse
        var id: String { rawValue }
        var label: String { self == .overview ? "Overview" : "Browse" }
        var icon: String { self == .overview ? "chart.pie" : "rectangle.split.3x1" }
    }

    var phase: Phase = .welcome
    var browseMode: BrowseMode = .overview
    var options = ScanOptions()
    var filters = ScanFilters()

    var progress = ScanProgress()
    var root: FileNode?

    /// Directory chain shown as columns; `path[0]` is the scanned root.
    var path: [FileNode] = []
    /// Currently focused item (shown in the inspector); may be a file or dir.
    var focusedNode: FileNode?
    var searchText: String = ""

    var cleanup: CleanupReport?
    var recentFolders: [URL] = []

    // UI state (menus, sheets, permissions)
    var showScanFilters = false
    var showInspector = true
    var showFullDiskAccessGuide = false
    var hasFullDiskAccess = FullDiskAccess.isGranted
    var dismissedFDABanner = false {
        didSet { UserDefaults.standard.set(dismissedFDABanner, forKey: fdaBannerKey) }
    }
    /// Set when the user chooses Move to Trash from a menu/shortcut; views show confirmation.
    var itemPendingTrash: FileNode?

    private var scanner: DiskScanner?
    private let recentsKey = "RecentFolders"
    private let fdaBannerKey = "DismissedFDABanner"
    private let maxRecents = 8

    init() {
        loadRecents()
        dismissedFDABanner = UserDefaults.standard.bool(forKey: fdaBannerKey)
        refreshFullDiskAccessStatus()
    }

    // MARK: - Folder selection

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to analyze"
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url: url)
        }
    }

    // MARK: - Scanning

    func startScan(url: URL) {
        let scanner = DiskScanner()
        self.scanner = scanner
        self.progress = ScanProgress()
        self.phase = .scanning
        self.focusedNode = nil
        invalidateSortCache()
        addRecent(url)

        let path = url.path
        let filters = self.filters
        Task { [weak self] in
            let result = await scanner.scan(rootPath: path, filters: filters) { progress in
                Task { @MainActor in self?.progress = progress }
            }
            await MainActor.run {
                guard let self else { return }
                if result.wasCancelled {
                    self.phase = self.root == nil ? .welcome : .ready
                    return
                }
                if let message = result.errorMessage {
                    self.phase = .error(message)
                    return
                }
                guard let root = result.root else {
                    self.phase = .error("Scan returned no data.")
                    return
                }
                self.root = root
                self.path = [root]
                self.focusedNode = nil
                self.browseMode = .overview
                self.phase = .ready
                self.analyzeCleanup()
            }
        }
    }

    func cancelScan() { scanner?.cancel() }

    func rescan() {
        guard let root else { return }
        startScan(url: URL(fileURLWithPath: root.path))
    }

    func analyzeCleanup() {
        guard let root else { return }
        Task.detached(priority: .userInitiated) {
            let report = JunkAnalyzer.analyze(root: root)
            await MainActor.run { self.cleanup = report }
        }
    }

    // MARK: - Column navigation

    var currentDirectory: FileNode? { path.last }

    var breadcrumb: [FileNode] { path }

    var canNavigateUp: Bool { path.count > 1 }

    func navigateUp() {
        guard path.count > 1 else { return }
        let removed = path.removeLast()
        focusedNode = removed
    }

    func navigate(toCrumb index: Int) {
        guard index >= 0, index < path.count else { return }
        let dir = path[index]
        path = Array(path.prefix(index + 1))
        focusedNode = dir
    }

    /// Selecting an item inside the column for directory at `columnIndex`.
    func select(_ node: FileNode, inColumnAt columnIndex: Int) {
        guard columnIndex < path.count else { return }
        focusedNode = node
        var newPath = Array(path.prefix(columnIndex + 1))
        if node.isDirectory { newPath.append(node) }
        path = newPath
    }

    /// The item highlighted in the column at `columnIndex`, if any.
    ///
    /// Column `i` lists children of `path[i]`. The selection is either the
    /// drilled-in folder `path[i + 1]` or a focused child of `path[i]`.
    func selection(inColumnAt columnIndex: Int) -> FileNode? {
        guard columnIndex < path.count else { return nil }
        if columnIndex + 1 < path.count { return path[columnIndex + 1] }
        if let focusedNode,
           focusedNode !== path[columnIndex],
           focusedNode.parent === path[columnIndex] {
            return focusedNode
        }
        return nil
    }

    enum ColumnNavigationDirection {
        case up, down, left, right
    }

    /// Move the column-browser selection with arrow keys (Finder-style).
    func navigateColumnSelection(_ direction: ColumnNavigationDirection) {
        guard phase == .ready, !path.isEmpty else { return }

        switch direction {
        case .up, .down:
            guard let columnIndex = activeColumnIndex() else { return }
            let isLast = columnIndex == path.count - 1
            let children = columnChildren(of: path[columnIndex], isLast: isLast)
            guard !children.isEmpty else { return }

            if let current = selection(inColumnAt: columnIndex),
               let idx = children.firstIndex(where: { $0 === current }) {
                let next = direction == .up ? max(0, idx - 1) : min(children.count - 1, idx + 1)
                guard next != idx else { return }
                select(children[next], inColumnAt: columnIndex)
            } else {
                let idx = direction == .up ? children.count - 1 : 0
                select(children[idx], inColumnAt: columnIndex)
            }

        case .left:
            guard let columnIndex = activeColumnIndex() else { return }
            if columnIndex == 0 {
                if path.count > 1 {
                    let current = selection(inColumnAt: 0)
                    path = [path[0]]
                    focusedNode = current ?? path[0]
                } else {
                    focusedNode = path[0]
                }
                return
            }
            let openedFolder = path[columnIndex]
            path = Array(path.prefix(columnIndex))
            focusedNode = openedFolder

        case .right:
            guard let columnIndex = activeColumnIndex(),
                  let selected = selection(inColumnAt: columnIndex),
                  selected.isDirectory else { return }

            if columnIndex + 1 >= path.count || path[columnIndex + 1] !== selected {
                path = Array(path.prefix(columnIndex + 1)) + [selected]
            }

            let childColumn = columnIndex + 1
            let isLast = childColumn == path.count - 1
            let children = columnChildren(of: path[childColumn], isLast: isLast)
            guard let first = children.first else {
                focusedNode = selected
                return
            }
            select(first, inColumnAt: childColumn)
        }
    }

    /// The column whose list currently contains the keyboard highlight.
    ///
    /// `path[k]` for `k > 0` is shown in column `k - 1`; children of `path[k]`
    /// are shown in column `k`.
    private func activeColumnIndex() -> Int? {
        guard !path.isEmpty else { return nil }
        guard let focusedNode else { return 0 }

        if focusedNode === path[0] { return 0 }

        if let pathIndex = path.firstIndex(where: { $0 === focusedNode }), pathIndex > 0 {
            return pathIndex - 1
        }

        if let parent = focusedNode.parent,
           let columnIndex = path.firstIndex(where: { $0 === parent }) {
            return columnIndex
        }

        return 0
    }

    /// Jump straight to a node in the column browser (from the overview).
    func revealInBrowser(_ node: FileNode) {
        var chain: [FileNode] = []
        var n: FileNode? = node.isDirectory ? node : node.parent
        while let cur = n { chain.append(cur); n = cur.parent }
        chain.reverse()
        if !chain.isEmpty { path = chain }
        focusedNode = node
        browseMode = .browse
    }

    func open(_ node: FileNode) {
        guard node.isDirectory else { return }
        // Append as a new column if it is a child of the current last column.
        if let idx = path.firstIndex(where: { $0 === node.parent }) {
            select(node, inColumnAt: idx)
        } else if node.parent === path.last {
            path.append(node)
            focusedNode = node
        } else {
            revealInBrowser(node)
        }
    }

    // MARK: - Sorting & filtering (ports dirlist.c)

    func isHidden(_ node: FileNode) -> Bool {
        guard let first = node.name.first else { return false }
        return first == "." || node.name.hasSuffix("~")
    }

    func size(of node: FileNode) -> Int64 {
        options.sizeMode == .disk ? node.size : node.asize
    }

    /// Captures everything that affects the sorted/filtered child list except the
    /// search query, so the cache can be invalidated only when one of these changes.
    private struct SortSignature: Equatable {
        var sortColumn: SortColumn
        var sortDescending: Bool
        var groupDirectoriesFirst: Bool
        var naturalSort: Bool
        var sizeMode: SizeMode
        var showHidden: Bool
        var minimumSize: Int64
        var childCount: Int
    }

    /// Per-directory cache of the sorted + (hidden/min-size) filtered children.
    /// Not observed: it is a derived cache, so writing to it during a view update
    /// must not trigger another render.
    @ObservationIgnored private var sortCache: [ObjectIdentifier: (signature: SortSignature, items: [FileNode])] = [:]

    /// Children of `dir` for display in a column, after filtering + sorting.
    ///
    /// Sorting is the expensive step, so it is cached and reused across renders.
    /// The search query is applied *after* the cached sort: filtering a sorted
    /// array preserves order, so each keystroke is just an O(n) scan instead of a
    /// re-sort of every visible column.
    func columnChildren(of dir: FileNode, isLast: Bool) -> [FileNode] {
        let base = sortedChildren(of: dir)
        guard isLast else { return base }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter { matches($0, query: query) }
    }

    private func sortedChildren(of dir: FileNode) -> [FileNode] {
        let signature = SortSignature(
            sortColumn: options.sortColumn,
            sortDescending: options.sortDescending,
            groupDirectoriesFirst: options.groupDirectoriesFirst,
            naturalSort: options.naturalSort,
            sizeMode: options.sizeMode,
            showHidden: options.showHidden,
            minimumSize: options.minimumSize,
            childCount: dir.children.count
        )
        let key = ObjectIdentifier(dir)
        if let cached = sortCache[key], cached.signature == signature {
            return cached.items
        }

        var items = dir.children
        if !options.showHidden {
            items = items.filter { !isHidden($0) }
        }
        if options.minimumSize > 0 {
            items = items.filter { size(of: $0) >= options.minimumSize || $0.isDirectory && containsLargeDescendant($0) }
        }
        items.sort(by: compare)

        sortCache[key] = (signature, items)
        return items
    }

    /// Case-insensitive substring match. Uses a cheap ASCII fast path and only
    /// falls back to the locale-aware (and far slower) comparison for queries or
    /// names that contain non-ASCII characters.
    private func matches(_ node: FileNode, query: String) -> Bool {
        if query.utf8.allSatisfy({ $0 < 0x80 }), node.name.utf8.allSatisfy({ $0 < 0x80 }) {
            return asciiCaseInsensitiveContains(haystack: node.name.utf8, needle: query.utf8)
        }
        return node.name.localizedCaseInsensitiveContains(query)
    }

    private func asciiCaseInsensitiveContains(haystack: String.UTF8View, needle: String.UTF8View) -> Bool {
        let h = Array(haystack), n = Array(needle)
        guard !n.isEmpty else { return true }
        guard h.count >= n.count else { return false }
        @inline(__always) func lower(_ b: UInt8) -> UInt8 { (b >= 65 && b <= 90) ? b + 32 : b }
        let last = h.count - n.count
        var i = 0
        while i <= last {
            var j = 0
            while j < n.count, lower(h[i + j]) == lower(n[j]) { j += 1 }
            if j == n.count { return true }
            i += 1
        }
        return false
    }

    /// Drops cached sort results. Called when the tree changes structurally
    /// (new scan, trashed item) so stale orderings/retained nodes are released.
    private func invalidateSortCache() {
        sortCache.removeAll()
    }

    private func containsLargeDescendant(_ dir: FileNode) -> Bool {
        // Keep directories whose total meets the threshold so the user can drill in.
        size(of: dir) >= options.minimumSize
    }

    func maxChildSize(of dir: FileNode) -> Int64 {
        dir.children.map { size(of: $0) }.max() ?? 0
    }

    private func compare(_ x: FileNode, _ y: FileNode) -> Bool {
        if options.groupDirectoriesFirst, x.isDirectory != y.isDirectory {
            return x.isDirectory
        }
        var r = primaryCompare(x, y)
        if r == 0 {
            switch options.sortColumn {
            case .size: r = cmpInt(x.asize, y.asize)
            case .apparent: r = cmpInt(x.size, y.size)
            default: r = cmpInt(x.size, y.size)
            }
        }
        if r == 0 { r = cmpName(x, y) }
        if r == 0 { r = cmpInt(Int64(x.items), Int64(y.items)) }
        if options.sortDescending { r = -r }
        if r == 0 { return cmpName(x, y) < 0 }
        return r < 0
    }

    private func primaryCompare(_ x: FileNode, _ y: FileNode) -> Int {
        switch options.sortColumn {
        case .size: return cmpInt(x.size, y.size)
        case .apparent: return cmpInt(x.asize, y.asize)
        case .name: return cmpName(x, y)
        case .items: return cmpInt(Int64(x.items), Int64(y.items))
        case .mtime: return cmpInt(x.mtime, y.mtime)
        }
    }

    private func cmpInt(_ a: Int64, _ b: Int64) -> Int { a > b ? 1 : (a == b ? 0 : -1) }

    private func cmpName(_ x: FileNode, _ y: FileNode) -> Int {
        if options.naturalSort {
            let r = x.name.localizedStandardCompare(y.name)
            return r == .orderedAscending ? -1 : (r == .orderedSame ? 0 : 1)
        }
        return x.name < y.name ? -1 : (x.name == y.name ? 0 : 1)
    }

    // MARK: - Full Disk Access

    func refreshFullDiskAccessStatus() {
        let granted = FullDiskAccess.isGranted
        hasFullDiskAccess = granted
        if granted { dismissedFDABanner = false }
    }

    // MARK: - Menu / shortcut actions

    var canOpenFocusedItem: Bool {
        guard phase == .ready, let node = focusedNode else { return false }
        return node.isDirectory || FileManager.default.fileExists(atPath: node.path)
    }

    var canTrashFocusedItem: Bool {
        guard phase == .ready, let node = focusedNode else { return false }
        return node.parent != nil
    }

    func openFocusedItem() {
        guard let node = focusedNode else { return }
        if node.isDirectory { open(node) }
        else { openWithDefaultApp(node) }
    }

    func revealFocusedInFinder() {
        guard let node = focusedNode else { return }
        revealInFinder(node)
    }

    func openFocusedWithDefaultApp() {
        guard let node = focusedNode, !node.isDirectory else { return }
        openWithDefaultApp(node)
    }

    func requestTrashForFocusedItem() {
        guard canTrashFocusedItem, let node = focusedNode else { return }
        itemPendingTrash = node
    }

    func clearRecents() {
        recentFolders = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    // MARK: - File actions

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func openWithDefaultApp(_ node: FileNode) {
        NSWorkspace.shared.open(node.url)
    }

    /// Moves an item to the Trash and updates aggregate sizes up the tree.
    func moveToTrash(_ node: FileNode) {
        guard let parent = node.parent else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            phase = .error("Couldn't move \(node.name) to Trash: \(error.localizedDescription)")
            return
        }

        parent.children.removeAll { $0 === node }

        let removedSize = node.size, removedASize = node.asize, removedItems = node.items + 1
        var ancestor: FileNode? = parent
        while let a = ancestor {
            a.size &-= removedSize
            a.asize &-= removedASize
            a.items -= removedItems
            ancestor = a.parent
        }

        // Fix navigation if a column directory was removed.
        if let idx = path.firstIndex(where: { $0 === node }) {
            path = Array(path.prefix(idx))
            if path.isEmpty, let root { path = [root] }
        }
        if focusedNode === node { focusedNode = nil }

        // Ancestor sizes changed, which can reorder their siblings, so the whole
        // sort cache is now stale.
        invalidateSortCache()
        analyzeCleanup()
    }

    // MARK: - Recent folders

    private func loadRecents() {
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        recentFolders = paths.map { URL(fileURLWithPath: $0) }
    }

    private func addRecent(_ url: URL) {
        recentFolders.removeAll { $0.path == url.path }
        recentFolders.insert(url, at: 0)
        if recentFolders.count > maxRecents {
            recentFolders = Array(recentFolders.prefix(maxRecents))
        }
        UserDefaults.standard.set(recentFolders.map { $0.path }, forKey: recentsKey)
    }
}
