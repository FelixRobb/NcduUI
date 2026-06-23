import Foundation
import Darwin

/// Path glob matching and cache-directory detection. Ports ncdu's `exclude.c`.
enum PathMatching {

    static let cacheTagSignature = "Signature: 8a477f597d28d172789f06886806bc55"

    /// Ports `exclude_match`: a pattern matches the full path or any sub-path
    /// that begins right after a "/" (so basename patterns match anywhere).
    static func matchesExclude(_ path: String, patterns: [String]) -> Bool {
        for pattern in patterns where !pattern.isEmpty {
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

    /// Ports `has_cachedir_tag`: a CACHEDIR.TAG file with the magic signature.
    static func hasCacheDirTag(_ dirPath: String) -> Bool {
        let tagPath = dirPath == "/" ? "/CACHEDIR.TAG" : dirPath + "/CACHEDIR.TAG"
        guard let f = fopen(tagPath, "rb") else { return false }
        defer { fclose(f) }
        let sig = Array(cacheTagSignature.utf8)
        var buf = [UInt8](repeating: 0, count: sig.count)
        let n = fread(&buf, 1, sig.count, f)
        return n == sig.count && buf == sig
    }
}
