import SwiftUI

struct ContentView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Group {
            switch model.phase {
            case .welcome:
                WelcomeView()
            case .scanning:
                ScanProgressView()
            case .ready:
                ready
            case .error(let message):
                ErrorView(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $model.showScanFilters) {
            ScanFiltersView()
        }
        .sheet(isPresented: $model.showFullDiskAccessGuide) {
            FullDiskAccessGuideView()
        }
        .confirmationDialog(
            "Move \"\(model.itemPendingTrash?.name ?? "")\" to Trash?",
            isPresented: Binding(
                get: { model.itemPendingTrash != nil },
                set: { if !$0 { model.itemPendingTrash = nil } }
            ),
            presenting: model.itemPendingTrash
        ) { node in
            Button("Move to Trash", role: .destructive) {
                model.moveToTrash(node)
                model.itemPendingTrash = nil
            }
            Button("Cancel", role: .cancel) { model.itemPendingTrash = nil }
        } message: { node in
            Text("\(node.isDirectory ? "This folder and everything inside it" : "This item") will be moved to the Trash.")
        }
    }

    private var ready: some View {
        @Bindable var model = model

        return Group {
            switch model.browseMode {
            case .overview:
                OverviewView()
            case .browse:
                VStack(spacing: 0) {
                    if !model.hasFullDiskAccess {
                        inlineFDANotice
                            .task { await pollFullDiskAccessUntilGranted() }
                    }
                    BreadcrumbView()
                    ColumnBrowserView()
                }
            }
        }
        .inspector(isPresented: $model.showInspector) {
            InfoPanelView()
                .inspectorColumnWidth(min: 270, ideal: 310, max: 440)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter current folder")
        .toolbar { toolbarContent }
        .navigationTitle(model.root.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "NcduUI")
        .onAppear { model.refreshFullDiskAccessStatus() }
    }

    private var inlineFDANotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text("Some folders may be inaccessible.")
                .font(.caption)
            Button("Enable Full Disk Access…") { model.showFullDiskAccessGuide = true }
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var model = model

        ToolbarItem(placement: .navigation) {
            Picker("Mode", selection: $model.browseMode) {
                ForEach(ScanViewModel.BrowseMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Overview (⌘1) · Browse (⌘2)")
        }

        ToolbarItemGroup {
            Picker("Size", selection: $model.options.sizeMode) {
                ForEach(SizeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Picker("Sort by", selection: $model.options.sortColumn) {
                    ForEach(SortColumn.allCases) { col in Text(col.label).tag(col) }
                }
                Divider()
                Toggle("Descending", isOn: $model.options.sortDescending)
                Toggle("Folders First", isOn: $model.options.groupDirectoriesFirst)
                Divider()
                Toggle("Show Hidden Items", isOn: $model.options.showHidden)
                Divider()
                Picker("Minimum size", selection: minSizeBinding) {
                    ForEach(MinimumSize.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Label("View Options", systemImage: "arrow.up.arrow.down")
            }

            Button { model.showScanFilters = true } label: {
                Label("Scan Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Scan Filters (⌘⇧F)")

            Button { model.rescan() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .help("Rescan (⌘R)")

            Button { model.chooseFolder() } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .help("Open Folder (⌘O)")
        }
    }

    private var minSizeBinding: Binding<MinimumSize> {
        Binding(
            get: { MinimumSize(rawValue: model.options.minimumSize) ?? .all },
            set: { model.options.minimumSize = $0.rawValue }
        )
    }

    /// Re-checks FDA while the inline notice is visible so the banner disappears
    /// as soon as macOS applies the permission, without requiring an app restart.
    private func pollFullDiskAccessUntilGranted() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            model.refreshFullDiskAccessStatus()
            if model.hasFullDiskAccess { break }
        }
    }
}

struct ErrorView: View {
    @Environment(ScanViewModel.self) private var model
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
            Text("Scan Failed")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                Button("Choose Folder…") { model.chooseFolder() }
                    .buttonStyle(.borderedProminent)
                if model.root != nil {
                    Button("Back") { model.phase = .ready }
                }
            }
        }
        .padding(40)
    }
}
