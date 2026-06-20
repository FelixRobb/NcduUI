import SwiftUI

struct ScanProgressView: View {
    @Environment(ScanViewModel.self) private var model

    private var isAggregating: Bool { model.progress.phase == .aggregating }

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)

            Text(isAggregating ? "Aggregating sizes…" : "Scanning…")
                .font(.title2.weight(.semibold))

            VStack(spacing: 6) {
                Text("\(model.progress.items.formatted()) items")
                    .font(.headline)
                    .monospacedDigit()
                Text(SizeFormatter.short(model.progress.totalSize))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if isAggregating, model.progress.aggregatedItems > 0 {
                    Text("\(model.progress.aggregatedItems.formatted()) processed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if !isAggregating {
                Text(model.progress.currentPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            } else {
                Text("Computing directory totals — this can take a minute on very large scans.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

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
