import Foundation
@testable import NcduUI

/// Builds in-memory `FileNode` trees for unit tests.
enum FileNodeFixtures {

    @discardableResult
    static func directory(
        name: String,
        path: String? = nil,
        size: Int64 = 0,
        asize: Int64 = 0,
        items: Int = 0,
        mtime: Int64 = 0,
        children: [FileNode] = [],
        parent: FileNode? = nil
    ) -> FileNode {
        let fullPath = path ?? name
        let node = FileNode(
            name: name,
            path: fullPath,
            kind: .directory,
            flags: [.dir],
            ownSize: 0,
            ownASize: 0,
            dev: 1,
            ino: UInt64.random(in: 1...UInt64.max),
            nlink: 1,
            mode: 0o040755,
            mtime: mtime,
            parent: parent
        )
        node.size = size
        node.asize = asize
        node.items = items
        for child in children {
            child.parent = node
            node.children.append(child)
        }
        return node
    }

    @discardableResult
    static func file(
        name: String,
        path: String? = nil,
        size: Int64,
        asize: Int64? = nil,
        mtime: Int64 = 0,
        nlink: UInt64 = 1,
        parent: FileNode? = nil
    ) -> FileNode {
        let fullPath = path ?? name
        let apparent = asize ?? size
        var flags: FileFlags = [.file]
        if nlink > 1 { flags.insert(.hlnkC) }
        return FileNode(
            name: name,
            path: fullPath,
            kind: .file,
            flags: flags,
            ownSize: size,
            ownASize: apparent,
            dev: 1,
            ino: UInt64.random(in: 1...UInt64.max),
            nlink: nlink,
            mode: 0o100644,
            mtime: mtime,
            parent: parent
        )
    }

    @discardableResult
    static func symlink(
        name: String,
        path: String? = nil,
        target: String = "/target",
        parent: FileNode? = nil
    ) -> FileNode {
        let fullPath = path ?? name
        let node = FileNode(
            name: name,
            path: fullPath,
            kind: .symlink,
            flags: [],
            ownSize: 0,
            ownASize: 0,
            dev: 1,
            ino: UInt64.random(in: 1...UInt64.max),
            nlink: 1,
            mode: 0o120777,
            mtime: 0,
            parent: parent
        )
        node.symlinkTarget = target
        return node
    }

    /// Simple tree: root with known children for sorting/filter tests.
    static func sampleDirectory() -> FileNode {
        let small = file(name: "small.txt", size: 100)
        let large = file(name: "large.bin", size: 10_000_000)
        let hidden = file(name: ".hidden", size: 5_000_000)
        let backup = file(name: "notes.txt~", size: 500)
        let subdir = directory(name: "Projects", size: 50_000_000, items: 2, children: [
            file(name: "main.swift", size: 2_000),
            file(name: "README.md", size: 500),
        ])
        return directory(name: "/scan", path: "/scan", size: 60_000_600, items: 5, children: [
            small, large, hidden, backup, subdir,
        ])
    }
}
