import Foundation

/// Serializes structural reads (column lists) and writes (trash) on the tree.
enum TreeLock {
    private static let lock = NSLock()

    static func withLock<R>(_ body: () -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Flags mirroring ncdu's `struct dir` flags (see reference/ncdu/src/global.h).
struct FileFlags: OptionSet, Sendable {
    let rawValue: Int

    static let dir       = FileFlags(rawValue: 1 << 0)  // FF_DIR
    static let file      = FileFlags(rawValue: 1 << 1)  // FF_FILE
    static let err       = FileFlags(rawValue: 1 << 2)  // FF_ERR: error reading this item
    static let othFS     = FileFlags(rawValue: 1 << 3)  // FF_OTHFS: on another filesystem
    static let excluded  = FileFlags(rawValue: 1 << 4)  // FF_EXL: excluded by pattern/cache
    static let subErr    = FileFlags(rawValue: 1 << 5)  // FF_SERR: error in a subdirectory
    static let hlnkC     = FileFlags(rawValue: 1 << 6)  // FF_HLNKC: hard-link candidate (nlink > 1)
}

/// What kind of filesystem object a node represents.
enum NodeKind: Sendable {
    case directory
    case file
    case symlink
    case other
}

/// A node in the scanned directory tree. Reference type because the tree is
/// large, mutated in place during aggregation, and navigated by identity.
///
/// `size` mirrors ncdu's disk usage (`st_blocks * 512`) and `asize` mirrors the
/// apparent size (`st_size`). Both are aggregate totals for directories.
final class FileNode: Identifiable, @unchecked Sendable {
    let id = UUID()

    let name: String
    /// Absolute filesystem path, fixed at creation so UI never walks `parent`.
    let path: String
    let kind: NodeKind
    var flags: FileFlags

    /// Aggregate disk usage in bytes (for dirs: own inode + all descendants).
    var size: Int64
    /// Aggregate apparent size in bytes.
    var asize: Int64

    /// This node's own disk/apparent size, excluding descendants. Mutable so
    /// excluded / other-filesystem items can be zeroed (matching ncdu).
    var ownSize: Int64
    var ownASize: Int64

    /// Number of items contained (for dirs: count of all descendants).
    var items: Int

    let dev: UInt64
    let ino: UInt64
    let nlink: UInt64
    let mode: UInt16
    let mtime: Int64

    /// Resolved destination for symlinks, if available.
    var symlinkTarget: String?

    /// Raw (non-retaining) parent pointer, like ncdu's `struct dir.parent`.
    /// The tree owns nodes through `children`, so a parent always outlives its
    /// descendants; aggregation walks this chain millions of times, so it must
    /// not pay ARC/weak-table overhead. The UI never walks it (see `path`).
    unowned(unsafe) var parent: FileNode?
    var children: [FileNode]

    /// Next node sharing the same inode (circular list), used only transiently
    /// during hard-link size accounting. Mirrors ncdu's `struct dir.hlnk`.
    unowned(unsafe) var hlnk: FileNode?

    init(
        name: String,
        path: String,
        kind: NodeKind,
        flags: FileFlags,
        ownSize: Int64,
        ownASize: Int64,
        dev: UInt64,
        ino: UInt64,
        nlink: UInt64,
        mode: UInt16,
        mtime: Int64,
        parent: FileNode? = nil
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.flags = flags
        self.ownSize = ownSize
        self.ownASize = ownASize
        self.size = ownSize
        self.asize = ownASize
        self.items = 0
        self.dev = dev
        self.ino = ino
        self.nlink = nlink
        self.mode = mode
        self.mtime = mtime
        self.parent = parent
        self.children = []
    }

    var isDirectory: Bool { kind == .directory }
    var isHardLinkCandidate: Bool { flags.contains(.hlnkC) }
    var hasError: Bool { flags.contains(.err) || flags.contains(.subErr) }
    var isExcluded: Bool { flags.contains(.excluded) || flags.contains(.othFS) }

    var mtimeDate: Date? {
        mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
    }

    var url: URL { URL(fileURLWithPath: path) }
}

extension FileNode: Hashable {
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
