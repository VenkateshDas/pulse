import PulseKit
import SwiftUI

/// Overlay lens applied to the same treemap — switch with no re-scan.
enum StorageLens: String, CaseIterable, Identifiable {
    case safety = "Safety"
    case age = "Age"
    case owner = "Owner"
    var id: String { rawValue }
}

/// One treemap cell: a folder/file node enriched with the smart-scan grade,
/// idle age, and owning category when known (for the three lenses).
struct TreemapCell: Identifiable, Equatable {
    let node: StorageNode
    let grade: SafetyGrade
    let idleDays: Int?
    let category: String
    var id: String { node.id }
}

/// Squarified treemap (spec §3.3, default view) with safety / age / owner
/// lenses. Single tap selects a cell (detail panel); double-tap a folder
/// zooms in. Pure SwiftUI geometry — no Canvas, animates with the layout.
struct TreemapView: View {
    let cells: [TreemapCell]
    let lens: StorageLens
    @Binding var selectedID: String?
    let onZoom: (StorageNode) -> Void

    var body: some View {
        GeometryReader { geo in
            let sorted = cells.sorted { $0.node.sizeBytes > $1.node.sizeBytes }
            let rects = Self.squarify(
                weights: sorted.map { Double(max($0.node.sizeBytes, 1)) },
                in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, cell in
                    if rects[index].width > 2 && rects[index].height > 2 {
                        cellView(cell, rect: rects[index])
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.25), value: cells)
        }
    }

    @ViewBuilder
    private func cellView(_ cell: TreemapCell, rect: CGRect) -> some View {
        let selected = selectedID == cell.id
        let color = lensColor(cell)
        let showLabel = rect.width > 54 && rect.height > 28
        RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(selected ? 0.9 : 0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(selected ? Halo.textPrimary : Halo.void.opacity(0.6),
                        lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .topLeading) {
                if showLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cell.node.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Halo.void)
                            .lineLimit(1)
                        Text(ByteFormat.string(cell.node.sizeBytes))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Halo.void.opacity(0.8))
                    }
                    .padding(5)
                }
            }
            .frame(width: max(rect.width - 2, 0), height: max(rect.height - 2, 0))
            .contentShape(Rectangle())
            .onTapGesture {
                selectedID = (selectedID == cell.id) ? nil : cell.id
            }
            .position(x: rect.midX, y: rect.midY)
            .help("\(cell.node.name) · \(ByteFormat.string(cell.node.sizeBytes))")
    }

    // MARK: Lens coloring

    private func lensColor(_ cell: TreemapCell) -> Color {
        switch lens {
        case .safety:
            return gradeColor(cell.grade)
        case .age:
            guard let idle = cell.idleDays else { return Halo.textDim }
            if idle < 30 { return Halo.pulseGreen }
            if idle < 180 { return Halo.amber }
            return Halo.flare
        case .owner:
            return Self.ownerPalette[abs(cell.category.hashValue) % Self.ownerPalette.count]
        }
    }

    private static let ownerPalette: [Color] = [
        Halo.ion, Halo.volt, Halo.amber, Halo.pulseGreen, Halo.flare,
    ]

    // MARK: Squarified layout (Bruls, Huizing, van Wijk)

    /// Returns one rect per weight (input order), packed to keep cells near
    /// square. Weights should be passed largest-first.
    static func squarify(weights: [Double], in rect: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else {
            return weights.map { _ in .zero }
        }
        let scale = (rect.width * rect.height) / total
        let areas = weights.map { $0 * scale }
        var result = [CGRect](repeating: .zero, count: weights.count)

        var x = rect.minX, y = rect.minY
        var w = rect.width, h = rect.height
        var i = 0
        while i < areas.count {
            var row: [Int] = []
            var rowAreas: [Double] = []
            var best = Double.greatestFiniteMagnitude
            var j = i
            while j < areas.count {
                let shortSide = min(w, h)
                let candidate = rowAreas + [areas[j]]
                let ratio = worstRatio(candidate, shortSide)
                if row.isEmpty || ratio <= best {
                    best = ratio
                    row.append(j)
                    rowAreas.append(areas[j])
                    j += 1
                } else {
                    break
                }
            }
            let rowSum = rowAreas.reduce(0, +)
            if w >= h {
                let colW = rowSum / max(h, 0.0001)
                var yy = y
                for (k, idx) in row.enumerated() {
                    let cellH = rowAreas[k] / max(colW, 0.0001)
                    result[idx] = CGRect(x: x, y: yy, width: colW, height: cellH)
                    yy += cellH
                }
                x += colW
                w -= colW
            } else {
                let rowH = rowSum / max(w, 0.0001)
                var xx = x
                for (k, idx) in row.enumerated() {
                    let cellW = rowAreas[k] / max(rowH, 0.0001)
                    result[idx] = CGRect(x: xx, y: y, width: cellW, height: rowH)
                    xx += cellW
                }
                y += rowH
                h -= rowH
            }
            i = j
        }
        return result
    }

    private static func worstRatio(_ areas: [Double], _ side: Double) -> Double {
        let sum = areas.reduce(0, +)
        let maxA = areas.max() ?? 0
        let minA = areas.min() ?? 0
        guard sum > 0, minA > 0, side > 0 else { return .greatestFiniteMagnitude }
        let s2 = sum * sum
        let side2 = side * side
        return max(side2 * maxA / s2, s2 / (side2 * minA))
    }
}
