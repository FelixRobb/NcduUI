import SwiftUI

struct BreadcrumbView: View {
    @Environment(ScanViewModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button { model.navigateUp() } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canNavigateUp)
                .help("Go to parent directory")

                Divider().frame(height: 14)

                ForEach(Array(model.breadcrumb.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        model.navigate(toCrumb: index)
                    } label: {
                        Text(crumbLabel(node, isFirst: index == 0))
                            .fontWeight(index == model.breadcrumb.count - 1 ? .semibold : .regular)
                            .foregroundStyle(index == model.breadcrumb.count - 1 ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func crumbLabel(_ node: FileNode, isFirst: Bool) -> String {
        if isFirst {
            let last = (node.name as NSString).lastPathComponent
            return last.isEmpty ? node.name : last
        }
        return node.name
    }
}
