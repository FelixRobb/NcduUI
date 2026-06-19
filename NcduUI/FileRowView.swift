import SwiftUI

struct FileRowView: View {
    let node: FileNode
    let displaySize: Int64
    let fraction: Double   // size relative to the largest sibling (bar length)
    let percent: Double    // size relative to the parent total
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                .layoutPriority(1)
                .frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)

            if node.isHardLinkCandidate {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Hard link (counted once)")
            }
            if node.hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Could not fully read this item")
            }

            Spacer(minLength: 12)

            Text(SizeFormatter.short(displaySize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)

            UsageBar(fraction: fraction)
                .frame(width: 110, height: 9)

            Text(percentString)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)

            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Spacer().frame(width: 10)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var percentString: String {
        String(format: "%.1f%%", percent)
    }

    private var iconName: String {
        switch node.kind {
        case .directory: return "folder.fill"
        case .file: return "doc"
        case .symlink: return "arrow.up.forward.app"
        case .other: return "gearshape"
        }
    }

    private var iconColor: Color {
        switch node.kind {
        case .directory: return .accentColor
        case .file: return .secondary
        case .symlink: return .teal
        case .other: return .secondary
        }
    }
}

/// A proportional usage bar whose color shifts from green (small) to red (large).
struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.1))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(2, geo.size.width * clamped))
            }
        }
    }

    private var clamped: Double { min(1, max(0, fraction)) }

    private var barColor: Color {
        Color(hue: 0.33 * (1 - clamped), saturation: 0.55, brightness: 0.85)
    }
}

/// Compact row for the Finder-style column browser, with a usage bar.
struct ColumnFileRowView: View {
    let node: FileNode
    let displaySize: Int64
    var fraction: Double = 0
    var percent: Double = 0
    let dimmed: Bool
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                .frame(minWidth: 48, maxWidth: .infinity, alignment: .leading)

            if node.isHardLinkCandidate {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(SizeFormatter.short(displaySize))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            UsageBar(fraction: fraction)
                .frame(width: 80, height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
        .help("\(node.name) — \(SizeFormatter.short(displaySize)) (\(String(format: "%.1f%%", percent)) of folder)")
    }

    private var iconName: String {
        switch node.kind {
        case .directory: return "folder.fill"
        case .file: return "doc"
        case .symlink: return "arrow.up.forward.app"
        case .other: return "gearshape"
        }
    }

    private var iconColor: Color {
        switch node.kind {
        case .directory: return .accentColor
        case .file: return .secondary
        case .symlink: return .teal
        case .other: return .secondary
        }
    }
}
