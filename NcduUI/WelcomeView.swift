import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(ScanViewModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 28) {
            FullDiskAccessBanner()

            VStack(spacing: 12) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                Text("Disk Usage Analyzer")
                    .font(.largeTitle.weight(.semibold))
                Text("A native, ncdu-style explorer for finding what's eating your disk.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            dropZone

            Button {
                model.showScanFilters = true
            } label: {
                Label(filtersSummary, systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.bordered)

            if !model.recentFolders.isEmpty {
                recents
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.refreshFullDiskAccessStatus()
            if !model.hasFullDiskAccess && !UserDefaults.standard.bool(forKey: "HasShownFDAGuide") {
                model.showFullDiskAccessGuide = true
                UserDefaults.standard.set(true, forKey: "HasShownFDAGuide")
            }
        }
        .task(id: model.hasFullDiskAccess) {
            guard !model.hasFullDiskAccess else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.refreshFullDiskAccessStatus()
                if model.hasFullDiskAccess { break }
            }
        }
    }

    private var filtersSummary: String {
        model.filters.isEmpty ? "Scan Filters" : "Scan Filters (active)"
    }

    private var dropZone: some View {
        Button(action: { model.chooseFolder() }) {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 34))
                Text("Choose a Folder to Scan")
                    .font(.headline)
                Text("or drag a folder here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 460)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7])
                    )
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.headline)
                .foregroundStyle(.secondary)
            ForEach(model.recentFolders, id: \.path) { url in
                Button {
                    model.startScan(url: url)
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                Task { @MainActor in model.startScan(url: url) }
            }
        }
        return true
    }
}
