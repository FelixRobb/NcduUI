import SwiftUI

struct InfoPanelView: View {
    @Environment(ScanViewModel.self) private var model

    private var node: FileNode? {
        model.focusedNode ?? model.currentDirectory
    }

    var body: some View {
        ScrollView {
            if let node {
                VStack(alignment: .leading, spacing: 18) {
                    header(node)
                    Divider()
                    stats(node)
                    Divider()
                    actions(node)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right")
                    .padding(.top, 60)
            }
        }
    }

    private func header(_ node: FileNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: headerIcon(node))
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name.isEmpty ? node.path : node.name)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(kindLabel(node))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stats(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Disk Usage", SizeFormatter.short(node.size))
            row("Apparent Size", SizeFormatter.short(node.asize))
            row("Exact Bytes", SizeFormatter.full(node.size))
            if node.isDirectory {
                row("Items", node.items.formatted())
            }
            if let date = node.mtimeDate {
                row("Modified", date.formatted(date: .abbreviated, time: .shortened))
            }
            if node.nlink > 1 {
                row("Hard Links", node.nlink.formatted())
            }
            if let target = node.symlinkTarget {
                row("Symlink To", target)
            }
            row("Path", node.path, mono: true)
        }
    }

    private func actions(_ node: FileNode) -> some View {
        VStack(spacing: 8) {
            Button {
                model.revealInFinder(node)
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }

            if node.isDirectory {
                Button {
                    model.revealInBrowser(node)
                } label: {
                    Label("Open in Browser", systemImage: "rectangle.split.3x1")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    model.openWithDefaultApp(node)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
            }

            Button(role: .destructive) {
                model.itemPendingTrash = node
            } label: {
                Label("Move to Trash", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(node.parent == nil)
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .lineLimit(mono ? 4 : 1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerIcon(_ node: FileNode) -> String {
        switch node.kind {
        case .directory: return "folder.fill"
        case .file: return "doc.fill"
        case .symlink: return "arrow.up.forward.app.fill"
        case .other: return "gearshape.fill"
        }
    }

    private func kindLabel(_ node: FileNode) -> String {
        switch node.kind {
        case .directory: return "Folder"
        case .file: return "File"
        case .symlink: return "Symbolic Link"
        case .other: return "Special File"
        }
    }
}
