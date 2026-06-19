import SwiftUI

/// Application menu bar and keyboard shortcuts.
struct AppCommands: Commands {
    @Bindable var model: ScanViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { model.chooseFolder() }
                .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                if model.recentFolders.isEmpty {
                    Text("No Recent Folders").disabled(true)
                } else {
                    ForEach(model.recentFolders, id: \.path) { url in
                        Button(url.lastPathComponent) { model.startScan(url: url) }
                    }
                    Divider()
                    Button("Clear Menu") { model.clearRecents() }
                }
            }
            .disabled(model.recentFolders.isEmpty)

            Divider()

            Button("Scan Filters…") { model.showScanFilters = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Rescan") { model.rescan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.root == nil)
        }

        CommandMenu("View") {
            Button("Overview") {
                model.browseMode = .overview
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(model.phase != .ready)

            Button("Browse") {
                model.browseMode = .browse
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(model.phase != .ready)

            Divider()

            Button(model.showInspector ? "Hide Inspector" : "Show Inspector") {
                model.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model.phase != .ready)

            Divider()

            Picker("Size Display", selection: $model.options.sizeMode) {
                ForEach(SizeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .disabled(model.phase != .ready)

            Toggle("Show Hidden Items", isOn: $model.options.showHidden)
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model.phase != .ready)

            Menu("Sort By") {
                Picker("Sort By", selection: $model.options.sortColumn) {
                    ForEach(SortColumn.allCases) { col in
                        Text(col.label).tag(col)
                    }
                }
                Divider()
                Toggle("Descending", isOn: $model.options.sortDescending)
                Toggle("Folders First", isOn: $model.options.groupDirectoriesFirst)
            }
            .disabled(model.phase != .ready)

            Menu("Minimum Size") {
                Picker("Minimum Size", selection: minimumSizeBinding) {
                    ForEach(MinimumSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
            }
            .disabled(model.phase != .ready)
        }

        CommandMenu("Go") {
            Button("Go Up") { model.navigateUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!model.canNavigateUp)

            Divider()

            Button("Open") { model.openFocusedItem() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!model.canOpenFocusedItem)

            Button("Reveal in Finder") { model.revealFocusedInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.focusedNode == nil)
        }

        CommandMenu("Item") {
            Button("Move to Trash…") { model.requestTrashForFocusedItem() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canTrashFocusedItem)

            Divider()

            Button("Open with Default App") { model.openFocusedWithDefaultApp() }
                .disabled(model.focusedNode.map { $0.isDirectory } ?? true)
        }

        CommandGroup(replacing: .help) {
            Button("Full Disk Access Guide…") {
                model.showFullDiskAccessGuide = true
            }
            Button("Check Full Disk Access") {
                model.refreshFullDiskAccessStatus()
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Cancel Scan") { model.cancelScan() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.phase != .scanning)
        }
    }

    private var minimumSizeBinding: Binding<MinimumSize> {
        Binding(
            get: { MinimumSize(rawValue: model.options.minimumSize) ?? .all },
            set: { model.options.minimumSize = $0.rawValue }
        )
    }
}
