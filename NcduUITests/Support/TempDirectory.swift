import Foundation
@testable import NcduUI

/// Creates a temporary directory that is removed when deallocated.
final class TempDirectory {
    let url: URL

    init(prefix: String = "NcduUITests") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String, contents: Data = Data()) throws -> URL {
        let path = url.appendingPathComponent(name)
        try contents.write(to: path)
        return path
    }

    func file(_ name: String, contents: String) throws -> URL {
        try file(name, contents: Data(contents.utf8))
    }

    func directory(_ name: String) throws -> URL {
        let path = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    func hardLink(from: String, to: String) throws {
        let src = url.appendingPathComponent(from)
        let dst = url.appendingPathComponent(to)
        try FileManager.default.linkItem(at: src, to: dst)
    }

    func cacheDirTag(in dirName: String) throws {
        let tag = url.appendingPathComponent(dirName).appendingPathComponent("CACHEDIR.TAG")
        try PathMatching.cacheTagSignature.write(to: tag, atomically: true, encoding: .utf8)
    }
}
