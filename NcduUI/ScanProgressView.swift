import SwiftUI

struct ScanProgressView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)

            Text("Scanning…")
                .font(.title2.weight(.semibold))

            VStack(spacing: 6) {
                Text("\(model.progress.items.formatted()) items")
                    .font(.headline)
                    .monospacedDigit()
                Text(SizeFormatter.short(model.progress.totalSize))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(model.progress.currentPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)

            Button("Cancel Scan", role: .cancel) { model.cancelScan() }
                .keyboardShortcut(".", modifiers: .command)
        }
        .padding(48)
        .focusable()
        .onKeyPress(.escape) {
            model.cancelScan()
            return .handled
        }
    }
}
