import AppKit
import Foundation

/// Detects and helps the user enable macOS Full Disk Access.
enum FullDiskAccess {
    /// Apple’s TCC database — readable only with Full Disk Access.
    private static let tccDatabasePath = "/Library/Application Support/com.apple.TCC/TCC.db"

    static var isGranted: Bool {
        // Primary probe: opening the system TCC database forces a live TCC check.
        if canOpenForReading(tccDatabasePath) { return true }

        // Fallback: try listing a protected user folder. Some macOS versions
        // propagate FDA to the running process before TCC.db becomes readable.
        let mailPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Mail")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: mailPath, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: mailPath)) != nil
    }

    static var appBundleURL: URL { Bundle.main.bundleURL }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NcduUI"
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access.
    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([appBundleURL])
    }

    private static func canOpenForReading(_ path: String) -> Bool {
        guard let file = fopen(path, "r") else { return false }
        fclose(file)
        return true
    }
}
