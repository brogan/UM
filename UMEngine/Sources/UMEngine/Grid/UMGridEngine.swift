import Foundation
import Observation

/// Central engine for the UM grid.  Owns the document, drives animation,
/// and handles all grid editing with undo/redo.
///
/// All mutations must happen on the @MainActor; rendering calls CGContext
/// on the same thread for simplicity at this stage.
@MainActor
@Observable
public final class UMGridEngine {

    public var document: UMGridDocument
    public private(set) var currentFrame: Int = 0

    private var undoStack: [UMGridDocument] = []
    private var redoStack: [UMGridDocument] = []

    // Running count used by the .sequential phase policy
    private var paintOrderCounter: Int = 0

    public init(document: UMGridDocument = .makeDefault()) {
        self.document = document
    }

    // MARK: - Canvas geometry

    public var canvasSize: (width: Double, height: Double) {
        let c = document.gridConfig
        return (
            width:  Double(c.cols) * c.cellWidth  + Double(c.xOffset * 2),
            height: Double(c.rows) * c.cellHeight + Double(c.yOffset * 2)
        )
    }

    // MARK: - Playback

    public func advance() {
        currentFrame += 1
    }

    public func seek(toFrame frame: Int) {
        currentFrame = max(0, frame)
    }

    // MARK: - Cell editing

    public func setCellDrawn(_ index: Int, drawn: Bool,
                              styleID:  UUID,
                              motionID: UUID? = nil,
                              shapeID:  UUID? = nil,
                              pathID:   UUID? = nil) {
        guard index >= 0, index < document.cells.count else { return }
        document.cells[index].isDrawn = drawn
        if drawn {
            document.cells[index].styleID        = styleID
            document.cells[index].motionID       = motionID
            document.cells[index].shapeID        = shapeID
            document.cells[index].pathID         = pathID
            document.cells[index].phaseOffset    = computePhaseOffset(for: index)
            document.cells[index].positionOffset = randomOffset()
            paintOrderCounter += 1
        }
    }

    public func floodFill(from index: Int,
                           styleID:  UUID,
                           motionID: UUID? = nil,
                           shapeID:  UUID? = nil,
                           pathID:   UUID? = nil) {
        guard index >= 0, index < document.cells.count else { return }
        guard !document.cells[index].isDrawn else { return }
        var visited = Set<Int>()
        var queue   = [index]
        let cols    = document.gridConfig.cols
        let rows    = document.gridConfig.rows
        while !queue.isEmpty {
            let i = queue.removeFirst()
            guard !visited.contains(i), i >= 0, i < document.cells.count else { continue }
            visited.insert(i)
            guard !document.cells[i].isDrawn else { continue }
            setCellDrawn(i, drawn: true, styleID: styleID,
                         motionID: motionID, shapeID: shapeID, pathID: pathID)
            // 4-connected neighbours
            let r = i / cols, c = i % cols
            if r > 0       { queue.append(i - cols) }
            if r < rows-1  { queue.append(i + cols) }
            if c > 0       { queue.append(i - 1) }
            if c < cols-1  { queue.append(i + 1) }
        }
    }

    public func sampleStyle(at index: Int) -> CellStyle? {
        guard index >= 0, index < document.cells.count,
              document.cells[index].isDrawn else { return nil }
        return document.style(for: document.cells[index])
    }

    public func setPositionOffset(_ offset: UMOffset, for indices: Set<Int>) {
        for i in indices where i >= 0 && i < document.cells.count {
            document.cells[i].positionOffset = offset
        }
    }

    public func setPhaseOffset(_ phase: Int, for indices: Set<Int>) {
        for i in indices where i >= 0 && i < document.cells.count {
            document.cells[i].phaseOffset = phase
        }
    }

    public func rescatterSelection(_ indices: Set<Int>) {
        for i in indices where i >= 0 && i < document.cells.count {
            document.cells[i].positionOffset = randomOffset()
            document.cells[i].phaseOffset    = computePhaseOffset(for: i)
        }
    }

    // MARK: - Grid transforms

    public func flipHorizontal() {
        pushUndoSnapshot()
        let cols = document.gridConfig.cols
        let rows = document.gridConfig.rows
        var newCells = document.cells
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                let src = r * cols + c
                let dst = r * cols + (cols - 1 - c)
                newCells[dst] = document.cells[src]
                newCells[dst].gridIndex      = dst
                newCells[dst].positionOffset = document.cells[src].positionOffset.flippedHorizontally()
            }
        }
        document.cells = newCells
    }

    public func flipVertical() {
        pushUndoSnapshot()
        let cols = document.gridConfig.cols
        let rows = document.gridConfig.rows
        var newCells = document.cells
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                let src = r * cols + c
                let dst = (rows - 1 - r) * cols + c
                newCells[dst] = document.cells[src]
                newCells[dst].gridIndex      = dst
                newCells[dst].positionOffset = document.cells[src].positionOffset.flippedVertically()
            }
        }
        document.cells = newCells
    }

    public func rotateLeft90() {
        guard document.gridConfig.rows == document.gridConfig.cols else { return }
        pushUndoSnapshot()
        let n = document.gridConfig.rows
        var newCells = document.cells
        for r in 0 ..< n {
            for c in 0 ..< n {
                let src = r * n + c
                let dst = (n - 1 - c) * n + r
                newCells[dst] = document.cells[src]
                newCells[dst].gridIndex      = dst
                newCells[dst].positionOffset = document.cells[src].positionOffset.rotatedLeft90()
            }
        }
        document.cells = newCells
    }

    public func rotateRight90() {
        guard document.gridConfig.rows == document.gridConfig.cols else { return }
        pushUndoSnapshot()
        let n = document.gridConfig.rows
        var newCells = document.cells
        for r in 0 ..< n {
            for c in 0 ..< n {
                let src = r * n + c
                let dst = c * n + (n - 1 - r)
                newCells[dst] = document.cells[src]
                newCells[dst].gridIndex      = dst
                newCells[dst].positionOffset = document.cells[src].positionOffset.rotatedRight90()
            }
        }
        document.cells = newCells
    }

    // MARK: - Grid transforms (stamp / accumulate)
    //
    // Stamp variants keep every currently drawn cell in place and paint
    // the transformed copy on top, so repeated applications build up
    // rotationally or reflectionally symmetric patterns.

    public func flipHorizontalStamp(phaseOffset: Int = 0) {
        pushUndoSnapshot()
        let cols = document.gridConfig.cols
        let rows = document.gridConfig.rows
        let snap = document.cells                   // read from snapshot to avoid aliasing
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                let src = r * cols + c
                guard snap[src].isDrawn else { continue }
                let dst = r * cols + (cols - 1 - c)
                document.cells[dst].isDrawn        = true
                document.cells[dst].styleID        = snap[src].styleID
                document.cells[dst].positionOffset = snap[src].positionOffset.flippedHorizontally()
                document.cells[dst].phaseOffset    = snap[src].phaseOffset + phaseOffset
            }
        }
    }

    public func flipVerticalStamp(phaseOffset: Int = 0) {
        pushUndoSnapshot()
        let cols = document.gridConfig.cols
        let rows = document.gridConfig.rows
        let snap = document.cells
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                let src = r * cols + c
                guard snap[src].isDrawn else { continue }
                let dst = (rows - 1 - r) * cols + c
                document.cells[dst].isDrawn        = true
                document.cells[dst].styleID        = snap[src].styleID
                document.cells[dst].positionOffset = snap[src].positionOffset.flippedVertically()
                document.cells[dst].phaseOffset    = snap[src].phaseOffset + phaseOffset
            }
        }
    }

    public func rotateLeft90Stamp(phaseOffset: Int = 0) {
        guard document.gridConfig.rows == document.gridConfig.cols else { return }
        pushUndoSnapshot()
        let n    = document.gridConfig.rows
        let snap = document.cells
        for r in 0 ..< n {
            for c in 0 ..< n {
                let src = r * n + c
                guard snap[src].isDrawn else { continue }
                let dst = (n - 1 - c) * n + r
                document.cells[dst].isDrawn        = true
                document.cells[dst].styleID        = snap[src].styleID
                document.cells[dst].positionOffset = snap[src].positionOffset.rotatedLeft90()
                document.cells[dst].phaseOffset    = snap[src].phaseOffset + phaseOffset
            }
        }
    }

    public func rotateRight90Stamp(phaseOffset: Int = 0) {
        guard document.gridConfig.rows == document.gridConfig.cols else { return }
        pushUndoSnapshot()
        let n    = document.gridConfig.rows
        let snap = document.cells
        for r in 0 ..< n {
            for c in 0 ..< n {
                let src = r * n + c
                guard snap[src].isDrawn else { continue }
                let dst = c * n + (n - 1 - r)
                document.cells[dst].isDrawn        = true
                document.cells[dst].styleID        = snap[src].styleID
                document.cells[dst].positionOffset = snap[src].positionOffset.rotatedRight90()
                document.cells[dst].phaseOffset    = snap[src].phaseOffset + phaseOffset
            }
        }
    }

    // MARK: - Resolution resampling

    /// Nearest-neighbour resample to a new row × col count.
    /// Cell size (cellWidth/cellHeight) is preserved; the canvas simply
    /// holds more or fewer cells.  positionOffsets are kept as-is because
    /// they are in reference-pixel space and the cell size hasn't changed.
    public func resample(toRows newRows: Int, cols newCols: Int) {
        guard newRows > 0, newCols > 0 else { return }
        guard newRows != document.gridConfig.rows || newCols != document.gridConfig.cols else { return }
        pushUndoSnapshot()

        let oldRows = document.gridConfig.rows
        let oldCols = document.gridConfig.cols
        let cfg     = document.gridConfig   // snapshot before mutation

        let newCells = (0 ..< newRows * newCols).map { idx -> UMGridCell in
            let nr = idx / newCols
            let nc = idx % newCols
            // Centre-to-centre nearest-neighbour mapping into old grid space
            let oc = min(Int((Double(nc) + 0.5) * Double(oldCols) / Double(newCols)), oldCols - 1)
            let or = min(Int((Double(nr) + 0.5) * Double(oldRows) / Double(newRows)), oldRows - 1)
            var cell = document.cells[or * oldCols + oc]
            cell.gridIndex = idx
            guard cell.isDrawn else { return cell }

            // ResizeOffsetPolicy
            switch cfg.resizeOffsetPolicy {
            case .preserveAbsolute:
                break
            case .scaleProportional:
                // When cellWidth/cellHeight change in future, scale accordingly.
                // Currently both are unchanged so the ratio is 1 and this is a no-op.
                let sx = cfg.cellWidth  / cfg.cellWidth
                let sy = cfg.cellHeight / cfg.cellHeight
                cell.positionOffset = UMOffset(dx: cell.positionOffset.dx * sx,
                                               dy: cell.positionOffset.dy * sy)
            case .reset:
                cell.positionOffset = .zero
            }

            // ResizePhasePolicy
            switch cfg.resizePhasePolicy {
            case .inherit:
                break
            case .inheritWithScatter:
                let maxScatter = cfg.phaseStepFrames * 8
                let s = Int((Double(maxScatter) * cfg.resizePhaseScatter).rounded())
                if s > 0 { cell.phaseOffset += Int.random(in: -s ... s) }
            case .reset:
                cell.phaseOffset = 0
            }

            return cell
        }

        document.gridConfig.rows = newRows
        document.gridConfig.cols = newCols
        document.cells = newCells
    }

    public func clearAll() {
        pushUndoSnapshot()
        for i in document.cells.indices {
            document.cells[i].isDrawn = false
        }
    }

    public func invertDrawn() {
        pushUndoSnapshot()
        for i in document.cells.indices {
            document.cells[i].isDrawn.toggle()
        }
    }

    // MARK: - Undo / Redo

    public func pushUndoSnapshot() {
        var snap = document
        snap.timeline = []   // timeline is not part of cell-editing undo
        undoStack.append(snap)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        var snap = document
        snap.timeline = []
        redoStack.append(snap)
        document = prev
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Private helpers

    private func computePhaseOffset(for index: Int) -> Int {
        let c = document.gridConfig
        let row = index / c.cols
        let col = index % c.cols
        switch c.phasePolicy {
        case .synchronized:
            return 0
        case .random:
            return Int.random(in: 0 ..< 120)
        case .sequential:
            return paintOrderCounter * c.phaseStepFrames
        case .spatial:
            return (row + col) * c.phaseStepFrames
        case .radial:
            let cx = Double(c.cols - 1) / 2
            let cy = Double(c.rows - 1) / 2
            let dist = (pow(Double(col) - cx, 2) + pow(Double(row) - cy, 2)).squareRoot()
            return Int(dist.rounded()) * c.phaseStepFrames
        }
    }

    private func randomOffset() -> UMOffset {
        let scatter = document.gridConfig.spatialScatter
        guard scatter > 0 else { return .zero }
        let c = document.gridConfig
        return UMOffset(
            dx: Double.random(in: -1...1) * scatter * c.cellWidth,
            dy: Double.random(in: -1...1) * scatter * c.cellHeight
        )
    }
}
