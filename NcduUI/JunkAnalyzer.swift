import Foundation

/// Categories of commonly reclaimable disk usage.
enum JunkCategory: String, CaseIterable, Identifiable, Sendable {
    case dependencies
    case buildOutput
    case caches
    case logsAndTemp
    case systemCruft
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dependencies: return "Dependencies"
        case .buildOutput: return "Build Output"
        case .caches: return "Caches"
        case .logsAndTemp: return "Logs & Temp Files"
        case .systemCruft: return "System Cruft"
        case .trash: return "Trash"
        }
    }

    var icon: String {
        switch self {
        case .dependencies: return "shippingbox"
        case .buildOutput: return "hammer"
        case .caches: return "clock.arrow.circlepath"
        case .logsAndTemp: return "doc.text"
        case .systemCruft: return "sparkles"
        case .trash: return "trash"
        }
    }

    var note: String {
        switch self {
        case .dependencies: return "Re-downloadable package folders. Safe to remove; reinstall to restore."
        case .buildOutput: return "Generated build artifacts. Rebuilding recreates them."
        case .caches: return "Cached data that apps can regenerate on demand."
        case .logsAndTemp: return "Log and temporary files that are safe to clear."
        case .systemCruft: return "macOS metadata files that are recreated automatically."
        case .trash: return "Items already sitting in a Trash folder."
        }
    }

    /// Lower number = surfaced first.
    var order: Int {
        switch self {
        case .dependencies: return 0
        case .buildOutput: return 1
        case .caches: return 2
        case .trash: return 3
        case .logsAndTemp: return 4
        case .systemCruft: return 5
        }
    }
}

/// A group of reclaimable findings for one category.
struct JunkGroup: Identifiable {
    let category: JunkCategory
    var nodes: [FileNode]
    var totalSize: Int64 { nodes.reduce(0) { $0 + $1.size } }
    var id: String { category.rawValue }
}

/// Result of analyzing a scanned tree for cleanup opportunities.
struct CleanupReport {
    var groups: [JunkGroup] = []
    var largestFiles: [FileNode] = []
    var largestFolders: [FileNode] = []
    var totalReclaimable: Int64 { groups.reduce(0) { $0 + $1.totalSize } }
}

/// Finds commonly reclaimable files/folders using a curated rule set, and the
/// largest items overall. Matched folders are not descended into, so nested
/// junk is reported once at the highest level.
enum JunkAnalyzer {

    private static let dirNames: [String: JunkCategory] = [
        "node_modules": .dependencies,
        "pods": .dependencies,
        ".venv": .dependencies,
        "venv": .dependencies,
        ".npm": .caches,
        ".yarn": .caches,
        ".pnpm-store": .caches,
        ".gradle": .caches,
        ".m2": .caches,
        ".cache": .caches,
        "caches": .caches,
        "deriveddata": .buildOutput,
        "build": .buildOutput,
        ".build": .buildOutput,
        "dist": .buildOutput,
        "__pycache__": .buildOutput,
        ".trash": .trash,
        ".trashes": .trash,
    ]

    private static let fileSuffixes: [(String, JunkCategory)] = [
        (".log", .logsAndTemp),
        (".tmp", .logsAndTemp),
        (".temp", .logsAndTemp),
        (".pyc", .buildOutput),
        (".cache", .caches),
    ]

    private static let fileNames: [String: JunkCategory] = [
        ".ds_store": .systemCruft,
        "thumbs.db": .systemCruft,
        ".localized": .systemCruft,
    ]

    static func classify(_ node: FileNode) -> JunkCategory? {
        let lower = node.name.lowercased()
        if node.isDirectory {
            return dirNames[lower]
        }
        if let cat = fileNames[lower] { return cat }
        for (suffix, cat) in fileSuffixes where lower.hasSuffix(suffix) {
            return cat
        }
        return nil
    }

    static func analyze(root: FileNode, minSize: Int64 = 64 * 1024) -> CleanupReport {
        // Serialize with structural mutations (Move to Trash) so the traversal
        // never reads a `children` array or `parent` pointer that's being torn
        // down on the main thread.
        TreeLock.withLock {
            var byCategory: [JunkCategory: [FileNode]] = [:]
            var allFiles: [FileNode] = []
            var allFolders: [FileNode] = []

            func visit(_ node: FileNode) {
                if let category = classify(node), node.size >= minSize {
                    byCategory[category, default: []].append(node)
                    // Don't descend into a matched folder.
                    return
                }
                if node.isDirectory {
                    if node.parent != nil { allFolders.append(node) }
                    for child in node.children { visit(child) }
                } else {
                    allFiles.append(node)
                }
            }
            for child in root.children { visit(child) }

            var report = CleanupReport()
            report.groups = byCategory
                .map { JunkGroup(category: $0.key, nodes: $0.value.sorted { $0.size > $1.size }) }
                .filter { $0.totalSize > 0 }
                .sorted {
                    $0.totalSize != $1.totalSize
                        ? $0.totalSize > $1.totalSize
                        : $0.category.order < $1.category.order
                }

            report.largestFiles = Array(allFiles.sorted { $0.size > $1.size }.prefix(8))
            report.largestFolders = Array(allFolders.sorted { $0.size > $1.size }.prefix(8))
            return report
        }
    }
}
