import Foundation
import UMEngine

// MARK: - Grid-scroll render spec

/// Describes which source cell to draw and at which display grid position.
struct CellRenderSpec {
    var cell:       UMGridCell
    var displayRow: Int
    var displayCol: Int
}

/// Builds the ordered list of `CellRenderSpec`s for one layer's cell pass.
///
/// When `scroll` is zero the result is equivalent to iterating `cells` in
/// natural order. When non-zero, display positions are remapped to their
/// source cells according to `mode`, and one extra column/row is appended
/// on the trailing edge to fill the sub-cell gap left by the fractional
/// scroll offset.
///
/// Callers apply the fractional pixel shift separately:
/// ```
/// let fracX = scroll.x - floor(scroll.x)
/// let fracY = scroll.y - floor(scroll.y)
/// mx = Double(spec.displayCol) * cellW + cellW/2 - fracX * cellW + ...
/// my = Double(spec.displayRow) * cellH + cellH/2 - fracY * cellH + ...
/// ```
func gridScrollRenderSpecs(
    cells: [UMGridCell],
    scroll: UMVec2,
    mode: GridScrollMode,
    rows: Int,
    cols: Int
) -> [CellRenderSpec] {
    // Fast path: no scroll active
    if scroll.x == 0 && scroll.y == 0 {
        return cells.filter(\.isDrawn).map { cell in
            CellRenderSpec(cell: cell,
                           displayRow: cell.gridIndex / cols,
                           displayCol: cell.gridIndex % cols)
        }
    }

    let intScrollC = Int(floor(scroll.x))
    let intScrollR = Int(floor(scroll.y))
    let fracX      = scroll.x - floor(scroll.x)
    let fracY      = scroll.y - floor(scroll.y)

    // One extra col/row on the trailing edge when there is a fractional offset,
    // so that the sub-pixel gap is filled by wrap-around content.
    let drawCols = fracX > 1e-9 ? cols + 1 : cols
    let drawRows = fracY > 1e-9 ? rows + 1 : rows

    var byIndex = [Int: UMGridCell]()
    byIndex.reserveCapacity(cells.count)
    for cell in cells where cell.isDrawn {
        byIndex[cell.gridIndex] = cell
    }

    var specs = [CellRenderSpec]()
    specs.reserveCapacity(drawRows * drawCols)

    for dr in 0..<drawRows {
        for dc in 0..<drawCols {
            let srcR: Int
            let srcC: Int
            switch mode {
            case .wrap:
                srcR = ((dr + intScrollR) % rows + rows) % rows
                srcC = ((dc + intScrollC) % cols + cols) % cols
            case .clamp:
                srcR = max(0, min(rows - 1, dr + intScrollR))
                srcC = max(0, min(cols - 1, dc + intScrollC))
            case .consume:
                let sr = dr + intScrollR
                let sc = dc + intScrollC
                guard sr >= 0 && sr < rows && sc >= 0 && sc < cols else { continue }
                srcR = sr; srcC = sc
            }
            if let cell = byIndex[srcR * cols + srcC] {
                specs.append(CellRenderSpec(cell: cell, displayRow: dr, displayCol: dc))
            }
        }
    }
    return specs
}
