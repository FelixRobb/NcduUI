import SwiftUI

/// A squarified treemap of a directory's children. Each tile's area is
/// proportional to its size; clicking selects, double-clicking opens folders.
struct TreemapView: View {
    let nodes: [FileNode]
    let sizeOf: (FileNode) -> Int64
    var selected: FileNode?
    var onSelect: (FileNode) -> Void
    var onOpen: (FileNode) -> Void

    private let maxTiles = 40

    var body: some View {
        GeometryReader { geo in
            let tiles = layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(tiles, id: \.node.id) { tile in
                    TreemapCell(
                        tile: tile,
                        isSelected: tile.node === selected
                    )
                    .frame(width: tile.rect.width, height: tile.rect.height)
                    .offset(x: tile.rect.minX, y: tile.rect.minY)
                    .onTapGesture(count: 2) { onOpen(tile.node) }
                    .onTapGesture { onSelect(tile.node) }
                }
            }
        }
    }

    private func layout(in size: CGSize) -> [Tile] {
        let prepared = nodes
            .map { ($0, max(0, sizeOf($0))) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        guard !prepared.isEmpty, size.width > 1, size.height > 1 else { return [] }

        let capped = Array(prepared.prefix(maxTiles))
        let values = capped.map { Double($0.1) }
        let total = values.reduce(0, +)
        guard total > 0 else { return [] }

        let area = Double(size.width) * Double(size.height)
        let areas = values.map { $0 / total * area }
        let rects = Squarify.layout(areas: areas, in: CGRect(origin: .zero, size: size))

        var tiles: [Tile] = []
        for (i, rect) in rects.enumerated() where i < capped.count {
            tiles.append(Tile(node: capped[i].0, value: capped[i].1, rect: rect, colorIndex: i))
        }
        return tiles
    }

    struct Tile {
        let node: FileNode
        let value: Int64
        let rect: CGRect
        let colorIndex: Int
    }
}

private struct TreemapCell: View {
    let tile: TreemapView.Tile
    let isSelected: Bool

    private static let palette: [Color] = [
        Color(hue: 0.58, saturation: 0.55, brightness: 0.85),
        Color(hue: 0.52, saturation: 0.50, brightness: 0.80),
        Color(hue: 0.45, saturation: 0.48, brightness: 0.78),
        Color(hue: 0.62, saturation: 0.45, brightness: 0.82),
        Color(hue: 0.38, saturation: 0.46, brightness: 0.76),
        Color(hue: 0.68, saturation: 0.42, brightness: 0.80),
    ]

    private var fill: Color {
        Self.palette[tile.colorIndex % Self.palette.count]
    }

    var body: some View {
        let showLabel = tile.rect.width > 54 && tile.rect.height > 28
        RoundedRectangle(cornerRadius: 4)
            .fill(fill.opacity(tile.node.isDirectory ? 0.9 : 0.65))
            .overlay(alignment: .topLeading) {
                if showLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.node.name)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        Text(SizeFormatter.short(tile.value))
                            .font(.system(size: 9))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.white : Color.black.opacity(0.12),
                                  lineWidth: isSelected ? 2 : 0.5)
            )
            .padding(1)
            .help("\(tile.node.name) — \(SizeFormatter.short(tile.value))")
    }
}

/// Squarified treemap layout (Bruls, Huizing, van Wijk). Returns rects in the
/// same order as the input areas, which must already be sorted descending.
enum Squarify {
    static func layout(areas: [Double], in rect: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: areas.count)
        guard !areas.isEmpty else { return rects }

        var x = Double(rect.minX), y = Double(rect.minY)
        var w = Double(rect.width), h = Double(rect.height)

        var rowIndices: [Int] = []
        var i = 0

        func rowAreas() -> [Double] { rowIndices.map { areas[$0] } }

        func worst(_ extra: Double?) -> Double {
            var vals = rowAreas()
            if let extra { vals.append(extra) }
            guard !vals.isEmpty else { return .greatestFiniteMagnitude }
            let side = min(w, h)
            let sum = vals.reduce(0, +)
            guard sum > 0, side > 0 else { return .greatestFiniteMagnitude }
            let maxv = vals.max()!, minv = vals.min()!
            let s2 = sum * sum
            let side2 = side * side
            return max(side2 * maxv / s2, s2 / (side2 * minv))
        }

        func layoutRow() {
            let vals = rowAreas()
            let sum = vals.reduce(0, +)
            guard sum > 0 else { return }
            if w <= h {
                let rowH = sum / w
                var rx = x
                for idx in rowIndices {
                    let rw = areas[idx] / rowH
                    rects[idx] = CGRect(x: rx, y: y, width: rw, height: rowH)
                    rx += rw
                }
                y += rowH; h -= rowH
            } else {
                let rowW = sum / h
                var ry = y
                for idx in rowIndices {
                    let rh = areas[idx] / rowW
                    rects[idx] = CGRect(x: x, y: ry, width: rowW, height: rh)
                    ry += rh
                }
                x += rowW; w -= rowW
            }
            rowIndices.removeAll(keepingCapacity: true)
        }

        while i < areas.count {
            if rowIndices.isEmpty || worst(nil) >= worst(areas[i]) {
                rowIndices.append(i)
                i += 1
            } else {
                layoutRow()
            }
        }
        if !rowIndices.isEmpty { layoutRow() }
        return rects
    }
}
