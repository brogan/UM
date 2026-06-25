import Foundation
import LoomEngine
import UMEngine

// MARK: - Shape sequence resolver

/// Returns the effective shapeID for a cell, accounting for SEQUENCE cycling on the motionSet.
/// When sequenceMode is `.off` or shapeIDs is empty, falls back to the cell's own shapeID.
func resolveSequenceShapeID(
    motionSet: UMMotionSet?,
    cellShapeID: UUID?,
    frame: Int,
    phaseOffset: Int
) -> UUID? {
    guard let ms = motionSet,
          ms.sequenceMode != .off,
          !ms.shapeIDs.isEmpty
    else { return cellShapeID }

    let step = (frame + phaseOffset) / max(1, ms.framesPerStep)
    switch ms.sequenceMode {
    case .off:
        return cellShapeID
    case .sequential:
        let idx = ((step % ms.shapeIDs.count) + ms.shapeIDs.count) % ms.shapeIDs.count
        return ms.shapeIDs[idx]
    case .random:
        // Multiply by a large prime to break periodic patterns across cells/frames
        let seed = abs(step &* 2654435761 &+ phaseOffset)
        return ms.shapeIDs[seed % ms.shapeIDs.count]
    }
}

/// Returns the effective shapeID for a sprite, checking for an assigned animated geometry
/// first (which overrides shapeID and SEQUENCE cycling), then falling back to SEQUENCE,
/// then to the sprite's own shapeID.
func resolveEffectiveSpriteShapeID(
    sprite: UMSprite,
    motionSet: UMMotionSet?,
    animatedGeometries: [UMAnimatedGeometry],
    frame: Int
) -> UUID? {
    if let geoID = sprite.animatedGeometryID,
       let geo = animatedGeometries.first(where: { $0.id == geoID }) {
        return geo.resolveShapeID(atFrame: frame + sprite.phaseOffset)
    }
    return resolveSequenceShapeID(motionSet: motionSet, cellShapeID: sprite.shapeID,
                                  frame: frame, phaseOffset: sprite.phaseOffset)
}

/// Returns the effective style override for a sprite from its animated geometry (if assigned),
/// or nil if there is no animated geometry or it carries no style at this frame.
func resolveEffectiveSpriteStyleID(
    sprite: UMSprite,
    animatedGeometries: [UMAnimatedGeometry],
    frame: Int
) -> UUID? {
    guard let geoID = sprite.animatedGeometryID,
          let geo = animatedGeometries.first(where: { $0.id == geoID })
    else { return nil }
    return geo.resolveStyleID(atFrame: frame + sprite.phaseOffset)
}

/// Returns the per-state transform for the active animated geometry state at the given frame,
/// or .identity if the sprite has no animated geometry assigned.
/// Used by hit-testing (primary layer only); render sites use resolveEffectiveSpriteLayers.
func resolveEffectiveSpriteStateTransform(
    sprite: UMSprite,
    animatedGeometries: [UMAnimatedGeometry],
    frame: Int
) -> UMAnimatedGeometryStateTransform {
    guard let geoID = sprite.animatedGeometryID,
          let geo = animatedGeometries.first(where: { $0.id == geoID })
    else { return .identity }
    return geo.resolveStateTransform(atFrame: frame + sprite.phaseOffset)
}

/// Returns the render layers for this sprite at the given frame.
/// Animated geometry sprites: calls geo.resolveRenderLayers (1 or 2 layers during transitions).
/// Non-animated sprites: returns a single synthetic layer with SEQUENCE-resolved shapeID.
/// Render sites iterate these layers, drawing each at layer.alpha opacity.
func resolveEffectiveSpriteLayers(
    sprite: UMSprite,
    motionSet: UMMotionSet?,
    animatedGeometries: [UMAnimatedGeometry],
    frame: Int
) -> [UMRenderLayer] {
    if let geoID = sprite.animatedGeometryID,
       let geo = animatedGeometries.first(where: { $0.id == geoID }) {
        return geo.resolveRenderLayers(atFrame: frame + sprite.phaseOffset)
    }
    let shapeID = resolveSequenceShapeID(motionSet: motionSet, cellShapeID: sprite.shapeID,
                                         frame: frame, phaseOffset: sprite.phaseOffset)
    guard let sid = shapeID else { return [] }
    return [UMRenderLayer(shapeID: sid, styleID: nil, alpha: 1.0, transform: .identity)]
}

// MARK: - Morph blend

/// Attempts per-vertex morph interpolation between the two render layers.
///
/// Returns `(polygons, transform)` when the two shapes have identical topology
/// (same polygon count, same per-polygon vertex count), so vertex positions can
/// be lerped at `t = geoLayers[1].alpha`. Returns `nil` when topology doesn't
/// match — callers should fall back to the existing alpha cross-fade.
///
/// The blended transform interpolates all five per-state fields (offsetX/Y,
/// rotation, scaleX/Y) so position, rotation, and scale also animate smoothly.
///
/// `type`, `pressures`, `pressureProfiles`, and `visible` are preserved from
/// the base (from-layer) polygons, matching Loom's MorphInterpolator contract.
func attemptMorphLayers(
    _ geoLayers: [UMRenderLayer],
    shapeMap: [UUID: [Polygon2D]],
    fallback: [Polygon2D]
) -> (polygons: [Polygon2D], transform: UMAnimatedGeometryStateTransform)? {
    guard geoLayers.count == 2 else { return nil }
    let from = geoLayers[0], to = geoLayers[1]
    let t = to.alpha                         // progress: 0...1
    guard t > 0 && t < 1 else { return nil }

    let fromPolys = (shapeMap[from.shapeID] ?? fallback).filter(\.visible)
    let toPolys   = (shapeMap[to.shapeID]   ?? fallback).filter(\.visible)

    guard !fromPolys.isEmpty,
          fromPolys.count == toPolys.count,
          zip(fromPolys, toPolys).allSatisfy({ $0.points.count == $1.points.count })
    else { return nil }

    // Lerp vertex positions; preserve all non-geometric fields from base.
    let morphed: [Polygon2D] = zip(fromPolys, toPolys).map { (f, tgt) in
        let pts = zip(f.points, tgt.points).map { Vector2D.lerp($0, $1, t: t) }
        return Polygon2D(points: pts, type: f.type,
                        pressures: f.pressures,
                        pressureProfiles: f.pressureProfiles,
                        visible: true)
    }

    // Lerp per-state transform fields.
    let ft = from.transform, tt = to.transform
    var blended = ft
    blended.offsetX  = ft.offsetX  + (tt.offsetX  - ft.offsetX)  * t
    blended.offsetY  = ft.offsetY  + (tt.offsetY  - ft.offsetY)  * t
    blended.rotation = ft.rotation + (tt.rotation - ft.rotation) * t
    blended.scaleX   = ft.scaleX   + (tt.scaleX   - ft.scaleX)   * t
    blended.scaleY   = ft.scaleY   + (tt.scaleY   - ft.scaleY)   * t

    return (morphed, blended)
}

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
