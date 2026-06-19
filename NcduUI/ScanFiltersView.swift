import SwiftUI

struct ScanFiltersView: View {
    @Environment(ScanViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newPattern = ""

    private let suggestions = ["node_modules", ".git", "*.log", "Caches", "*.tmp"]

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scan Filters").font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    toggles

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exclude Patterns").font(.headline)
                        Text("Glob patterns matched against names and paths (like ncdu --exclude).")
                            .font(.caption).foregroundStyle(.secondary)

                        HStack {
                            TextField("e.g. *.log or node_modules", text: $newPattern)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addPattern)
                            Button("Add", action: addPattern)
                                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { add(s) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(model.filters.excludePatterns.contains(s))
                            }
                        }

                        if model.filters.excludePatterns.isEmpty {
                            Text("No patterns. Everything is scanned.")
                                .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(model.filters.excludePatterns, id: \.self) { pattern in
                                    HStack {
                                        Image(systemName: "circle.slash").foregroundStyle(.secondary)
                                        Text(pattern).font(.system(.body, design: .monospaced))
                                        Spacer()
                                        Button {
                                            model.filters.excludePatterns.removeAll { $0 == pattern }
                                        } label: { Image(systemName: "minus.circle") }
                                            .buttonStyle(.borderless)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Text("Changes apply on the next scan.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                if model.root != nil {
                    Button("Rescan Now") { dismiss(); model.rescan() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 460, height: 520)
    }

    private var toggles: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.filters.sameFilesystem) {
                label("Stay on the same filesystem", "Don't descend into other mounted volumes (ncdu -x).")
            }
            Toggle(isOn: $model.filters.excludeCaches) {
                label("Exclude cache folders", "Skip directories tagged with CACHEDIR.TAG.")
            }
            Toggle(isOn: $model.filters.followSymlinks) {
                label("Follow symlinks", "Count symlink targets (files only), like ncdu -L.")
            }
        }
    }

    private func label(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addPattern() {
        add(newPattern)
        newPattern = ""
    }

    private func add(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !model.filters.excludePatterns.contains(trimmed) else { return }
        model.filters.excludePatterns.append(trimmed)
    }
}
