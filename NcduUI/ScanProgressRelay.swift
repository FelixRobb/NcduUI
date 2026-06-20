import Foundation

/// Coalesces high-frequency scan progress updates onto the main actor without
/// flooding it with one `Task` per file.
final class ScanProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: ScanProgress?
    private var draining = false
    private let apply: @MainActor (ScanProgress) -> Void

    init(apply: @escaping @MainActor (ScanProgress) -> Void) {
        self.apply = apply
    }

    func post(_ value: ScanProgress) {
        lock.lock()
        pending = value
        let start = !draining
        if start { draining = true }
        lock.unlock()
        guard start else { return }
        Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    @MainActor
    private func drain() async {
        while true {
            lock.lock()
            guard let snapshot = pending else {
                draining = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            apply(snapshot)
            await Task.yield()
        }
    }
}
