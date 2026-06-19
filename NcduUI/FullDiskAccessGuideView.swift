import SwiftUI

struct FullDiskAccessGuideView: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusCard
                    steps
                    note
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 560)
        .onAppear { model.refreshFullDiskAccessStatus() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Full Disk Access")
                    .font(.title2.weight(.semibold))
                Text("Scan any folder without repeated permission prompts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: model.hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(model.hasFullDiskAccess ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.hasFullDiskAccess ? "Full Disk Access is enabled" : "Full Disk Access is not enabled")
                    .font(.headline)
                Text(model.hasFullDiskAccess
                     ? "NcduUI can read protected folders such as Mail, Messages, and system Library paths."
                     : "Without this, macOS may block folders and you’ll see incomplete scan results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to enable").font(.headline)
            step(1, "Open Full Disk Access settings",
                 "Click the button below to jump directly to the right pane in System Settings.")
            step(2, "Add NcduUI",
                 "Click the + button, then choose NcduUI from Applications — or drag the app from Finder.")
            step(3, "Turn on the switch",
                 "Make sure the toggle next to NcduUI is enabled.")
            step(4, "Restart NcduUI",
                 "Quit and reopen the app so macOS applies the new permission.")
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Why is this needed?", systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
            Text("macOS protects folders like ~/Library/Mail, ~/Library/Messages, and parts of /Library. Full Disk Access lets NcduUI scan them in one go instead of asking for each folder separately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Check Again") { model.refreshFullDiskAccessStatus() }
            Spacer()
            Button("Reveal App in Finder") { FullDiskAccess.revealAppInFinder() }
            Button("Open System Settings") { FullDiskAccess.openSystemSettings() }
                .buttonStyle(.bordered)
            if model.hasFullDiskAccess {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

/// Compact banner shown on the welcome screen when FDA is missing.
struct FullDiskAccessBanner: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        if !model.hasFullDiskAccess && !model.dismissedFDABanner {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Full Disk Access for complete scans")
                        .font(.subheadline.weight(.medium))
                    Text("Avoid permission prompts and scan protected Library folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Learn How…") { model.showFullDiskAccessGuide = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button {
                    model.dismissedFDABanner = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.25)))
            )
        }
    }
}
