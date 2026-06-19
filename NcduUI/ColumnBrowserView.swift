import SwiftUI

/// Finder-style Miller column browser built from nested SwiftUI `ScrollView`s.
/// Unlike `List`, nested scroll views on macOS route trackpad gestures to the
/// correct axis natively — no AppKit scroll-event bridge required.
struct ColumnBrowserView: View {
    @Environment(ScanViewModel.self) private var model
    @FocusState private var keyboardFocused: Bool

    private let columnWidth: CGFloat = 400

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    ForEach(Array(model.path.enumerated()), id: \.element.id) { index, dir in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 1)
                        }
                        column(dir: dir, index: index)
                            .frame(width: columnWidth)
                            .id(dir.id)
                    }

                    if let focused = model.focusedNode, !focused.isDirectory {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 1)
                        filePreview(focused)
                            .frame(width: columnWidth)
                            .id("preview-\(focused.id)")
                    }
                }
            }
            .onChange(of: model.path.map(\.id)) { _, ids in
                guard let last = ids.last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .trailing) }
            }
        }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onAppear { keyboardFocused = true }
        .onTapGesture { keyboardFocused = true }
        .onKeyPress(.upArrow) {
            guard keyboardFocused else { return .ignored }
            model.navigateColumnSelection(.up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard keyboardFocused else { return .ignored }
            model.navigateColumnSelection(.down)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard keyboardFocused else { return .ignored }
            model.navigateColumnSelection(.left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard keyboardFocused else { return .ignored }
            model.navigateColumnSelection(.right)
            return .handled
        }
        .onKeyPress(.return) {
            model.openFocusedItem()
            return model.focusedNode != nil ? .handled : .ignored
        }
        .onKeyPress(.delete, phases: .down) { _ in
            model.requestTrashForFocusedItem()
            return model.canTrashFocusedItem ? .handled : .ignored
        }
    }

    private func column(dir: FileNode, index: Int) -> some View {
        let isLast = index == model.path.count - 1
        let children = model.columnChildren(of: dir, isLast: isLast)
        let maxSize = model.maxChildSize(of: dir)
        let parentTotal = max(model.size(of: dir), 1)

        return ScrollViewReader { rowProxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    ForEach(children) { node in
                        let sz = model.size(of: node)
                        let isSelected = model.selection(inColumnAt: index) === node
                        ColumnFileRowView(
                            node: node,
                            displaySize: sz,
                            fraction: maxSize > 0 ? Double(sz) / Double(maxSize) : 0,
                            percent: Double(sz) / Double(parentTotal) * 100,
                            dimmed: model.isHidden(node) || node.isExcluded,
                            isSelected: isSelected
                        )
                        .id(node.id)
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(node, inColumnAt: index) }
                        .contextMenu { contextMenu(for: node) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .onChange(of: model.focusedNode?.id) { _, _ in
                guard let selected = model.selection(inColumnAt: index) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    rowProxy.scrollTo(selected.id, anchor: .center)
                }
            }
            .onChange(of: model.path.count) { _, _ in
                guard let selected = model.selection(inColumnAt: index) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    rowProxy.scrollTo(selected.id, anchor: .center)
                }
            }
        }
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if children.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty || !isLast ? "Empty" : "No Matches",
                    systemImage: "folder"
                )
                .controlSize(.small)
            }
        }
    }

    private func filePreview(_ node: FileNode) -> some View {
        VStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                .resizable()
                .frame(width: 96, height: 96)
            Text(node.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(SizeFormatter.short(node.size))
                .foregroundStyle(.secondary)
            HStack {
                Button("Reveal") { model.revealInFinder(node) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Open") { model.openWithDefaultApp(node) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
            }
            .controlSize(.small)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func contextMenu(for node: FileNode) -> some View {
        if node.isDirectory {
            Button("Open") { model.open(node) }
        }
        Button("Reveal in Finder") { model.revealInFinder(node) }
        if !node.isDirectory {
            Button("Open with Default App") { model.openWithDefaultApp(node) }
        }
        Divider()
        Button("Move to Trash", role: .destructive) { model.itemPendingTrash = node }
    }
}
