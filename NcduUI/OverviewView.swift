import SwiftUI

struct OverviewView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryHeader
                if let root = model.root, !model.children(of: root).isEmpty {
                    compositionCard(root: root)
                }
                cleanupSection
                largestSection
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var summaryHeader: some View {
        let root = model.root
        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(root.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "")
                    .font(.title.weight(.bold))
                Text(root?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            stat(SizeFormatter.short(root.map { model.size(of: $0) } ?? 0), "Total")
            stat((root?.items ?? 0).formatted(), "Items")
            if let reclaimable = model.cleanup?.totalReclaimable, reclaimable > 0 {
                stat(SizeFormatter.short(reclaimable), "Reclaimable", tint: .orange)
            }
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Composition treemap

    private func compositionCard(root: FileNode) -> some View {
        Card(title: "Composition", systemImage: "square.grid.2x2") {
            TreemapView(
                nodes: model.children(of: root),
                sizeOf: { model.size(of: $0) },
                selected: model.focusedNode,
                onSelect: { model.focusedNode = $0 },
                onOpen: { model.revealInBrowser($0) }
            )
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Cleanup suggestions

    private var cleanupSection: some View {
        Group {
            if let cleanup = model.cleanup {
                if cleanup.groups.isEmpty {
                    Card(title: "Cleanup Suggestions", systemImage: "sparkles") {
                        Label("No obvious reclaimable files found.", systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                } else {
                    Card(title: "Cleanup Suggestions", systemImage: "sparkles") {
                        VStack(spacing: 14) {
                            ForEach(cleanup.groups) { group in
                                JunkGroupView(group: group, onTrash: { model.itemPendingTrash = $0 })
                                    .environment(model)
                            }
                        }
                    }
                }
            } else {
                Card(title: "Cleanup Suggestions", systemImage: "sparkles") {
                    HStack { ProgressView().controlSize(.small); Text("Analyzing…").foregroundStyle(.secondary) }
                        .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Largest items

    private var largestSection: some View {
        Group {
            if let cleanup = model.cleanup {
                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Largest Folders", systemImage: "folder") {
                        itemList(cleanup.largestFolders)
                    }
                    Card(title: "Largest Files", systemImage: "doc") {
                        itemList(cleanup.largestFiles)
                    }
                }
            }
        }
    }

    private func itemList(_ nodes: [FileNode]) -> some View {
        VStack(spacing: 0) {
            if nodes.isEmpty {
                Text("None").foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(nodes) { node in
                OverviewItemRow(node: node, size: model.size(of: node),
                                onReveal: { model.revealInBrowser(node) },
                                onTrash: { model.itemPendingTrash = node })
            }
        }
    }
}

// MARK: - Reusable card

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }
}

private struct JunkGroupView: View {
    @Environment(ScanViewModel.self) private var model
    let group: JunkGroup
    let onTrash: (FileNode) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: group.category.icon)
                    .foregroundStyle(.orange)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.category.title).fontWeight(.medium)
                    Text(group.category.note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(SizeFormatter.short(group.totalSize))
                    .monospacedDigit().fontWeight(.semibold)
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }

            Text("\(group.nodes.count) item\(group.nodes.count == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.tertiary)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.nodes.prefix(12)) { node in
                        OverviewItemRow(node: node, size: model.size(of: node),
                                        onReveal: { model.revealInBrowser(node) },
                                        onTrash: { onTrash(node) })
                    }
                    if group.nodes.count > 12 {
                        Text("+ \(group.nodes.count - 12) more")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct OverviewItemRow: View {
    let node: FileNode
    let size: Int64
    let onReveal: () -> Void
    let onTrash: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                Text(relativePath).font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(SizeFormatter.short(size)).monospacedDigit().foregroundStyle(.secondary)
            if hovering {
                Button(action: onReveal) { Image(systemName: "arrow.right.circle") }
                    .buttonStyle(.borderless).help("Show in browser")
                Button(action: onTrash) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Move to Trash")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var relativePath: String {
        (node.path as NSString).deletingLastPathComponent
    }
}
