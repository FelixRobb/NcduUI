import Foundation

/// Which size metric is shown and used for the usage bars.
enum SizeMode: String, CaseIterable, Identifiable {
    case disk      // st_blocks * 512  (ncdu default)
    case apparent  // st_size

    var id: String { rawValue }
    var label: String {
        switch self {
        case .disk: return "Disk Usage"
        case .apparent: return "Apparent Size"
        }
    }
}

/// Sort column, mirroring ncdu's DL_COL_* (see reference/ncdu/src/dirlist.c).
enum SortColumn: String, CaseIterable, Identifiable {
    case size      // disk usage
    case apparent  // apparent size
    case name
    case items
    case mtime

    var id: String { rawValue }
    var label: String {
        switch self {
        case .size: return "Disk Usage"
        case .apparent: return "Apparent Size"
        case .name: return "Name"
        case .items: return "Item Count"
        case .mtime: return "Modified"
        }
    }
}

/// User-adjustable browsing options. Mirrors the toggles ncdu exposes.
struct ScanOptions: Equatable {
    var sizeMode: SizeMode = .disk
    var sortColumn: SortColumn = .size
    var sortDescending: Bool = true
    var groupDirectoriesFirst: Bool = false
    var showHidden: Bool = true
    var naturalSort: Bool = true
    /// Browse-time minimum size; items smaller than this are hidden. 0 = show all.
    var minimumSize: Int64 = 0
}

/// Preset thresholds for the minimum-size browse filter.
enum MinimumSize: Int64, CaseIterable, Identifiable {
    case all = 0
    case oneMB = 1_048_576
    case tenMB = 10_485_760
    case hundredMB = 104_857_600
    case oneGB = 1_073_741_824

    var id: Int64 { rawValue }
    var label: String {
        switch self {
        case .all: return "Any size"
        case .oneMB: return "≥ 1 MB"
        case .tenMB: return "≥ 10 MB"
        case .hundredMB: return "≥ 100 MB"
        case .oneGB: return "≥ 1 GB"
        }
    }
}

/// Scan-time filters, applied while walking the tree. Ports ncdu's exclude/
/// scan options (see reference/ncdu/src/main.c and exclude.c).
struct ScanFilters: Equatable {
    /// Glob patterns (fnmatch) matched against full path and each sub-path.
    var excludePatterns: [String] = []
    /// Skip directories containing a CACHEDIR.TAG file (ncdu --exclude-caches).
    var excludeCaches: Bool = false
    /// Don't cross into other mounted volumes (ncdu -x).
    var sameFilesystem: Bool = false
    /// Follow symlinks to files, counting the target (ncdu -L).
    var followSymlinks: Bool = false

    var isEmpty: Bool {
        excludePatterns.isEmpty && !excludeCaches && !sameFilesystem && !followSymlinks
    }
}
