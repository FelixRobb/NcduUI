import Foundation
import Darwin

/// Live progress emitted while scanning.
struct ScanProgress: Sendable {
    enum Phase: Sendable {
        case scanning
        case aggregating
    }

    var phase: Phase = .scanning
    var items: Int = 0
    var totalSize: Int64 = 0
    var currentPath: String = ""
    /// Nodes processed so far during aggregation (0 while scanning).
    var aggregatedItems: Int = 0
}

/// Outcome of a scan.
struct ScanResult: Sendable {
    var root: FileNode?
    var errorMessage: String?
    var wasCancelled: Bool = false
}

/// Recursive disk-usage scanner. Ports the core of ncdu's `dir_scan.c` and the
/// hard-link accounting from `dir_mem.c` / `util.c` to Swift, using `lstat`,
/// `opendir`, and `readdir` directly so we get real `st_blocks` disk usage.
final class DiskScanner: @unchecked Sendable {

    private let lock = NSLock()
    private var _cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock(); _cancelled = true; lock.unlock()
    }

    // MARK: - Public entry point

    func scan(
        rootPath: String,
        filters: ScanFilters = ScanFilters(),
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async -> ScanResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performScan(rootPath: rootPath, filters: filters, progress: progress)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Scanning

    private var counter = ScanProgress()
    private var lastReport = DispatchTime.now()
    private let counterLock = NSLock()
    private var filters = ScanFilters()
    private var rootDev: UInt64 = 0

    private func performScan(
        rootPath: String,
        filters: ScanFilters,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) -> ScanResult {
        let normalized = (rootPath as NSString).standardizingPath
        var st = stat()
        guard lstat(normalized, &st) == 0 else {
            return ScanResult(errorMessage: "Could not read \(normalized): \(String(cString: strerror(errno)))")
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            return ScanResult(errorMessage: "\(normalized) is not a directory")
        }

        counter = ScanProgress()
        lastReport = DispatchTime.now()
        self.filters = filters
        self.rootDev = UInt64(bitPattern: Int64(st.st_dev))

        let root = makeNode(name: normalized, path: normalized, st: st, parent: nil)
        walk(root: root, rootPath: normalized, progress: progress)

        if isCancelled {
            return ScanResult(root: nil, wasCancelled: true)
        }

        reportAggregating(aggregated: 0, progress: progress)
        aggregate(root: root, progress: progress)

        if isCancelled {
            return ScanResult(root: nil, wasCancelled: true)
        }

        progress(counter)
        return ScanResult(root: root)
    }

    /// A directory that still needs to be read, paired with its absolute path.
    private typealias WorkItem = (node: FileNode, path: String)

    /// Thread-safe work queue used to distribute directories across worker
    /// threads. `pending` tracks directories that are either queued or being
    /// processed, so workers know when the whole tree has been consumed.
    private final class WorkQueue: @unchecked Sendable {
        private let cond = NSCondition()
        private var stack: [WorkItem]
        private var pending: Int

        init(seed: WorkItem) {
            stack = [seed]
            pending = 1
        }

        /// Blocks until a directory is available, or returns `nil` when the
        /// entire tree has been processed.
        func next() -> WorkItem? {
            cond.lock()
            defer { cond.unlock() }
            while true {
                if let item = stack.popLast() { return item }
                if pending == 0 {
                    cond.broadcast() // wake any siblings so they can exit too
                    return nil
                }
                cond.wait()
            }
        }

        /// Marks the just-processed directory as done and enqueues the
        /// subdirectories discovered inside it.
        func complete(subdirs: [WorkItem]) {
            cond.lock()
            pending -= 1
            if !subdirs.isEmpty {
                stack.append(contentsOf: subdirs)
                pending += subdirs.count
                cond.broadcast()
            } else if pending == 0 {
                cond.broadcast()
            }
            cond.unlock()
        }
    }

    /// Walks the tree in parallel. ncdu reads a directory fully into memory and
    /// closes its descriptor before recursing (`dir_scan.c`); we do the same but
    /// fan the subdirectories out to a bounded pool of worker threads, which is a
    /// large win on SSDs/APFS where directory I/O parallelizes well.
    private func walk(
        root: FileNode,
        rootPath: String,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) {
        let queue = WorkQueue(seed: (root, rootPath))
        // Directory I/O on APFS parallelizes well and workers spend much of
        // their time blocked in lstat/readdir, so scale to every core.
        let workerCount = max(4, ProcessInfo.processInfo.activeProcessorCount)
        let group = DispatchGroup()
        let pool = DispatchQueue(label: "com.ncduui.scan.workers", attributes: .concurrent)

        for _ in 0..<workerCount {
            group.enter()
            pool.async { [weak self] in
                defer { group.leave() }
                guard let self else { return }
                while let item = queue.next() {
                    let subdirs = self.readDirectory(node: item.node, path: item.path, progress: progress)
                    queue.complete(subdirs: subdirs)
                }
            }
        }
        group.wait()
    }

    /// Reads a single directory: stats every entry, appends the resulting child
    /// nodes to `node`, and returns the subdirectories that should be recursed
    /// into. Only this worker touches `node.children`, so no locking is needed
    /// for the tree itself. The directory descriptor is closed before returning,
    /// bounding open descriptors to one per worker.
    private func readDirectory(
        node: FileNode,
        path: String,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) -> [WorkItem] {
        guard !isCancelled else { return [] }
        guard let dir = opendir(path) else {
            node.flags.insert(.err)
            return []
        }
        defer { closedir(dir) }

        // Accumulate this directory's contribution locally and merge into the
        // shared counter at most a few times per directory, so 18 workers don't
        // serialize on the progress lock for every single file.
        var localItems = 0
        var localSize: Int64 = 0
        var lastPath = path

        var subdirs: [WorkItem] = []
        while let entp = readdir(dir) {
            if isCancelled {
                flushProgress(items: localItems, size: localSize, path: lastPath, progress: progress)
                return subdirs
            }
            let name = direntName(entp)
            if name == "." || name == ".." || name.isEmpty { continue }

            let childPath = path == "/" ? "/" + name : path + "/" + name
            var st = stat()
            if lstat(childPath, &st) != 0 {
                let errNode = FileNode(
                    name: name, path: childPath, kind: .other, flags: [.err],
                    ownSize: 0, ownASize: 0, dev: 0, ino: 0, nlink: 0, mode: 0, mtime: 0,
                    parent: node)
                node.children.append(errNode)
                continue
            }

            let child = makeNode(name: name, path: childPath, st: st, parent: node)
            node.children.append(child)
            localItems += 1
            localSize += child.ownSize
            lastPath = childPath
            // Keep progress live inside very large directories.
            if localItems & 0x1FFF == 0 {
                flushProgress(items: localItems, size: localSize, path: lastPath, progress: progress)
                localItems = 0
                localSize = 0
            }

            // Excluded by glob pattern.
            if !filters.excludePatterns.isEmpty, matchesExclude(childPath) {
                child.flags.insert(.excluded)
                child.ownSize = 0
                child.ownASize = 0
                continue
            }

            guard child.kind == .directory, !child.flags.contains(.err) else { continue }

            // Stay on the same filesystem.
            if filters.sameFilesystem, child.dev != rootDev {
                child.flags.insert(.othFS)
                child.ownSize = 0
                child.ownASize = 0
                continue
            }

            // Skip cache directories (CACHEDIR.TAG).
            if filters.excludeCaches, hasCacheDirTag(childPath) {
                child.flags.insert(.excluded)
                child.ownSize = 0
                child.ownASize = 0
                continue
            }

            subdirs.append((child, childPath))
        }
        flushProgress(items: localItems, size: localSize, path: lastPath, progress: progress)
        return subdirs
    }

    /// Creates a `FileNode` from an `lstat` result, mirroring `stat_to_dir`.
    private func makeNode(name: String, path: String, st lst: stat, parent: FileNode?) -> FileNode {
        var st = lst

        // Follow symlinks to files (ncdu -L): replace the link's stat with the
        // target's, but only when the target is not a directory.
        if filters.followSymlinks, (lst.st_mode & S_IFMT) == S_IFLNK {
            var target = stat()
            if stat(path, &target) == 0, (target.st_mode & S_IFMT) != S_IFDIR {
                st = target
            }
        }

        let fmt = st.st_mode & S_IFMT
        let kind: NodeKind
        var flags: FileFlags = []

        if fmt == S_IFDIR {
            kind = .directory
            flags.insert(.dir)
        } else if fmt == S_IFREG {
            kind = .file
            flags.insert(.file)
        } else if fmt == S_IFLNK {
            kind = .symlink
        } else {
            kind = .other
        }

        // Hard-link candidate: non-directory with more than one link.
        if fmt != S_IFDIR && st.st_nlink > 1 {
            flags.insert(.hlnkC)
        }

        let diskSize = Int64(st.st_blocks) * 512
        let apparentSize = Int64(st.st_size)

        let node = FileNode(
            name: name,
            path: path,
            kind: kind,
            flags: flags,
            ownSize: diskSize,
            ownASize: apparentSize,
            dev: UInt64(bitPattern: Int64(st.st_dev)),
            ino: UInt64(st.st_ino),
            nlink: UInt64(st.st_nlink),
            mode: UInt16(st.st_mode),
            mtime: Int64(st.st_mtimespec.tv_sec),
            parent: parent
        )

        if kind == .symlink {
            node.symlinkTarget = readSymlink(path)
        }
        return node
    }

    /// Merges a worker's locally-accumulated batch into the shared counter.
    /// Called a few times per directory rather than once per file, so the lock
    /// is cheap even with many workers.
    private func flushProgress(items: Int, size: Int64, path: String, progress: @escaping @Sendable (ScanProgress) -> Void) {
        guard items > 0 else { return }
        counterLock.lock()
        counter.phase = .scanning
        counter.items += items
        counter.totalSize += size
        counter.currentPath = path

        let now = DispatchTime.now()
        let shouldReport = now.uptimeNanoseconds - lastReport.uptimeNanoseconds > 40_000_000 // ~40ms
        if shouldReport { lastReport = now }
        let snapshot = shouldReport ? counter : nil
        counterLock.unlock()

        // Report outside the lock so the (main-thread) callback never blocks workers.
        if let snapshot { progress(snapshot) }
    }

    private func reportAggregating(aggregated: Int, progress: @escaping @Sendable (ScanProgress) -> Void) {
        counterLock.lock()
        counter.phase = .aggregating
        counter.aggregatedItems = aggregated
        counter.currentPath = ""
        let snapshot = counter
        counterLock.unlock()
        progress(snapshot)
    }

    // MARK: - Aggregation (ports dir_mem.c hard-link accounting)

    private struct InodeKey: Hashable { let dev: UInt64; let ino: UInt64 }

    /// Computes aggregate sizes/items for every directory, deduplicating hard
    /// links so a shared inode is counted once per ancestor subtree.
    ///
    /// Ports ncdu's `addparentstats` (util.c) and `hlink_check` (dir_mem.c)
    /// 1:1: each item's own size is pushed up its parent chain, and hard links
    /// are tracked through a circular `hlnk` list so a shared inode contributes
    /// to each ancestor directory exactly once. The ancestor walk for hard links
    /// terminates as soon as a covering ancestor is found, which keeps large
    /// link groups (e.g. Xcode/CoreSimulator runtimes) from blowing up.
    private func aggregate(root: FileNode, progress: @escaping @Sendable (ScanProgress) -> Void) {
        /// Representative node (first seen) for each inode, ncdu's `links` table.
        var linkRep: [InodeKey: FileNode] = [:]
        var stack: [FileNode] = root.children.reversed()
        var visited = 0
        var lastReport = DispatchTime.now()
        let reportInterval: UInt64 = 100_000_000 // 100ms
        let reportStride = 25_000

        /// Ports `addparentstats`: add a contribution to every ancestor.
        func addParentStats(_ start: FileNode?, size: Int64, asize: Int64, items: Int) {
            var d = start
            while let n = d {
                n.size = n.size &+ size
                n.asize = n.asize &+ asize
                n.items += items
                d = n.parent
            }
        }

        /// Ports `hlink_check`: insert `d` into the circular `hlnk` list for its
        /// inode, then add its size only to the ancestors that don't already
        /// contain another link to the same inode (stopping at the first one).
        func hlinkCheck(_ d: FileNode) {
            let key = InodeKey(dev: d.dev, ino: d.ino)
            if let t = linkRep[key] {
                d.hlnk = (t.hlnk == nil) ? t : t.hlnk
                t.hlnk = d
            } else {
                linkRep[key] = d
            }

            var stop = false
            var par = d.parent
            while !stop, let p = par {
                // Has another link to this inode already counted toward `p`?
                if let first = d.hlnk {
                    var t: FileNode? = first
                    while let tt = t, tt !== d {
                        var pt = tt.parent
                        while let anc = pt {
                            if anc === p { stop = true; break }
                            pt = anc.parent
                        }
                        if stop { break }
                        t = tt.hlnk
                    }
                }
                if !stop {
                    p.size = p.size &+ d.ownSize
                    p.asize = p.asize &+ d.ownASize
                }
                par = p.parent
            }
        }

        func process(_ node: FileNode) {
            // Don't add size/asize for hard-link candidates here; hlinkCheck
            // takes care of it, matching ncdu's item() dispatch.
            if node.flags.contains(.hlnkC) {
                addParentStats(node.parent, size: 0, asize: 0, items: 1)
                hlinkCheck(node)
            } else {
                addParentStats(node.parent, size: node.ownSize, asize: node.ownASize, items: 1)
            }

            if node.flags.contains(.err) {
                var p = node.parent
                while let n = p {
                    n.flags.insert(.subErr)
                    p = n.parent
                }
            }

            if node.isDirectory {
                stack.append(contentsOf: node.children.reversed())
            }
        }

        while let node = stack.popLast() {
            if isCancelled { return }
            process(node)
            visited += 1
            let now = DispatchTime.now()
            if visited % reportStride == 0
                || now.uptimeNanoseconds - lastReport.uptimeNanoseconds > reportInterval {
                lastReport = now
                reportAggregating(aggregated: visited, progress: progress)
            }
        }
    }

    // MARK: - Low-level helpers

    /// Decodes the entry name using `d_namlen` directly, avoiding a `strlen`
    /// scan of the fixed-size `d_name` buffer for every single file.
    private func direntName(_ entp: UnsafeMutablePointer<dirent>) -> String {
        let length = Int(entp.pointee.d_namlen)
        return withUnsafeBytes(of: &entp.pointee.d_name) { raw in
            String(decoding: raw.prefix(length), as: UTF8.self)
        }
    }

    private func readSymlink(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let len = readlink(path, &buffer, buffer.count - 1)
        guard len >= 0 else { return nil }
        buffer[len] = 0
        return String(cString: buffer)
    }

    /// Ports `exclude_match`: a pattern matches the full path or any sub-path
    /// that begins right after a "/" (so basename patterns match anywhere).
    private func matchesExclude(_ path: String) -> Bool {
        for pattern in filters.excludePatterns where !pattern.isEmpty {
            let matched = pattern.withCString { pat -> Bool in
                path.withCString { full -> Bool in
                    if fnmatch(pat, full, 0) == 0 { return true }
                    var c = full
                    while c.pointee != 0 {
                        if c.pointee == 47 /* '/' */, c.advanced(by: 1).pointee != 47 {
                            if fnmatch(pat, c.advanced(by: 1), 0) == 0 { return true }
                        }
                        c = c.advanced(by: 1)
                    }
                    return false
                }
            }
            if matched { return true }
        }
        return false
    }

    private static let cacheTagSignature = "Signature: 8a477f597d28d172789f06886806bc55"

    /// Ports `has_cachedir_tag`: a CACHEDIR.TAG file with the magic signature.
    private func hasCacheDirTag(_ dirPath: String) -> Bool {
        let tagPath = dirPath == "/" ? "/CACHEDIR.TAG" : dirPath + "/CACHEDIR.TAG"
        guard let f = fopen(tagPath, "rb") else { return false }
        defer { fclose(f) }
        let sig = Array(Self.cacheTagSignature.utf8)
        var buf = [UInt8](repeating: 0, count: sig.count)
        let n = fread(&buf, 1, sig.count, f)
        return n == sig.count && buf == sig
    }
}
