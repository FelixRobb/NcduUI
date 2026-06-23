import Foundation

/// Sorting and browse-time filtering for directory children. Ports ncdu's `dirlist.c`.
enum NodeSorting {

    static func isHidden(_ node: FileNode) -> Bool {
        guard let first = node.name.first else { return false }
        return first == "." || node.name.hasSuffix("~")
    }

    static func displaySize(of node: FileNode, mode: SizeMode) -> Int64 {
        mode == .disk ? node.size : node.asize
    }

    /// Filters hidden / minimum-size items and sorts the remainder.
    static func filterAndSort(children: [FileNode], options: ScanOptions) -> [FileNode] {
        var items = children
        if !options.showHidden {
            items = items.filter { !isHidden($0) }
        }
        if options.minimumSize > 0 {
            items = items.filter {
                displaySize(of: $0, mode: options.sizeMode) >= options.minimumSize
                    || $0.isDirectory && containsLargeDescendant($0, options: options)
            }
        }
        items.sort { compare($0, $1, options: options) }
        return items
    }

    private static func containsLargeDescendant(_ dir: FileNode, options: ScanOptions) -> Bool {
        displaySize(of: dir, mode: options.sizeMode) >= options.minimumSize
    }

    static func compare(_ x: FileNode, _ y: FileNode, options: ScanOptions) -> Bool {
        if options.groupDirectoriesFirst, x.isDirectory != y.isDirectory {
            return x.isDirectory
        }
        var r = primaryCompare(x, y, options: options)
        if r == 0 {
            switch options.sortColumn {
            case .size: r = cmpInt(x.asize, y.asize)
            case .apparent: r = cmpInt(x.size, y.size)
            default: r = cmpInt(x.size, y.size)
            }
        }
        if r == 0 { r = cmpName(x, y, options: options) }
        if r == 0 { r = cmpInt(Int64(x.items), Int64(y.items)) }
        if options.sortDescending { r = -r }
        if r == 0 { return cmpName(x, y, options: options) < 0 }
        return r < 0
    }

    private static func primaryCompare(_ x: FileNode, _ y: FileNode, options: ScanOptions) -> Int {
        switch options.sortColumn {
        case .size: return cmpInt(x.size, y.size)
        case .apparent: return cmpInt(x.asize, y.asize)
        case .name: return cmpName(x, y, options: options)
        case .items: return cmpInt(Int64(x.items), Int64(y.items))
        case .mtime: return cmpInt(x.mtime, y.mtime)
        }
    }

    private static func cmpInt(_ a: Int64, _ b: Int64) -> Int { a > b ? 1 : (a == b ? 0 : -1) }

    private static func cmpName(_ x: FileNode, _ y: FileNode, options: ScanOptions) -> Int {
        if options.naturalSort {
            let r = x.name.localizedStandardCompare(y.name)
            return r == .orderedAscending ? -1 : (r == .orderedSame ? 0 : 1)
        }
        return x.name < y.name ? -1 : (x.name == y.name ? 0 : 1)
    }
}
