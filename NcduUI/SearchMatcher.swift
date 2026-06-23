import Foundation

/// Case-insensitive substring search for the column-browser filter.
enum SearchMatcher {

    static func matches(name: String, query: String) -> Bool {
        if query.utf8.allSatisfy({ $0 < 0x80 }), name.utf8.allSatisfy({ $0 < 0x80 }) {
            return asciiCaseInsensitiveContains(haystack: name.utf8, needle: query.utf8)
        }
        return name.localizedCaseInsensitiveContains(query)
    }

    static func asciiCaseInsensitiveContains(haystack: String.UTF8View, needle: String.UTF8View) -> Bool {
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
}
