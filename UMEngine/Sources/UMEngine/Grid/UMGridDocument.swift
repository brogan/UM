import Foundation

public struct UMGridDocument: Codable, Sendable {
    public var gridConfig:   UMGridConfig
    public var cells:        [UMGridCell]
    public var styles:       [CellStyle]
    public var paths:        [UMMotionPath]
    public var shapes:       [UMShape]
    public var timeline:     [UMTimelineState]
    public var colorSource:  UMColorSource?

    public init(
        gridConfig: UMGridConfig = UMGridConfig(),
        cells: [UMGridCell] = [],
        styles: [CellStyle] = [],
        paths: [UMMotionPath] = [],
        shapes: [UMShape] = [],
        timeline: [UMTimelineState] = [],
        colorSource: UMColorSource? = nil
    ) {
        self.gridConfig  = gridConfig
        self.cells       = cells
        self.styles      = styles
        self.paths       = paths
        self.shapes      = shapes
        self.timeline    = timeline
        self.colorSource = colorSource
    }

    // Custom Codable so that existing .umproj files without newer keys still load.
    private enum CodingKeys: String, CodingKey {
        case gridConfig, cells, styles, paths, shapes, timeline, colorSource
    }

    public init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        gridConfig   = try c.decode(UMGridConfig.self,   forKey: .gridConfig)
        cells        = try c.decode([UMGridCell].self,   forKey: .cells)
        styles       = try c.decode([CellStyle].self,    forKey: .styles)
        paths        = (try? c.decodeIfPresent([UMMotionPath].self,    forKey: .paths))    ?? []
        shapes       = (try? c.decodeIfPresent([UMShape].self,         forKey: .shapes))   ?? []
        timeline     = (try? c.decodeIfPresent([UMTimelineState].self, forKey: .timeline)) ?? []
        colorSource  = try? c.decodeIfPresent(UMColorSource.self,      forKey: .colorSource)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(gridConfig,  forKey: .gridConfig)
        try c.encode(cells,       forKey: .cells)
        try c.encode(styles,      forKey: .styles)
        try c.encode(paths,       forKey: .paths)
        try c.encode(shapes,      forKey: .shapes)
        try c.encode(timeline,    forKey: .timeline)
        try c.encodeIfPresent(colorSource, forKey: .colorSource)
    }

    /// Create a blank document with all cells undrawn.
    public static func makeDefault(rows: Int = 8, cols: Int = 8) -> UMGridDocument {
        let config = UMGridConfig(rows: rows, cols: cols)
        let cells  = (0 ..< rows * cols).map { UMGridCell(gridIndex: $0) }
        return UMGridDocument(gridConfig: config, cells: cells, styles: [])
    }

    /// Hard-coded demo: 6×6 grid, cross+diagonal pattern, sequential phase offsets,
    /// a few nudged positionOffsets — exercises the topology/geometry decoupling.
    public static func makeTestGrid() -> UMGridDocument {
        let rows = 6, cols = 6
        let style = CellStyle(name: "Default")

        // Indices to draw: column-3 vertical, row-2 horizontal, main diagonal
        let drawn: Set<Int> = {
            var s = Set<Int>()
            for r in 0..<rows { s.insert(r * cols + 3) }          // column 3
            for c in 0..<cols { s.insert(2 * cols + c) }          // row 2
            for d in 0..<min(rows, cols) { s.insert(d * cols + d) } // diagonal
            return s
        }()

        // Cells with non-zero positionOffset (demonstrates spatial independence)
        let nudges: [Int: UMOffset] = [
            0 * cols + 0: UMOffset(dx:  8, dy: -6),
            1 * cols + 1: UMOffset(dx: -5, dy:  9),
            2 * cols + 3: UMOffset(dx: 12, dy:  4),
        ]

        var paintOrder = 0
        let phaseStep  = 8

        var cells = (0 ..< rows * cols).map { idx -> UMGridCell in
            var cell = UMGridCell(gridIndex: idx)
            if drawn.contains(idx) {
                cell.isDrawn      = true
                cell.styleID      = style.id
                cell.positionOffset = nudges[idx] ?? .zero
                cell.phaseOffset  = paintOrder * phaseStep
                paintOrder += 1
            }
            return cell
        }

        let config = UMGridConfig(
            rows: rows, cols: cols,
            cellWidth: 80, cellHeight: 80,
            phasePolicy: .sequential, phaseStepFrames: phaseStep
        )
        return UMGridDocument(gridConfig: config, cells: cells, styles: [style])
    }

    // MARK: - Convenience accessors

    public func row(for index: Int) -> Int { index / gridConfig.cols }
    public func col(for index: Int) -> Int { index % gridConfig.cols }

    public func style(for cell: UMGridCell) -> CellStyle? {
        styles.first { $0.id == cell.styleID }
    }

    /// Nominal screen position of a cell's centre (before positionOffset is applied).
    public func nominalPosition(for index: Int) -> (x: Double, y: Double) {
        let c = gridConfig
        let x = Double(c.xOffset) + Double(col(for: index)) * c.cellWidth  + c.cellWidth  / 2
        let y = Double(c.yOffset) + Double(row(for: index)) * c.cellHeight + c.cellHeight / 2
        return (x, y)
    }

    /// Visual screen position: nominal + positionOffset.
    public func visualPosition(for cell: UMGridCell) -> (x: Double, y: Double) {
        let n = nominalPosition(for: cell.gridIndex)
        return (n.x + cell.positionOffset.dx, n.y + cell.positionOffset.dy)
    }
}
