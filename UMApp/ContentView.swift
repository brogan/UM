import SwiftUI
import UMEngine
import LoomEngine

private let umCompositingColorSpace: CGColorSpace =
    CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

struct ContentView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        VStack(spacing: 0) {
            ToolStripView()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.bar)

            Divider()

            HSplitView {
                StylePaletteView()
                    .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)

                GridCanvasPlaceholder()
                    .frame(minWidth: 400)

                QuickAdjustView()
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
            }

            Divider()

            UMTimelinePanel()

            TransportBarView()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.bar)
        }
    }
}

// MARK: - Tool strip

struct ToolStripView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PaintTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }

            Divider().frame(height: 16).padding(.horizontal, 4)

            // Transform mode toggle
            transformModeToggle

            Divider().frame(height: 16).padding(.horizontal, 4)

            stampPhaseOffsetControl

            iconButton("↔", help: "Flip horizontal")  { transform(move: controller.engine.flipHorizontal) { controller.engine.flipHorizontalStamp(phaseOffset: controller.stampPhaseOffset) } }
            iconButton("↕", help: "Flip vertical")    { transform(move: controller.engine.flipVertical)   { controller.engine.flipVerticalStamp(phaseOffset: controller.stampPhaseOffset) } }
            iconButton("↺", help: "Rotate left")      { transform(move: controller.engine.rotateLeft90)   { controller.engine.rotateLeft90Stamp(phaseOffset: controller.stampPhaseOffset) } }
            iconButton("↻", help: "Rotate right")     { transform(move: controller.engine.rotateRight90)  { controller.engine.rotateRight90Stamp(phaseOffset: controller.stampPhaseOffset) } }

            Divider().frame(height: 16).padding(.horizontal, 4)

            iconButton("⊡", help: "Clear all")        { controller.engine.clearAll() }
            iconButton("⊟", help: "Invert")           { controller.engine.invertDrawn() }

            Spacer()

            // Paint-time phase policy — applied whenever a new cell is drawn
            Picker("", selection: Binding(
                get: { controller.engine.document.gridConfig.phasePolicy },
                set: { controller.engine.document.gridConfig.phasePolicy = $0 }
            )) {
                ForEach(PhasePolicy.allCases, id: \.self) { p in
                    Text(p.rawValue.capitalized).tag(p)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 112)
            .font(.system(size: 11))
            .help("Phase policy for newly painted cells")

            // Phase step frames — step size used by Sequential, Spatial, Radial policies
            phaseStepControl

            Divider().frame(height: 16).padding(.horizontal, 4)

            // Spatial scatter — random position offset applied when cells are painted
            scatterControl

            Divider().frame(height: 16).padding(.horizontal, 4)

            Toggle("Stretch", isOn: Binding(
                get: { controller.stretchSpritesToCell },
                set: { controller.stretchSpritesToCell = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .help("Stretch sprites to fill their cell")
        }
        .font(.system(size: 13))
    }

    private var transformModeToggle: some View {
        HStack(spacing: 0) {
            modeButton("Move",  mode: .move)
            modeButton("Stamp", mode: .stamp)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func modeButton(_ label: String, mode: TransformMode) -> some View {
        let active = controller.transformMode == mode
        return Button(label) { controller.transformMode = mode }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(active ? Color.accentColor.opacity(0.18) : Color.clear)
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
    }

    private func transform(move: () -> Void, _ stamp: () -> Void) {
        switch controller.transformMode {
        case .move:  move()
        case .stamp: stamp()
        }
    }

    private var stampPhaseOffsetControl: some View {
        let isStamp = controller.transformMode == .stamp
        return HStack(spacing: 3) {
            Text("Δφ")
                .font(.system(size: 10))
                .foregroundStyle(isStamp ? .secondary : .tertiary)
            HStack(spacing: 0) {
                Button("−") { controller.stampPhaseOffset -= 1 }
                    .buttonStyle(.plain)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                Text(controller.stampPhaseOffset >= 0
                     ? "+\(controller.stampPhaseOffset)"
                     : "\(controller.stampPhaseOffset)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 28)
                    .multilineTextAlignment(.center)
                Button("+") { controller.stampPhaseOffset += 1 }
                    .buttonStyle(.plain)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .disabled(!isStamp)
            .opacity(isStamp ? 1 : 0.4)
        }
    }

    private var phaseStepControl: some View {
        HStack(spacing: 3) {
            Text("φ step")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Button("−") {
                    controller.engine.document.gridConfig.phaseStepFrames =
                        max(1, controller.engine.document.gridConfig.phaseStepFrames - 1)
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                Text("\(controller.engine.document.gridConfig.phaseStepFrames) fr")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 36)
                    .multilineTextAlignment(.center)
                Button("+") {
                    controller.engine.document.gridConfig.phaseStepFrames =
                        min(240, controller.engine.document.gridConfig.phaseStepFrames + 1)
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        .help("Phase step frames — used by Sequential, Spatial, and Radial policies")
    }

    private var scatterControl: some View {
        HStack(spacing: 4) {
            Text("Scatter")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { controller.engine.document.gridConfig.spatialScatter },
                set: { controller.engine.document.gridConfig.spatialScatter = $0 }
            ), in: 0...1)
            .frame(width: 80)
            .help("Random position scatter applied when cells are painted (0 = none, 1 = up to ±1 cell)")
        }
    }

    private func toolButton(_ tool: PaintTool) -> some View {
        let active = controller.activeTool == tool
        return Button(tool.rawValue) { controller.activeTool = tool }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(active ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(active ? Color.accentColor : Color.primary)
    }

    private func iconButton(_ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
            .foregroundStyle(Color.secondary)
            .help(help)
    }
}

// MARK: - UMBlendMode rendering bridges

extension UMBlendMode {
    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:     return .normal
        case .multiply:   return .multiply
        case .screen:     return .screen
        case .overlay:    return .overlay
        case .dodge:      return .colorDodge
        case .burn:       return .colorBurn
        case .softLight:  return .softLight
        case .hardLight:  return .hardLight
        case .difference: return .difference
        case .exclusion:  return .exclusion
        case .add:        return .plusLighter
        }
    }

    var swiftUIBlendMode: GraphicsContext.BlendMode {
        switch self {
        case .normal:     return .normal
        case .multiply:   return .multiply
        case .screen:     return .screen
        case .overlay:    return .overlay
        case .dodge:      return .colorDodge
        case .burn:       return .colorBurn
        case .softLight:  return .softLight
        case .hardLight:  return .hardLight
        case .difference: return .difference
        case .exclusion:  return .exclusion
        case .add:        return .plusLighter
        }
    }
}

// MARK: - Accumulation buffer — background CG rendering

private struct LayerAccumulationData: @unchecked Sendable {
    let cells: [UMGridCell]
    let styles: [CellStyle]
    let paths: [UMMotionPath]
    let config: UMGridConfig
    let opacity: Double
    let colorSource: UMColorSource?
    let colorGrid: [[UMColor]]?
    // Per-layer geometry (derived from gridW/gridH and each layer's col/row count)
    let cellW: Double
    let cellH: Double
    let scaleX: Double
    let scaleY: Double
    // Grid scroll
    let gridScrollDriver: UMVectorDriver
    let gridScrollMode: GridScrollMode
    // Sprite layer fields
    let layerMode: LayerMode
    let sprites: [UMSprite]
    let gridW: Double  // canvas width in SwiftUI points (needed for sprite position scaling)
    let gridH: Double
    let blendMode: UMBlendMode
}

private struct AccumulationSnapshot: @unchecked Sendable {
    let layers: [LayerAccumulationData]
    let previousBuffer: CGImage?
    let backgroundColor: UMColor
    let backgroundImage: CGImage?
    let shapePolygonMap: [UUID: [Polygon2D]]
    let shapePolygonIDMap: [UUID: [UUID]]
    let fallbackPolygons: [Polygon2D]
    let projectMotionSets: [UMMotionSet]
    let projectAnimatedGeometries: [UMAnimatedGeometry]
    let stretchSprites: Bool
    let frame: Int
    let pw: Int
    let ph: Int
    let displayScale: CGFloat
}

// Composites all visible layers into a new CGImage on a background thread.
// Uses direct CG drawing — no SwiftUI ImageRenderer, no main-thread blocking.
private nonisolated func renderAccumulationCG(_ snap: AccumulationSnapshot) -> CGImage? {
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                   | CGBitmapInfo.byteOrder32Little.rawValue
    guard let mainCtx = CGContext(data: nil, width: snap.pw, height: snap.ph,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: umCompositingColorSpace,
                                   bitmapInfo: bitmapInfo) else { return nil }
    let frame = CGRect(x: 0, y: 0, width: snap.pw, height: snap.ph)

    // Base layer: previous accumulated frame, or solid background + image
    if let buf = snap.previousBuffer {
        mainCtx.draw(buf, in: frame)
    } else {
        let bg = snap.backgroundColor
        mainCtx.setFillColor(CGColor(red: bg.r, green: bg.g, blue: bg.b, alpha: bg.a))
        mainCtx.fill(frame)
        if let bgImg = snap.backgroundImage { mainCtx.draw(bgImg, in: frame) }
    }

    for layer in snap.layers {
        guard let layerImage = renderLayerCG(layer, snap: snap) else { continue }
        mainCtx.setBlendMode(layer.blendMode.cgBlendMode)
        mainCtx.setAlpha(layer.opacity)
        mainCtx.draw(layerImage, in: frame)
        mainCtx.setAlpha(1.0)
        mainCtx.setBlendMode(.normal)
    }
    return mainCtx.makeImage()
}

// Renders one layer's cells to a CGImage in pixel space.
// Applies a y-flip transform so cell coordinates match the SwiftUI Canvas convention
// (y-down, origin top-left). This produces the same visual result as ImageRenderer+FrameCapture.
private nonisolated func renderLayerCG(_ layer: LayerAccumulationData,
                                        snap: AccumulationSnapshot) -> CGImage? {
    let pw = snap.pw, ph = snap.ph
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                   | CGBitmapInfo.byteOrder32Little.rawValue
    guard let ctx = CGContext(data: nil, width: pw, height: ph,
                               bitsPerComponent: 8, bytesPerRow: 0,
                               space: umCompositingColorSpace,
                               bitmapInfo: bitmapInfo) else { return nil }

    // Mirror y-axis so drawing coordinates match Canvas (y increases downward)
    ctx.translateBy(x: 0, y: CGFloat(ph))
    ctx.scaleBy(x: 1, y: -1)

    let dsf       = Double(snap.displayScale)
    let styleMap  = Dictionary(uniqueKeysWithValues: layer.styles.map  { ($0.id, $0) })
    let motionMap = Dictionary(uniqueKeysWithValues: snap.projectMotionSets.map { ($0.id, $0) })

    // Sprite layer path
    if layer.layerMode == .sprite {
        let spriteRef = min(layer.gridW, layer.gridH) / 8.0
        for (idx, sprite) in layer.sprites.enumerated() {
            let motionSet = sprite.motionID.flatMap { motionMap[$0] }
            let styleOverrideID = resolveEffectiveSpriteStyleID(sprite: sprite,
                                                                 animatedGeometries: snap.projectAnimatedGeometries,
                                                                 frame: snap.frame)
            let style     = (styleOverrideID ?? sprite.styleID).flatMap { styleMap[$0] }
            let motion    = computeMotion(motionSet: motionSet, style: style, path: nil,
                                          frame: snap.frame, phaseOffset: sprite.phaseOffset,
                                          cellIndex: idx,
                                          cellW: spriteRef * sprite.scaleX,
                                          cellH: spriteRef * sprite.scaleY)
            let driverPos = DriverEvaluator.evaluate(sprite.positionDriver, frame: snap.frame, spriteIndex: idx)
            let stateT = resolveEffectiveSpriteStateTransform(sprite: sprite,
                                                              animatedGeometries: snap.projectAnimatedGeometries,
                                                              frame: snap.frame)
            let mx = (sprite.x * layer.gridW + motion.dx + driverPos.x + stateT.offsetX) * dsf
            let my = (sprite.y * layer.gridH + motion.dy + driverPos.y + stateT.offsetY) * dsf
            let effectiveShapeID = resolveEffectiveSpriteShapeID(sprite: sprite, motionSet: motionSet,
                                                                  animatedGeometries: snap.projectAnimatedGeometries,
                                                                  frame: snap.frame)
            let polygons   = resolvePolygons(shapeID: effectiveShapeID,
                                             shapeMap: snap.shapePolygonMap,
                                             fallback: snap.fallbackPolygons)
            let polygonIDs = resolvePolygonIDs(shapeID: effectiveShapeID, idMap: snap.shapePolygonIDMap)
            let zoomX = (spriteRef / 2) * sprite.scaleX * motion.scaleX * stateT.scaleX * dsf
            let zoomY = (spriteRef / 2) * sprite.scaleY * motion.scaleY * stateT.scaleY * dsf
            let rot   = sprite.rotation + motion.rotation + stateT.rotation
            let fillC   = style?.fillColor   ?? .defaultFill
            let strokeC = style?.strokeColor ?? .defaultStroke
            let strokeW = (style?.strokeWidth ?? 1.5) * dsf
            let mode    = style?.renderMode  ?? .filledStroked
            if polygons.isEmpty {
                let rect = CGRect(x: mx - zoomX, y: my - zoomY, width: zoomX * 2, height: zoomY * 2)
                let cgp  = CGPath(roundedRect: rect, cornerWidth: 3 * dsf, cornerHeight: 3 * dsf, transform: nil)
                ctx.setFillColor(CGColor(red: fillC.r, green: fillC.g, blue: fillC.b, alpha: fillC.a))
                ctx.addPath(cgp); ctx.fillPath()
            } else {
                for (i, polygon) in polygons.filter(\.visible).enumerated() {
                    let ovr = sprite.polygonOverrides[polygonIDs[safe: i]?.uuidString ?? ""]
                    let fC  = ovr?.fill   ?? fillC
                    let sC  = ovr?.stroke ?? strokeC
                    let cgp = buildPolygonPath(polygon, cx: mx, cy: my,
                                               zoomX: zoomX, zoomY: zoomY,
                                               scaleX: 1.0, scaleY: 1.0, rotation: rot)
                    if mode == .filled || mode == .filledStroked {
                        ctx.setFillColor(CGColor(red: fC.r, green: fC.g, blue: fC.b, alpha: fC.a))
                        ctx.addPath(cgp); ctx.fillPath()
                    }
                    if mode == .stroked || mode == .filledStroked {
                        ctx.setStrokeColor(CGColor(red: sC.r, green: sC.g, blue: sC.b, alpha: sC.a))
                        ctx.setLineWidth(CGFloat(strokeW))
                        ctx.addPath(cgp); ctx.strokePath()
                    }
                }
            }
        }
        return ctx.makeImage()
    }

    let cellW     = layer.cellW, cellH = layer.cellH
    let half      = min(cellW, cellH)
    let pathMap   = Dictionary(uniqueKeysWithValues: layer.paths.map   { ($0.id, $0) })

    let cgScroll = DriverEvaluator.evaluate(layer.gridScrollDriver, frame: snap.frame)
    let cgFracX  = cgScroll.x - floor(cgScroll.x)
    let cgFracY  = cgScroll.y - floor(cgScroll.y)
    let cgSpecs  = gridScrollRenderSpecs(cells: layer.cells, scroll: cgScroll,
                                          mode: layer.gridScrollMode,
                                          rows: layer.config.rows, cols: layer.config.cols)
    for spec in cgSpecs {
        let cell      = spec.cell
        let r         = spec.displayRow
        let c         = spec.displayCol
        let style     = styleMap[cell.styleID]
        let motionSet = cell.motionID.flatMap { motionMap[$0] }
        let path      = cell.pathID.flatMap { pathMap[$0] }
        var motion    = computeMotion(motionSet: motionSet, style: style, path: path,
                                      frame: snap.frame, phaseOffset: cell.phaseOffset,
                                      cellIndex: cell.gridIndex, cellW: cellW, cellH: cellH)
        if let src = layer.colorSource, let grid = layer.colorGrid,
           r < grid.count, c < grid[r].count {
            applyColorMap(grid[r][c], source: src, style: style, to: &motion)
        }

        let mx = (Double(c) * cellW + cellW/2 - cgFracX * cellW + cell.positionOffset.dx * layer.scaleX + motion.dx) * dsf
        let my = (Double(r) * cellH + cellH/2 - cgFracY * cellH + cell.positionOffset.dy * layer.scaleY + motion.dy) * dsf

        let fillC   = motion.fillOverride   ?? style?.fillColor   ?? .defaultFill
        let strokeC = motion.strokeOverride ?? style?.strokeColor ?? .defaultStroke
        let strokeW = (style?.strokeWidth ?? 1.5) * dsf
        let mode    = style?.renderMode ?? .filledStroked

        let effectiveShapeID = resolveSequenceShapeID(motionSet: motionSet,
                                                      cellShapeID: cell.shapeID,
                                                      frame: snap.frame,
                                                      phaseOffset: cell.phaseOffset)
        let polygons = resolvePolygons(shapeID: effectiveShapeID,
                                       shapeMap: snap.shapePolygonMap,
                                       fallback: snap.fallbackPolygons)

        if polygons.isEmpty {
            let rw = (cellW - 4) / 2 * motion.scaleX * dsf
            let rh = (cellH - 4) / 2 * motion.scaleY * dsf
            let rect = CGRect(x: mx - rw, y: my - rh, width: rw * 2, height: rh * 2)
            let cgp  = CGPath(roundedRect: rect, cornerWidth: 3 * dsf, cornerHeight: 3 * dsf, transform: nil)
            ctx.setFillColor(CGColor(red: fillC.r, green: fillC.g, blue: fillC.b, alpha: fillC.a))
            ctx.addPath(cgp); ctx.fillPath()
        } else {
            let zoomX = (snap.stretchSprites ? cellW : half) * motion.scaleX * dsf
            let zoomY = (snap.stretchSprites ? cellH : half) * motion.scaleY * dsf
            for polygon in polygons.filter(\.visible) {
                let cgp = buildPolygonPath(polygon, cx: mx, cy: my,
                                           zoomX: zoomX, zoomY: zoomY,
                                           scaleX: cell.scaleX, scaleY: cell.scaleY,
                                           rotation: cell.rotation + motion.rotation)
                if mode == .filled || mode == .filledStroked {
                    ctx.setFillColor(CGColor(red: fillC.r, green: fillC.g, blue: fillC.b, alpha: fillC.a))
                    ctx.addPath(cgp); ctx.fillPath()
                }
                if mode == .stroked || mode == .filledStroked {
                    ctx.setStrokeColor(CGColor(red: strokeC.r, green: strokeC.g, blue: strokeC.b, alpha: strokeC.a))
                    ctx.setLineWidth(CGFloat(strokeW))
                    ctx.addPath(cgp); ctx.strokePath()
                }
            }
        }
    }
    return ctx.makeImage()
}

// MARK: - Tangent drag state

private enum TangentHandle { case out, `in` }

private struct TangentDragState {
    var kfID:         UUID
    var which:        TangentHandle
    var startTangentX: Double
    var startTangentY: Double
    var startCanvasPt: CGPoint
}

// MARK: - Grid canvas

struct GridCanvasPlaceholder: View {
    @Environment(AppController.self) private var controller
    @Environment(\.displayScale) private var displayScale
    @State private var lastDragIndex: Int?         = nil
    @State private var lastNudgeLocation: CGPoint? = nil
    @State private var captureTask: Task<Void, Never>? = nil
    // Rubber-band selection state
    @State private var rubberBandStart:   CGPoint? = nil
    @State private var rubberBandCurrent: CGPoint? = nil
    // Cached layout — needed in onEnded where geo is out of scope
    @State private var cachedCellW: Double = 1
    @State private var cachedCellH: Double = 1
    @State private var cachedGridW: Double = 400
    @State private var cachedGridH: Double = 400
    // Sprite drag state
    @State private var spriteDragID:          UUID?    = nil
    @State private var spriteDragOffset:      CGPoint  = .zero
    @State private var spriteDragIsKeyframe:  Bool     = false
    // Zoom/pan state
    @State private var baseZoom: Double = 1.0
    @State private var scrollMonitor: Any? = nil
    // Hover preview state
    @State private var hoverViewPoint: CGPoint? = nil
    // Bezier tangent handle drag state
    @State private var tangentDragState: TangentDragState? = nil

    var body: some View {
        GeometryReader { geo in
            let config       = controller.engine.document.gridConfig
            let currentFrame = controller.engine.currentFrame

            // Canvas letterboxes to maintain the user-defined output aspect ratio.
            let canvasAspect = config.canvasWidth / config.canvasHeight
            let winAspect    = geo.size.width / geo.size.height
            let gridH = winAspect > canvasAspect ? geo.size.height        : geo.size.width / canvasAspect
            let gridW = winAspect > canvasAspect ? gridH * canvasAspect   : geo.size.width
            let cellW  = gridW / Double(config.cols)
            let cellH  = gridH / Double(config.rows)
            let scaleX = cellW / config.cellWidth
            let scaleY = cellH / config.cellHeight

            let bg   = controller.backgroundColor
            let zoom = controller.canvasZoom
            let pan  = controller.canvasPan
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                Canvas { ctx, size in
                    // Pan/zoom transform — all subsequent drawing is in canvas space (0,0,gridW,gridH)
                    let tx = (size.width  - gridW * zoom) / 2 + pan.width
                    let ty = (size.height - gridH * zoom) / 2 + pan.height
                    ctx.concatenate(CGAffineTransform(translationX: tx, y: ty).scaledBy(x: zoom, y: zoom))
                    ctx.clip(to: Path(CGRect(origin: .zero, size: CGSize(width: gridW, height: gridH))))

                    // Background
                    let bgColor   = Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)
                    let bgRect    = CGRect(origin: .zero, size: CGSize(width: gridW, height: gridH))
                    if controller.backgroundDraw {
                        ctx.fill(Path(bgRect), with: .color(bgColor))
                        if let bgImg = controller.backgroundCGImage {
                            let resolved = ctx.resolve(Image(decorative: bgImg, scale: 1))
                            ctx.draw(resolved, in: bgRect)
                        }
                    } else if let buf = controller.frameBuffer {
                        let img = ctx.resolve(Image(decorative: buf, scale: displayScale))
                        ctx.draw(img, in: bgRect)
                    } else {
                        ctx.fill(Path(bgRect), with: .color(bgColor))
                        if let bgImg = controller.backgroundCGImage {
                            let resolved = ctx.resolve(Image(decorative: bgImg, scale: 1))
                            ctx.draw(resolved, in: bgRect)
                        }
                    }

                    // Grid lines — only when enabled
                    if controller.showGrid {
                        let gc = controller.gridColor
                        var linePath = Path()
                        let activeDistortion = controller.layerStates[safe: controller.activeLayerIndex]?.gridDistortion ?? .none
                        if case .perspective(let vStr, let hStr, let conv) = activeDistortion {
                            let rowH = UMGridDistortion.perspectiveSizes(count: config.rows, total: gridH, strength: vStr)
                            let colW = UMGridDistortion.perspectiveSizes(count: config.cols, total: gridW, strength: hStr)

                            if conv > 1e-6, abs(vStr) > 1e-6 {
                                // Converging lines: vertical lines fan out, horizontal lines vary in width.
                                // Top boundary (row 0) fills exactly gridW; lower rows overflow and are clipped.
                                let (topLeft, topWidth) = UMGridDistortion.convergenceBand(
                                    forRow: 0, rowHeights: rowH, gridW: gridW, convergence: conv)
                                let (botLeft, botWidth) = UMGridDistortion.convergenceBand(
                                    forRow: config.rows - 1, rowHeights: rowH, gridW: gridW, convergence: conv)
                                // Vertical lines: straight from top boundary to bottom boundary
                                for c in 0...config.cols {
                                    let frac = Double(c) / Double(config.cols)
                                    let xTop = topLeft + frac * topWidth
                                    let xBot = botLeft + frac * botWidth
                                    linePath.move(to: CGPoint(x: xTop, y: 0))
                                    linePath.addLine(to: CGPoint(x: xBot, y: gridH))
                                }
                                // Horizontal lines: each spans its row's convergence band
                                var cumY = 0.0
                                for r in 0...config.rows {
                                    let rowIdx = min(r, config.rows - 1)
                                    let (left, width) = UMGridDistortion.convergenceBand(
                                        forRow: rowIdx, rowHeights: rowH, gridW: gridW, convergence: conv)
                                    linePath.move(to: CGPoint(x: left, y: cumY))
                                    linePath.addLine(to: CGPoint(x: left + width, y: cumY))
                                    if r < config.rows { cumY += rowH[r] }
                                }
                            } else {
                                // Standard perspective: straight vertical/horizontal lines at computed pitches
                                var x = 0.0
                                for i in 0...config.cols {
                                    linePath.move(to: CGPoint(x: x, y: 0))
                                    linePath.addLine(to: CGPoint(x: x, y: gridH))
                                    if i < colW.count { x += colW[i] }
                                }
                                var y = 0.0
                                for i in 0...config.rows {
                                    linePath.move(to: CGPoint(x: 0, y: y))
                                    linePath.addLine(to: CGPoint(x: gridW, y: y))
                                    if i < rowH.count { y += rowH[i] }
                                }
                            }
                        } else {
                            for c in 0...config.cols {
                                let x = Double(c) * cellW
                                linePath.move(to: CGPoint(x: x, y: 0))
                                linePath.addLine(to: CGPoint(x: x, y: gridH))
                            }
                            for r in 0...config.rows {
                                let y = Double(r) * cellH
                                linePath.move(to: CGPoint(x: 0, y: y))
                                linePath.addLine(to: CGPoint(x: gridW, y: y))
                            }
                        }
                        ctx.stroke(linePath,
                                   with: .color(Color(red: gc.r, green: gc.g, blue: gc.b, opacity: gc.a)),
                                   lineWidth: controller.gridLineWidth)
                    }

                    // Phase heat-map overlay (active grid layer only, raw canvas space)
                    if controller.showPhaseHeatmap,
                       controller.layerStates[safe: controller.activeLayerIndex]?.layerMode == .grid {
                        let hmCells  = controller.engine.document.cells
                        let maxPhase = hmCells.map { $0.phaseOffset }.max() ?? 0
                        if maxPhase > 0 {
                            for cell in hmCells where cell.styleID != nil {
                                let row = cell.gridIndex / config.cols
                                let col = cell.gridIndex % config.cols
                                let t   = Double(cell.phaseOffset) / Double(maxPhase)
                                let hue = (1.0 - t) * 0.667  // blue (t=0) → red (t=1)
                                let rect = CGRect(x: Double(col) * cellW, y: Double(row) * cellH,
                                                  width: cellW, height: cellH)
                                ctx.fill(Path(rect),
                                         with: .color(Color(hue: hue, saturation: 0.85, brightness: 0.9, opacity: 0.5)))
                            }
                        }
                    }

                    // Drawn cells — render each layer into an isolated compositing group.
                    let shapePolyMap   = controller.shapePolygonMap
                    let shapePolyIDMap = controller.shapePolygonIDMap
                    let fallbackPolys  = controller.shapePolygons
                    let stretch       = controller.stretchSpritesToCell
                    let cameraFrame   = controller.camera.evaluate(frame: currentFrame)

                    for ls in controller.layerStates where ls.isVisible {
                        // --- Sprite layer branch ---
                        if ls.layerMode == .sprite {
                            let lOpacity   = DriverEvaluator.evaluate(ls.opacityDriver, frame: currentFrame)
                            let lMotionMap = Dictionary(uniqueKeysWithValues: controller.projectMotionSets.map { ($0.id, $0) })
                            let lLayerOff  = DriverEvaluator.evaluate(ls.layerOffset, frame: currentFrame)
                            let lLayerXF   = umLayerTransform(cameraFrame: cameraFrame,
                                                               parallaxFactor: ls.parallaxFactor,
                                                               layerOffset: lLayerOff,
                                                               canvasW: gridW, canvasH: gridH)
                            var spriteCompositeCtx = ctx
                            spriteCompositeCtx.blendMode = ls.blendMode.swiftUIBlendMode
                            spriteCompositeCtx.drawLayer { layerCtx in
                                layerCtx.opacity = lOpacity
                                if !lLayerXF.isIdentity { layerCtx.concatenate(lLayerXF) }
                                let styleMap  = Dictionary(uniqueKeysWithValues: controller.projectStyles.map { ($0.id, $0) })
                                let spriteRef = min(gridW, gridH) / 8.0
                                for (idx, sprite) in ls.sprites.enumerated() {
                                    let motionSet = sprite.motionID.flatMap { lMotionMap[$0] }
                                    let styleOverrideID = resolveEffectiveSpriteStyleID(sprite: sprite,
                                                                                         animatedGeometries: controller.projectAnimatedGeometries,
                                                                                         frame: currentFrame)
                                    let style     = (styleOverrideID ?? sprite.styleID).flatMap { styleMap[$0] }
                                    let motion    = computeMotion(motionSet: motionSet, style: style, path: nil,
                                                                  frame: currentFrame,
                                                                  phaseOffset: sprite.phaseOffset,
                                                                  cellIndex: idx,
                                                                  cellW: spriteRef * sprite.scaleX,
                                                                  cellH: spriteRef * sprite.scaleY)
                                    let driverPos = DriverEvaluator.evaluate(sprite.positionDriver, frame: currentFrame, spriteIndex: idx)
                                    let stateT = resolveEffectiveSpriteStateTransform(sprite: sprite,
                                                                                       animatedGeometries: controller.projectAnimatedGeometries,
                                                                                       frame: currentFrame)
                                    let mx  = sprite.x * gridW + motion.dx + driverPos.x + stateT.offsetX
                                    let my  = sprite.y * gridH + motion.dy + driverPos.y + stateT.offsetY
                                    let rot = sprite.rotation + motion.rotation + stateT.rotation
                                    let effectiveShapeID = resolveEffectiveSpriteShapeID(sprite: sprite, motionSet: motionSet,
                                                                                          animatedGeometries: controller.projectAnimatedGeometries,
                                                                                          frame: currentFrame)
                                    let polygons   = resolvePolygons(shapeID: effectiveShapeID,
                                                                     shapeMap: shapePolyMap,
                                                                     fallback: fallbackPolys)
                                    let polygonIDs = resolvePolygonIDs(shapeID: effectiveShapeID, idMap: shapePolyIDMap)
                                    let zoomX = (spriteRef / 2) * sprite.scaleX * motion.scaleX * stateT.scaleX
                                    let zoomY = (spriteRef / 2) * sprite.scaleY * motion.scaleY * stateT.scaleY
                                    let isSelected = sprite.id == controller.activeSpriteID

                                    if polygons.isEmpty {
                                        let rect = CGRect(x: mx - zoomX, y: my - zoomY, width: zoomX * 2, height: zoomY * 2)
                                        let fc   = style?.fillColor ?? .defaultFill
                                        layerCtx.fill(Path(roundedRect: rect, cornerRadius: 3),
                                                      with: .color(Color(red: fc.r, green: fc.g, blue: fc.b, opacity: fc.a)))
                                        if isSelected {
                                            layerCtx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                                                            with: .color(.accentColor), lineWidth: 1.5)
                                        }
                                    } else {
                                        let fillC   = style?.fillColor   ?? .defaultFill
                                        let strokeC = style?.strokeColor ?? .defaultStroke
                                        let strokeW = style?.strokeWidth ?? 1.5
                                        let mode    = style?.renderMode  ?? .filledStroked
                                        let paths   = polygons.filter(\.visible).enumerated().map { (_, polygon) -> CGPath in
                                            buildPolygonPath(polygon, cx: mx, cy: my,
                                                             zoomX: zoomX, zoomY: zoomY,
                                                             scaleX: 1.0, scaleY: 1.0,
                                                             rotation: rot)
                                        }
                                        for (i, cgp) in paths.enumerated() {
                                            let ovr   = sprite.polygonOverrides[polygonIDs[safe: i]?.uuidString ?? ""]
                                            let fC    = ovr?.fill   ?? fillC
                                            let sC    = ovr?.stroke ?? strokeC
                                            if mode == .filled || mode == .filledStroked {
                                                layerCtx.fill(Path(cgp),
                                                              with: .color(Color(red: fC.r, green: fC.g, blue: fC.b, opacity: fC.a)))
                                            }
                                            if mode == .stroked || mode == .filledStroked {
                                                layerCtx.stroke(Path(cgp),
                                                                with: .color(Color(red: sC.r, green: sC.g, blue: sC.b, opacity: sC.a)),
                                                                lineWidth: strokeW)
                                            }
                                        }
                                        if isSelected {
                                            for cgp in paths {
                                                layerCtx.stroke(Path(cgp),
                                                                with: .color(.accentColor.opacity(0.9)),
                                                                lineWidth: 2.5)
                                            }
                                        }
                                    }
                                }
                            } // drawLayer sprite
                            continue
                        }

                        // --- Grid layer (existing) ---
                        let isActiveLayer = ls.engine === controller.engine
                        let lConfig   = ls.engine.document.gridConfig
                        let lCellW    = gridW / Double(lConfig.cols)
                        let lCellH    = gridH / Double(lConfig.rows)
                        let lScaleX   = lCellW / lConfig.cellWidth
                        let lScaleY   = lCellH / lConfig.cellHeight
                        let lDistortion = ls.gridDistortion
                        let lStyleMap = Dictionary(uniqueKeysWithValues:
                            ls.engine.document.styles.map { ($0.id, $0) })
                        let lPathMap  = Dictionary(uniqueKeysWithValues:
                            ls.engine.document.paths.map { ($0.id, $0) })
                        let lColorGrid = controller.colorMapEngine(forLayerID: ls.id)?.currentGrid(
                            animationFrame: currentFrame,
                            loopMode: ls.engine.document.colorSource?.videoLoopMode ?? .loop)
                        let lColorSrc  = ls.engine.document.colorSource
                        let lOpacity   = DriverEvaluator.evaluate(ls.opacityDriver, frame: currentFrame)

                        let lMotionMap = Dictionary(uniqueKeysWithValues: controller.projectMotionSets.map { ($0.id, $0) })
                        let lLayerOff  = DriverEvaluator.evaluate(ls.layerOffset, frame: currentFrame)
                        let lLayerXF   = umLayerTransform(cameraFrame: cameraFrame,
                                                           parallaxFactor: ls.parallaxFactor,
                                                           layerOffset: lLayerOff,
                                                           canvasW: gridW, canvasH: gridH)
                        let lScroll    = DriverEvaluator.evaluate(ls.gridScrollDriver, frame: currentFrame)
                        let lFracX     = lScroll.x - floor(lScroll.x)
                        let lFracY     = lScroll.y - floor(lScroll.y)
                        let lSpecs     = gridScrollRenderSpecs(
                            cells: ls.engine.document.cells, scroll: lScroll,
                            mode: ls.gridScrollMode,
                            rows: lConfig.rows, cols: lConfig.cols)
                        var gridCompositeCtx = ctx
                        gridCompositeCtx.blendMode = ls.blendMode.swiftUIBlendMode
                        gridCompositeCtx.drawLayer { layerCtx in
                            layerCtx.opacity = lOpacity
                            if !lLayerXF.isIdentity { layerCtx.concatenate(lLayerXF) }
                            for spec in lSpecs {
                                let cell      = spec.cell
                                let r         = spec.displayRow
                                let c         = spec.displayCol
                                let style     = lStyleMap[cell.styleID]
                                let motionSet = cell.motionID.flatMap { lMotionMap[$0] }
                                let path      = cell.pathID.flatMap { lPathMap[$0] }
                                var motion    = computeMotion(motionSet: motionSet, style: style, path: path,
                                                              frame: currentFrame,
                                                              phaseOffset: cell.phaseOffset,
                                                              cellIndex: cell.gridIndex,
                                                              cellW: lCellW, cellH: lCellH)
                                if cell.lockedFillColor != nil || cell.lockedStrokeColor != nil {
                                    if let fc = cell.lockedFillColor   { motion.fillOverride   = fc }
                                    if let sc = cell.lockedStrokeColor { motion.strokeOverride = sc }
                                } else if let src = lColorSrc, let grid = lColorGrid,
                                          r < grid.count, c < grid[r].count {
                                    applyColorMap(grid[r][c], source: src, style: style, to: &motion)
                                }
                                let dCell = lDistortion.evaluate(row: r, col: c,
                                                                    rows: lConfig.rows, cols: lConfig.cols,
                                                                    uniformCellW: lCellW, uniformCellH: lCellH,
                                                                    gridW: gridW, gridH: gridH)
                                let dCellW = dCell.cellW, dCellH = dCell.cellH
                                let mx = dCell.cx - lFracX * lCellW + cell.positionOffset.dx * lScaleX + motion.dx
                                let my = dCell.cy - lFracY * lCellH + cell.positionOffset.dy * lScaleY + motion.dy
                                let isSelected = isActiveLayer && controller.selectedIndices.contains(cell.gridIndex)

                                let lEffectiveShapeID = resolveSequenceShapeID(motionSet: motionSet,
                                                                               cellShapeID: cell.shapeID,
                                                                               frame: currentFrame,
                                                                               phaseOffset: cell.phaseOffset)
                                let polygons = resolvePolygons(shapeID: lEffectiveShapeID,
                                                               shapeMap: shapePolyMap,
                                                               fallback: fallbackPolys)

                                if polygons.isEmpty {
                                    let rw   = (dCellW - 4) / 2 * motion.scaleX
                                    let rh   = (dCellH - 4) / 2 * motion.scaleY
                                    let rect = CGRect(x: mx - rw, y: my - rh, width: rw * 2, height: rh * 2)
                                    let fc   = motion.fillOverride ?? style?.fillColor ?? .defaultFill
                                    layerCtx.fill(Path(roundedRect: rect, cornerRadius: 3),
                                                  with: .color(Color(red: fc.r, green: fc.g, blue: fc.b)
                                                      .opacity(isSelected ? min(1, fc.a * 1.3) : fc.a)))
                                    if isSelected {
                                        layerCtx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                                                        with: .color(.accentColor), lineWidth: 1.5)
                                    }
                                } else {
                                    let dCellHalf = min(dCellW, dCellH)
                                    let zoomX   = (stretch ? dCellW : dCellHalf) * motion.scaleX
                                    let zoomY   = (stretch ? dCellH : dCellHalf) * motion.scaleY
                                    let fillC   = motion.fillOverride   ?? style?.fillColor   ?? .defaultFill
                                    let strokeC = motion.strokeOverride ?? style?.strokeColor ?? .defaultStroke
                                    let strokeW = style?.strokeWidth ?? 1.5
                                    let mode    = style?.renderMode  ?? .filledStroked

                                    let paths = polygons.filter(\.visible)
                                                        .map { buildPolygonPath($0, cx: mx, cy: my,
                                                                                zoomX: zoomX, zoomY: zoomY,
                                                                                scaleX: cell.scaleX,
                                                                                scaleY: cell.scaleY,
                                                                                rotation: cell.rotation + motion.rotation) }
                                    for cgp in paths {
                                        if mode == .filled || mode == .filledStroked {
                                            layerCtx.fill(Path(cgp),
                                                          with: .color(Color(red: fillC.r, green: fillC.g,
                                                                             blue: fillC.b, opacity: fillC.a)))
                                        }
                                        if mode == .stroked || mode == .filledStroked {
                                            layerCtx.stroke(Path(cgp),
                                                            with: .color(Color(red: strokeC.r, green: strokeC.g,
                                                                               blue: strokeC.b, opacity: strokeC.a)),
                                                            lineWidth: strokeW)
                                        }
                                    }
                                    if isSelected {
                                        for cgp in paths {
                                            layerCtx.stroke(Path(cgp),
                                                            with: .color(.accentColor.opacity(0.9)),
                                                            lineWidth: 2.5)
                                        }
                                    }
                                }
                            }
                        } // ctx.drawLayer
                    } // for ls in layerStates

                    // Hover preview: ghost sprite on undrawn cells in Draw/Fill mode (grid layers only)
                    if controller.canvasIsHovered,
                       controller.activeTool == .draw || controller.activeTool == .fill,
                       controller.layerStates[controller.activeLayerIndex].layerMode == .grid,
                       let vp = hoverViewPoint {
                        let cp  = canvasPoint(vp, viewSize: size, gridW: gridW, gridH: gridH)
                        let col = Int(cp.x / cellW)
                        let row = Int(cp.y / cellH)
                        if col >= 0, col < config.cols, row >= 0, row < config.rows {
                            let idx = row * config.cols + col
                            if !controller.engine.document.cells[idx].isDrawn {
                                let mx       = Double(col) * cellW + cellW / 2
                                let my       = Double(row) * cellH + cellH / 2
                                let style    = controller.projectStyles.first { $0.id == controller.activeStyleID }
                                let polygons = resolvePolygons(shapeID: controller.activeShapeID,
                                                               shapeMap: shapePolyMap,
                                                               fallback: fallbackPolys)
                                let halfCell = min(cellW, cellH) / 2
                                if polygons.isEmpty {
                                    let rw   = (cellW - 4) / 2
                                    let rh   = (cellH - 4) / 2
                                    let rect = CGRect(x: mx - rw, y: my - rh, width: rw * 2, height: rh * 2)
                                    let fc   = style?.fillColor ?? .defaultFill
                                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                                             with: .color(Color(red: fc.r, green: fc.g, blue: fc.b).opacity(fc.a * 0.4)))
                                } else {
                                    let zoomX   = (stretch ? cellW : halfCell)
                                    let zoomY   = (stretch ? cellH : halfCell)
                                    let fillC   = style?.fillColor   ?? .defaultFill
                                    let strokeC = style?.strokeColor ?? .defaultStroke
                                    let strokeW = style?.strokeWidth ?? 1.5
                                    let mode    = style?.renderMode  ?? .filledStroked
                                    let paths   = polygons.filter(\.visible)
                                                          .map { buildPolygonPath($0, cx: mx, cy: my,
                                                                                  zoomX: zoomX, zoomY: zoomY,
                                                                                  scaleX: 1.0, scaleY: 1.0,
                                                                                  rotation: 0) }
                                    for cgp in paths {
                                        if mode == .filled || mode == .filledStroked {
                                            ctx.fill(Path(cgp),
                                                     with: .color(Color(red: fillC.r, green: fillC.g,
                                                                        blue: fillC.b, opacity: fillC.a * 0.4)))
                                        }
                                        if mode == .stroked || mode == .filledStroked {
                                            ctx.stroke(Path(cgp),
                                                       with: .color(Color(red: strokeC.r, green: strokeC.g,
                                                                          blue: strokeC.b, opacity: strokeC.a * 0.4)),
                                                       lineWidth: strokeW)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Path overlay: trajectory + keyframe dots + animated playhead
                    // Uses active layer's paths (controller.engine is always the active layer).
                    let pathMap = Dictionary(uniqueKeysWithValues:
                        controller.engine.document.paths.map { ($0.id, $0) })
                    if controller.showPathOverlay,
                       let activePID = controller.activePathID,
                       let activePath = pathMap[activePID],
                       activePath.duration > 0 {

                        // Collect cells that carry this path (cap at 30 for performance)
                        let pathCells = controller.engine.document.cells
                            .filter { $0.isDrawn && $0.pathID == activePID }
                            .prefix(30)

                        // Pre-compute relative trajectory points (cell-fraction → canvas pixels)
                        let dur      = activePath.duration
                        let step     = max(1, dur / 120)
                        var relPts   = [CGPoint]()
                        var t        = 0
                        while t <= dur {
                            let (dx, dy, _, _, _) = activePath.evaluate(atFrame: t, cellW: cellW, cellH: cellH)
                            relPts.append(CGPoint(x: dx, y: dy))
                            t += step
                        }

                        // Keyframe positions (direct from model — avoids evaluate at exact boundary)
                        let kfRelPts: [CGPoint] = activePath.keyframes.map { kf in
                            CGPoint(x: kf.dx * cellW, y: kf.dy * cellH)
                        }

                        let selectedKFID = controller.selectedPathKeyframeID

                        for cell in pathCells {
                            let row = cell.gridIndex / config.cols
                            let col = cell.gridIndex % config.cols
                            let cx  = Double(col) * cellW + cellW / 2 + cell.positionOffset.dx * scaleX
                            let cy  = Double(row) * cellH + cellH / 2 + cell.positionOffset.dy * scaleY

                            // Trajectory
                            if relPts.count >= 2 {
                                var traj = Path()
                                traj.move(to: CGPoint(x: cx + relPts[0].x, y: cy + relPts[0].y))
                                for pt in relPts.dropFirst() {
                                    traj.addLine(to: CGPoint(x: cx + pt.x, y: cy + pt.y))
                                }
                                if activePath.loops {
                                    traj.addLine(to: CGPoint(x: cx + relPts[0].x, y: cy + relPts[0].y))
                                }
                                ctx.stroke(traj,
                                           with: .color(Color.accentColor.opacity(0.35)),
                                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            }

                            // Keyframe dots + tangent handles
                            for (ki, kf) in activePath.keyframes.enumerated() {
                                let kfPt = CGPoint(x: cx + kfRelPts[ki].x, y: cy + kfRelPts[ki].y)
                                let isSelected = kf.id == selectedKFID

                                // Tangent arms for the selected keyframe
                                if isSelected {
                                    let outPt = CGPoint(x: kfPt.x + kf.outTangentX * cellW,
                                                        y: kfPt.y + kf.outTangentY * cellH)
                                    let inPt  = CGPoint(x: kfPt.x + kf.inTangentX  * cellW,
                                                        y: kfPt.y + kf.inTangentY  * cellH)
                                    // Arm lines
                                    ctx.stroke(Path { $0.move(to: kfPt); $0.addLine(to: outPt) },
                                               with: .color(Color.white.opacity(0.7)),
                                               style: StrokeStyle(lineWidth: 1))
                                    ctx.stroke(Path { $0.move(to: kfPt); $0.addLine(to: inPt) },
                                               with: .color(Color.white.opacity(0.5)),
                                               style: StrokeStyle(lineWidth: 1))
                                    // Out handle (white fill, accent stroke)
                                    ctx.fill(Path(ellipseIn: CGRect(x: outPt.x-4, y: outPt.y-4, width: 8, height: 8)),
                                             with: .color(Color.white))
                                    ctx.stroke(Path(ellipseIn: CGRect(x: outPt.x-4, y: outPt.y-4, width: 8, height: 8)),
                                               with: .color(Color.accentColor), lineWidth: 1.5)
                                    // In handle (white fill, secondary stroke)
                                    ctx.fill(Path(ellipseIn: CGRect(x: inPt.x-4, y: inPt.y-4, width: 8, height: 8)),
                                             with: .color(Color.white))
                                    ctx.stroke(Path(ellipseIn: CGRect(x: inPt.x-4, y: inPt.y-4, width: 8, height: 8)),
                                               with: .color(Color.secondary), lineWidth: 1.5)
                                }

                                // Keyframe dot
                                let dotR: CGFloat = isSelected ? 4.5 : 3
                                ctx.fill(Path(ellipseIn: CGRect(x: kfPt.x-dotR, y: kfPt.y-dotR,
                                                                 width: dotR*2, height: dotR*2)),
                                         with: .color(isSelected ? Color.white : Color.accentColor.opacity(0.85)))
                                if isSelected {
                                    ctx.stroke(Path(ellipseIn: CGRect(x: kfPt.x-dotR, y: kfPt.y-dotR,
                                                                       width: dotR*2, height: dotR*2)),
                                               with: .color(Color.accentColor), lineWidth: 1.5)
                                }
                            }

                            // Animated playhead
                            let (pdx, pdy, _, _, _) = activePath.evaluate(
                                atFrame: currentFrame + cell.phaseOffset,
                                cellW: cellW, cellH: cellH)
                            let pp = CGPoint(x: cx + pdx, y: cy + pdy)
                            ctx.fill(Path(ellipseIn: CGRect(x: pp.x-4.5, y: pp.y-4.5, width: 9, height: 9)),
                                     with: .color(Color.white))
                            ctx.fill(Path(ellipseIn: CGRect(x: pp.x-3, y: pp.y-3, width: 6, height: 6)),
                                     with: .color(Color.accentColor))
                        }
                    }

                    // Rubber-band selection (in canvas space, drawn on top)
                    if controller.activeTool == .select,
                       let rbStart = rubberBandStart, let rbEnd = rubberBandCurrent {
                        let rbRect = CGRect(
                            x: min(rbStart.x, rbEnd.x),
                            y: min(rbStart.y, rbEnd.y),
                            width:  max(1, abs(rbEnd.x - rbStart.x)),
                            height: max(1, abs(rbEnd.y - rbStart.y))
                        )
                        ctx.fill(Path(rbRect), with: .color(Color.accentColor.opacity(0.07)))
                        ctx.stroke(Path(rbRect),
                                   with: .color(Color.accentColor.opacity(0.75)),
                                   style: StrokeStyle(lineWidth: 1 / zoom,
                                                      dash: [4 / zoom, 3 / zoom]))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            cachedCellW = cellW
                            cachedCellH = cellH
                            cachedGridW = gridW
                            cachedGridH = gridH
                            let pt = canvasPoint(value.location,
                                                 viewSize: geo.size,
                                                 gridW: gridW, gridH: gridH)

                            // Bezier tangent handle intercept (path overlay active + KF selected)
                            if let drag = tangentDragState {
                                applyTangentDrag(drag, pt: pt, cellW: cellW, cellH: cellH)
                                return
                            }
                            if controller.showPathOverlay,
                               let kfID = controller.selectedPathKeyframeID {
                                let startPt = canvasPoint(value.startLocation,
                                                          viewSize: geo.size,
                                                          gridW: gridW, gridH: gridH)
                                if let hit = hitTestTangentHandles(at: startPt, kfID: kfID,
                                                                   cellW: cellW, cellH: cellH,
                                                                   scaleX: scaleX, scaleY: scaleY) {
                                    tangentDragState = hit
                                    applyTangentDrag(hit, pt: pt, cellW: cellW, cellH: cellH)
                                    return
                                }
                            }

                            // Sprite layer intercept
                            let activeLS = controller.layerStates[controller.activeLayerIndex]
                            if activeLS.layerMode == .sprite {
                                let frame = controller.engine.currentFrame
                                let startPt = canvasPoint(value.startLocation,
                                                          viewSize: geo.size,
                                                          gridW: gridW, gridH: gridH)
                                if spriteDragID == nil && rubberBandStart == nil {
                                    if let hit = spriteHitTest(at: startPt, in: activeLS,
                                                               gridW: gridW, gridH: gridH, frame: frame) {
                                        if controller.activeTool == .select {
                                            controller.selectSpriteFromCanvas(hit.id)
                                        } else {
                                            controller.activeSpriteID = hit.id
                                        }
                                        spriteDragID = hit.id
                                        spriteDragIsKeyframe = hit.positionDriver.mode == .keyframe
                                        // offset = rendered display position - click position
                                        let si = activeLS.sprites.firstIndex(where: { $0.id == hit.id }) ?? 0
                                        let dOff = DriverEvaluator.evaluate(hit.positionDriver, frame: frame, spriteIndex: si)
                                        let motion = spriteMotion(for: hit, index: si, frame: frame,
                                                                  gridW: gridW, gridH: gridH)
                                        spriteDragOffset = CGPoint(x: hit.x * gridW + motion.dx + dOff.x - startPt.x,
                                                                   y: hit.y * gridH + motion.dy + dOff.y - startPt.y)
                                    } else if controller.activeTool == .select {
                                        rubberBandStart = startPt
                                    }
                                }
                                if let dragID = spriteDragID {
                                    let targetX = pt.x + spriteDragOffset.x
                                    let targetY = pt.y + spriteDragOffset.y
                                    if spriteDragIsKeyframe {
                                        let si = activeLS.sprites.firstIndex(where: { $0.id == dragID }) ?? 0
                                        let sprite = activeLS.sprites[safe: si]
                                        let targetFrame = controller.engine.currentFrame
                                        let motion = sprite.map {
                                            spriteMotion(for: $0, index: si, frame: targetFrame,
                                                         gridW: gridW, gridH: gridH)
                                        } ?? SpriteMotion()
                                        controller.setSpritePositionKeyframe(
                                            id: dragID,
                                            frame: targetFrame,
                                            canvasX: targetX, canvasY: targetY,
                                            gridW: gridW, gridH: gridH,
                                            motionDX: motion.dx, motionDY: motion.dy)
                                    } else {
                                        controller.moveSprite(id: dragID,
                                                             to: CGPoint(x: targetX / gridW, y: targetY / gridH))
                                    }
                                } else if controller.activeTool == .select {
                                    rubberBandCurrent = pt
                                }
                                return
                            }
                            switch controller.activeTool {
                            case .select:
                                if rubberBandStart == nil {
                                    rubberBandStart = canvasPoint(value.startLocation,
                                                                  viewSize: geo.size,
                                                                  gridW: gridW, gridH: gridH)
                                }
                                rubberBandCurrent = pt
                            case .nudge:
                                handleNudge(at: pt,
                                            cellW: cellW, cellH: cellH,
                                            scaleX: scaleX, scaleY: scaleY,
                                            config: config)
                            default:
                                handleDrag(at: pt,
                                           cellW: cellW, cellH: cellH,
                                           config: config)
                            }
                        }
                        .onEnded { value in
                            // Tangent drag end
                            if tangentDragState != nil {
                                tangentDragState = nil
                                lastDragIndex    = nil
                                lastNudgeLocation = nil
                                return
                            }

                            // KF dot tap → select / deselect keyframe
                            let dist = hypot(value.translation.width, value.translation.height)
                            if dist < 6, controller.showPathOverlay,
                               let activePID = controller.activePathID,
                               let activePath = controller.engine.document.paths.first(where: { $0.id == activePID }) {
                                let tapPt = canvasPoint(value.startLocation,
                                                        viewSize: geo.size,
                                                        gridW: cachedGridW, gridH: cachedGridH)
                                let config2 = controller.engine.document.gridConfig
                                let cW = cachedGridW / Double(config2.cols)
                                let cH = cachedGridH / Double(config2.rows)
                                let pathCells2 = controller.engine.document.cells
                                    .filter { $0.isDrawn && $0.pathID == activePID }.prefix(30)
                                let sX2 = cW / config2.cellWidth; let sY2 = cH / config2.cellHeight
                                outer: for cell2 in pathCells2 {
                                    let r2 = cell2.gridIndex / config2.cols
                                    let c2 = cell2.gridIndex % config2.cols
                                    let cx2 = Double(c2) * cW + cW / 2 + cell2.positionOffset.dx * sX2
                                    let cy2 = Double(r2) * cH + cH / 2 + cell2.positionOffset.dy * sY2
                                    for kf in activePath.keyframes {
                                        let kfX = cx2 + kf.dx * cW
                                        let kfY = cy2 + kf.dy * cH
                                        if hypot(tapPt.x - kfX, tapPt.y - kfY) <= 8 {
                                            controller.selectedPathKeyframeID =
                                                (controller.selectedPathKeyframeID == kf.id) ? nil : kf.id
                                            break outer
                                        }
                                    }
                                }
                            }

                            let activeLS = controller.layerStates[controller.activeLayerIndex]
                            if activeLS.layerMode == .sprite {
                                if spriteDragID != nil {
                                    spriteDragID         = nil
                                    spriteDragOffset     = .zero
                                    spriteDragIsKeyframe = false
                                } else if controller.activeTool == .select {
                                    handleSpriteSelectEnd(value: value, in: activeLS)
                                    rubberBandStart = nil
                                    rubberBandCurrent = nil
                                } else {
                                    let dist = hypot(value.translation.width, value.translation.height)
                                    if dist < 8 {
                                        let startPt = canvasPoint(value.startLocation,
                                                                  viewSize: geo.size,
                                                                  gridW: cachedGridW, gridH: cachedGridH)
                                        let frame = controller.engine.currentFrame
                                        if controller.activeTool != .select,
                                           spriteHitTest(at: startPt, in: activeLS,
                                                         gridW: cachedGridW, gridH: cachedGridH,
                                                         frame: frame) == nil {
                                            let tap = canvasPoint(value.location,
                                                                  viewSize: geo.size,
                                                                  gridW: cachedGridW, gridH: cachedGridH)
                                            controller.addSprite(at: CGPoint(
                                                x: tap.x / cachedGridW,
                                                y: tap.y / cachedGridH))
                                        }
                                    }
                                }
                                lastDragIndex     = nil
                                lastNudgeLocation = nil
                                return
                            }
                            if controller.activeTool == .select {
                                let pt = canvasPoint(value.location,
                                                     viewSize: geo.size,
                                                     gridW: gridW, gridH: gridH)
                                handleSelectEnd(value: value, clickPt: pt, config: config)
                                rubberBandStart   = nil
                                rubberBandCurrent = nil
                            }
                            lastDragIndex     = nil
                            lastNudgeLocation = nil
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            controller.canvasZoom = max(0.1, min(10.0, baseZoom * value))
                        }
                        .onEnded { _ in
                            baseZoom = controller.canvasZoom
                        }
                )
                .onHover { controller.canvasIsHovered = $0 }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let pt): hoverViewPoint = pt
                    case .ended:          hoverViewPoint = nil
                    }
                }
                .onChange(of: controller.engine.currentFrame) {
                    guard !controller.backgroundDraw else { return }
                    let pw = Int((gridW * displayScale).rounded())
                    let ph = Int((gridH * displayScale).rounded())
                    guard pw > 0, ph > 0 else { return }
                    // Snapshot all value-type data synchronously on main thread (fast),
                    // then render the accumulation buffer on a background thread so the
                    // main actor stays free for user interactions (pickers, dropdowns).
                    let currentFrame = controller.engine.currentFrame
                    let snapshot = AccumulationSnapshot(
                        layers: controller.layerStates.filter(\.isVisible).map { ls in
                            let lConfig = ls.engine.document.gridConfig
                            let lCellW  = gridW / Double(lConfig.cols)
                            let lCellH  = gridH / Double(lConfig.rows)
                            return LayerAccumulationData(
                                cells:       ls.engine.document.cells,
                                styles:      ls.engine.document.styles,
                                paths:       ls.engine.document.paths,
                                config:      lConfig,
                                opacity:     ls.opacity,
                                colorSource: ls.engine.document.colorSource,
                                colorGrid:   controller.colorMapEngine(forLayerID: ls.id)?.currentGrid(
                                    animationFrame: currentFrame,
                                    loopMode: ls.engine.document.colorSource?.videoLoopMode ?? .loop),
                                cellW: lCellW, cellH: lCellH,
                                scaleX: lCellW / lConfig.cellWidth,
                                scaleY: lCellH / lConfig.cellHeight,
                                gridScrollDriver: ls.gridScrollDriver,
                                gridScrollMode:   ls.gridScrollMode,
                                layerMode: ls.layerMode,
                                sprites:   ls.sprites,
                                gridW:     gridW,
                                gridH:     gridH,
                                blendMode: ls.blendMode
                            )
                        },
                        previousBuffer:    controller.frameBuffer,
                        backgroundColor:   controller.backgroundColor,
                        backgroundImage:   controller.backgroundCGImage,
                        shapePolygonMap:   controller.shapePolygonMap,
                        shapePolygonIDMap: controller.shapePolygonIDMap,
                        fallbackPolygons:  controller.shapePolygons,
                        projectMotionSets: controller.projectMotionSets,
                        projectAnimatedGeometries: controller.projectAnimatedGeometries,
                        stretchSprites:    controller.stretchSpritesToCell,
                        frame:           currentFrame,
                        pw: pw, ph: ph,
                        displayScale: displayScale
                    )
                    captureTask?.cancel()
                    captureTask = Task.detached(priority: .utility) { [controller] in
                        guard !Task.isCancelled else { return }
                        guard let image = renderAccumulationCG(snapshot) else { return }
                        await MainActor.run { controller.updateFrameBuffer(image) }
                    }
                }

                // Keyboard shortcuts — hidden buttons so they receive key events when canvas is active
                Group {
                    Button("") {
                        controller.canvasZoom = 1.0
                        controller.canvasPan  = .zero
                        baseZoom = 1.0
                    }
                    .keyboardShortcut("0", modifiers: .command)
                    Button("") {
                        controller.canvasZoom = min(10.0, controller.canvasZoom * 1.25)
                        baseZoom = controller.canvasZoom
                    }
                    .keyboardShortcut("=", modifiers: .command)
                    Button("") {
                        controller.canvasZoom = max(0.1, controller.canvasZoom / 1.25)
                        baseZoom = controller.canvasZoom
                    }
                    .keyboardShortcut("-", modifiers: .command)
                    // Delete selected sprite
                    Button("") {
                        if let id = controller.activeSpriteID {
                            controller.removeSprite(id: id)
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                }
                .hidden()
            }
            .onAppear {
                let c = controller
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard c.canvasIsHovered else { return event }
                    if event.modifierFlags.contains(.option) {
                        let delta = event.scrollingDeltaY
                        let factor = exp(-delta * 0.02)
                        c.canvasZoom = max(0.1, min(10.0, c.canvasZoom * factor))
                        return nil
                    } else if !event.modifierFlags.contains(.command) {
                        c.canvasPan.width  += event.scrollingDeltaX
                        c.canvasPan.height += event.scrollingDeltaY
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
            }
        }
    }


    // MARK: - Tangent handle helpers

    private func hitTestTangentHandles(at pt: CGPoint, kfID: UUID,
                                       cellW: Double, cellH: Double,
                                       scaleX: Double, scaleY: Double) -> TangentDragState? {
        guard let activePID = controller.activePathID,
              let activePath = controller.engine.document.paths.first(where: { $0.id == activePID }),
              let kf = activePath.keyframes.first(where: { $0.id == kfID })
        else { return nil }

        let config   = controller.engine.document.gridConfig
        let pathCells = controller.engine.document.cells
            .filter { $0.isDrawn && $0.pathID == activePID }.prefix(30)
        let hitR: Double = 8

        for cell in pathCells {
            let row = cell.gridIndex / config.cols
            let col = cell.gridIndex % config.cols
            let cx  = Double(col) * cellW + cellW / 2 + cell.positionOffset.dx * scaleX
            let cy  = Double(row) * cellH + cellH / 2 + cell.positionOffset.dy * scaleY
            let kfX = cx + kf.dx * cellW
            let kfY = cy + kf.dy * cellH

            let outX = kfX + kf.outTangentX * cellW
            let outY = kfY + kf.outTangentY * cellH
            if hypot(pt.x - outX, pt.y - outY) <= hitR {
                return TangentDragState(kfID: kfID, which: .out,
                                        startTangentX: kf.outTangentX, startTangentY: kf.outTangentY,
                                        startCanvasPt: pt)
            }
            let inX = kfX + kf.inTangentX * cellW
            let inY = kfY + kf.inTangentY * cellH
            if hypot(pt.x - inX, pt.y - inY) <= hitR {
                return TangentDragState(kfID: kfID, which: .in,
                                        startTangentX: kf.inTangentX, startTangentY: kf.inTangentY,
                                        startCanvasPt: pt)
            }
        }
        return nil
    }

    private func spriteBounds(for sprite: UMSprite, index: Int, frame: Int,
                              gridW: Double, gridH: Double) -> CGRect {
        let ref = min(gridW, gridH) / 8.0
        let motion = spriteMotion(for: sprite, index: index, frame: frame, gridW: gridW, gridH: gridH)
        let dOff = DriverEvaluator.evaluate(sprite.positionDriver, frame: frame, spriteIndex: index)
        let stateT = resolveEffectiveSpriteStateTransform(sprite: sprite,
                                                          animatedGeometries: controller.projectAnimatedGeometries,
                                                          frame: frame)
        let sx = sprite.x * gridW + motion.dx + dOff.x + stateT.offsetX
        let sy = sprite.y * gridH + motion.dy + dOff.y + stateT.offsetY
        let zoom = controller.canvasZoom
        let minHit = 10.0 / zoom  // minimum hit radius in canvas px, stays ≥10 view px at any zoom
        let hw = max(minHit, (ref / 2) * sprite.scaleX * abs(motion.scaleX) * stateT.scaleX)
        let hh = max(minHit, (ref / 2) * sprite.scaleY * abs(motion.scaleY) * stateT.scaleY)
        let fallback = CGRect(x: sx - hw, y: sy - hh, width: hw * 2, height: hh * 2)
        let style = sprite.styleID.flatMap { id in controller.projectStyles.first { $0.id == id } }
        let motionSet = sprite.motionID.flatMap { id in controller.projectMotionSets.first { $0.id == id } }
        let effectiveShapeID = resolveEffectiveSpriteShapeID(sprite: sprite, motionSet: motionSet,
                                                              animatedGeometries: controller.projectAnimatedGeometries,
                                                              frame: frame)
        let polygons = resolvePolygons(shapeID: effectiveShapeID,
                                       shapeMap: controller.shapePolygonMap,
                                       fallback: controller.shapePolygons)
        guard !polygons.isEmpty else { return fallback }
        let zoomX = (ref / 2) * sprite.scaleX * motion.scaleX * stateT.scaleX
        let zoomY = (ref / 2) * sprite.scaleY * motion.scaleY * stateT.scaleY
        let rot = sprite.rotation + motion.rotation + stateT.rotation
        let bounds = polygons.filter(\.visible).reduce(CGRect.null) { partial, polygon in
            partial.union(Path(buildPolygonPath(polygon, cx: sx, cy: sy,
                                                zoomX: zoomX, zoomY: zoomY,
                                                scaleX: 1.0, scaleY: 1.0,
                                                rotation: rot)).boundingRect)
        }
        let strokeW = CGFloat(style?.strokeWidth ?? 1.5)
        let pad = max(minHit, Double(strokeW))
        return bounds.isNull ? fallback : bounds.insetBy(dx: -pad, dy: -pad)
    }

    private func spriteCenter(for sprite: UMSprite, index: Int, frame: Int,
                              gridW: Double, gridH: Double) -> CGPoint {
        let motion = spriteMotion(for: sprite, index: index, frame: frame, gridW: gridW, gridH: gridH)
        let dOff = DriverEvaluator.evaluate(sprite.positionDriver, frame: frame, spriteIndex: index)
        return CGPoint(x: sprite.x * gridW + motion.dx + dOff.x,
                       y: sprite.y * gridH + motion.dy + dOff.y)
    }

    private func applyTangentDrag(_ drag: TangentDragState, pt: CGPoint,
                                  cellW: Double, cellH: Double) {
        guard let activePID = controller.activePathID,
              let pi = controller.engine.document.paths.firstIndex(where: { $0.id == activePID }),
              let ki = controller.engine.document.paths[pi].keyframes.firstIndex(where: { $0.id == drag.kfID })
        else { return }

        let dxCell = (pt.x - drag.startCanvasPt.x) / cellW
        let dyCell = (pt.y - drag.startCanvasPt.y) / cellH
        let newX = drag.startTangentX + dxCell
        let newY = drag.startTangentY + dyCell
        let smooth = controller.engine.document.paths[pi].keyframes[ki].smooth

        switch drag.which {
        case .out:
            controller.engine.document.paths[pi].keyframes[ki].outTangentX = newX
            controller.engine.document.paths[pi].keyframes[ki].outTangentY = newY
            if smooth {
                controller.engine.document.paths[pi].keyframes[ki].inTangentX = -newX
                controller.engine.document.paths[pi].keyframes[ki].inTangentY = -newY
            }
        case .in:
            controller.engine.document.paths[pi].keyframes[ki].inTangentX = newX
            controller.engine.document.paths[pi].keyframes[ki].inTangentY = newY
            if smooth {
                controller.engine.document.paths[pi].keyframes[ki].outTangentX = -newX
                controller.engine.document.paths[pi].keyframes[ki].outTangentY = -newY
            }
        }
    }

    private func canvasPoint(_ viewPt: CGPoint, viewSize: CGSize,
                             gridW: Double, gridH: Double) -> CGPoint {
        let zoom = controller.canvasZoom
        let pan  = controller.canvasPan
        let tx   = (viewSize.width  - gridW * zoom) / 2 + pan.width
        let ty   = (viewSize.height - gridH * zoom) / 2 + pan.height
        return CGPoint(x: (viewPt.x - tx) / zoom, y: (viewPt.y - ty) / zoom)
    }

    private func spriteHitTest(at pt: CGPoint, in ls: UMLayerState,
                               gridW: Double, gridH: Double, frame: Int = 0) -> UMSprite? {
        if let activeID = controller.activeSpriteID,
           let idx = ls.sprites.firstIndex(where: { $0.id == activeID }) {
            let sprite = ls.sprites[idx]
            if spriteBounds(for: sprite, index: idx, frame: frame,
                            gridW: gridW, gridH: gridH).contains(pt) {
                return sprite
            }
        }
        for idx in ls.sprites.indices.reversed() {
            let sprite = ls.sprites[idx]
            if spriteBounds(for: sprite, index: idx, frame: frame,
                            gridW: gridW, gridH: gridH).contains(pt) {
                return sprite
            }
        }
        return nil
    }

    private func spriteMotion(for sprite: UMSprite, index: Int, frame: Int,
                              gridW: Double, gridH: Double) -> SpriteMotion {
        let style     = sprite.styleID.flatMap { id in controller.projectStyles.first { $0.id == id } }
        let motionSet = sprite.motionID.flatMap { id in controller.projectMotionSets.first { $0.id == id } }
        let spriteRef = min(gridW, gridH) / 8.0
        return computeMotion(motionSet: motionSet, style: style, path: nil,
                             frame: frame,
                             phaseOffset: sprite.phaseOffset,
                             cellIndex: index,
                             cellW: spriteRef * sprite.scaleX,
                             cellH: spriteRef * sprite.scaleY)
    }

    private func handleSpriteSelectEnd(value: DragGesture.Value, in ls: UMLayerState) {
        let shift = NSEvent.modifierFlags.contains(.shift)
        let t = value.translation
        let isClick = t.width.magnitude < 4 && t.height.magnitude < 4
        let frame = controller.engine.currentFrame

        if isClick {
            guard let pt = rubberBandStart else { return }
            if let hit = spriteHitTest(at: pt, in: ls, gridW: cachedGridW, gridH: cachedGridH, frame: frame) {
                controller.selectSpriteFromCanvas(hit.id)
            } else if !shift {
                controller.selectSpriteFromCanvas(nil)
            }
            return
        }

        guard let start = rubberBandStart, let end = rubberBandCurrent else { return }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        for idx in ls.sprites.indices.reversed() {
            let sprite = ls.sprites[idx]
            if rect.contains(spriteCenter(for: sprite, index: idx, frame: frame,
                                          gridW: cachedGridW, gridH: cachedGridH)) {
                controller.selectSpriteFromCanvas(sprite.id)
                return
            }
        }
        var best: (id: UUID, area: CGFloat)?
        for idx in ls.sprites.indices {
            let sprite = ls.sprites[idx]
            let intersection = rect.intersection(spriteBounds(for: sprite, index: idx, frame: frame,
                                                              gridW: cachedGridW, gridH: cachedGridH))
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            let area = intersection.width * intersection.height
            if best == nil || area > best!.area {
                best = (sprite.id, area)
            }
        }
        if let best {
            controller.selectSpriteFromCanvas(best.id)
            return
        }
        if !shift {
            controller.selectSpriteFromCanvas(nil)
        }
    }

    private func handleDrag(at pt: CGPoint,
                            cellW: Double, cellH: Double,
                            config: UMGridConfig) {
        let col = Int(pt.x / cellW)
        let row = Int(pt.y / cellH)
        guard col >= 0, col < config.cols, row >= 0, row < config.rows else { return }
        let index = row * config.cols + col
        guard index != lastDragIndex else { return }

        if lastDragIndex == nil { controller.engine.pushUndoSnapshot() }
        lastDragIndex = index

        switch controller.activeTool {
        case .draw:
            let sid = controller.activeStyleID ?? controller.projectStyles.first?.id ?? UUID()
            controller.engine.setCellDrawn(index, drawn: true, styleID: sid,
                                           motionID: controller.activeMotionID,
                                           shapeID:  controller.activeShapeID,
                                           pathID:   controller.activePathID)
        case .erase:
            controller.engine.setCellDrawn(index, drawn: false, styleID: UUID())
        case .sample:
            if let style = controller.engine.sampleStyle(at: index) {
                controller.activeStyleID = style.id
            }
        case .fill:
            let sid = controller.activeStyleID ?? controller.projectStyles.first?.id ?? UUID()
            controller.engine.floodFill(from: index, styleID: sid,
                                        motionID: controller.activeMotionID,
                                        shapeID:  controller.activeShapeID,
                                        pathID:   controller.activePathID)
        case .select, .nudge:
            break  // handled separately
        }
    }

    private func handleSelectEnd(value: DragGesture.Value,
                                  clickPt: CGPoint,
                                  config: UMGridConfig) {
        let shift = NSEvent.modifierFlags.contains(.shift)
        let t = value.translation
        let isClick = t.width.magnitude < 4 && t.height.magnitude < 4

        if isClick {
            let col = Int(clickPt.x / cachedCellW)
            let row = Int(clickPt.y / cachedCellH)
            guard col >= 0, col < config.cols, row >= 0, row < config.rows else {
                if !shift { controller.selectedIndices = [] }
                return
            }
            let index = row * config.cols + col
            if shift {
                if controller.selectedIndices.contains(index) {
                    controller.selectedIndices.remove(index)
                } else {
                    controller.selectedIndices.insert(index)
                }
            } else {
                controller.selectedIndices = controller.selectedIndices == [index] ? [] : [index]
            }
        } else {
            guard let start = rubberBandStart, let end = rubberBandCurrent else { return }
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y))
            let indices = Set(controller.engine.document.cells.compactMap { cell -> Int? in
                guard cell.isDrawn else { return nil }
                let r = cell.gridIndex / config.cols
                let c = cell.gridIndex % config.cols
                let cx = Double(c) * cachedCellW + cachedCellW / 2
                let cy = Double(r) * cachedCellH + cachedCellH / 2
                return rect.contains(CGPoint(x: cx, y: cy)) ? cell.gridIndex : nil
            })
            if shift {
                controller.selectedIndices.formUnion(indices)
            } else {
                controller.selectedIndices = indices
            }
        }
    }

    private func handleNudge(at pt: CGPoint,
                             cellW: Double, cellH: Double,
                             scaleX: Double, scaleY: Double,
                             config: UMGridConfig) {
        guard let last = lastNudgeLocation else {
            controller.engine.pushUndoSnapshot()
            if controller.selectedIndices.isEmpty {
                let col = Int(pt.x / cellW)
                let row = Int(pt.y / cellH)
                if col >= 0, col < config.cols, row >= 0, row < config.rows {
                    let index = row * config.cols + col
                    if index < controller.engine.document.cells.count,
                       controller.engine.document.cells[index].isDrawn {
                        controller.selectedIndices = [index]
                    }
                }
            }
            lastNudgeLocation = pt
            return
        }

        // Convert screen-pixel delta to reference-pixel space before storing,
        // so the offset magnitude is independent of the current canvas size and resolution.
        let dx = (pt.x - last.x) / scaleX
        let dy = (pt.y - last.y) / scaleY
        for i in controller.selectedIndices where i < controller.engine.document.cells.count {
            controller.engine.document.cells[i].positionOffset.dx += dx
            controller.engine.document.cells[i].positionOffset.dy += dy
        }
        lastNudgeLocation = pt
    }

}

// MARK: - Polygon path builder (file scope — shared by canvas and frame buffer renderer)

func buildPolygonPath(_ polygon: Polygon2D,
                      cx: Double, cy: Double,
                      zoomX: Double, zoomY: Double,
                      scaleX: Double = 1, scaleY: Double = 1,
                      rotation: Double = 0) -> CGPath {
    let pts      = polygon.points
    let path     = CGMutablePath()
    let θ        = rotation * .pi / 180
    let cosθ     = cos(θ), sinθ = sin(θ)
    let doRotate = rotation != 0
    func pt(_ v: Vector2D) -> CGPoint {
        var lx = v.x * scaleX
        var ly = v.y * scaleY
        if doRotate {
            let rx = lx * cosθ - ly * sinθ
            let ry = lx * sinθ + ly * cosθ
            lx = rx; ly = ry
        }
        return CGPoint(x: cx + lx * zoomX, y: cy - ly * zoomY)
    }

    switch polygon.type {

    case .spline, .openSpline:
        guard pts.count >= 4 else { return path }
        let nSeg = pts.count / 4
        path.move(to: pt(pts[0]))
        for i in 0 ..< nSeg {
            let b = i * 4
            path.addCurve(to: pt(pts[b+3]), control1: pt(pts[b+1]), control2: pt(pts[b+2]))
        }
        if polygon.type == .spline { path.closeSubpath() }

    case .line:
        guard pts.count >= 2 else { return path }
        path.move(to: pt(pts[0]))
        for i in 1 ..< pts.count { path.addLine(to: pt(pts[i])) }
        path.closeSubpath()

    case .point:
        guard let p = pts.first else { return path }
        let c = pt(p)
        // Fixed visual radius — scales gently with cell size, min 2.5 pt
        let r = max(2.5, min(abs(zoomX), abs(zoomY)) * abs(scaleX + scaleY) * 0.05)
        path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

    case .oval:
        // pts[0] = centre, pts[1] = centre + (rx, ry) in world space.
        // Apply scale and rotation to the centre; derive screen radii from raw world extents.
        guard pts.count >= 2 else { return path }
        let screenC = pt(pts[0])
        let raw     = pts[1] - pts[0]           // (rx, ry) in world space, unrotated
        let screenRx = abs(raw.x) * abs(scaleX) * abs(zoomX)
        let screenRy = abs(raw.y) * abs(scaleY) * abs(zoomY)
        path.addEllipse(in: CGRect(x: screenC.x - screenRx, y: screenC.y - screenRy,
                                   width: screenRx * 2, height: screenRy * 2))
    }

    return path
}

// MARK: - Per-sprite motion transform

struct SpriteMotion {
    var dx:             Double = 0
    var dy:             Double = 0
    var scaleX:         Double = 1
    var scaleY:         Double = 1
    var rotation:       Double = 0    // degrees added to cell.rotation
    var fillOverride:   UMColor? = nil
    var strokeOverride: UMColor? = nil
}

/// Inject sampled image/video color into motion's fill and/or stroke override channels.
func applyColorMap(_ sampled: UMColor, source: UMColorSource,
                   style: CellStyle?, to motion: inout SpriteMotion) {
    let a      = source.preserveStyleAlpha ? (style?.fillColor.a ?? 1.0) : sampled.a
    let mapped = UMColor(r: sampled.r, g: sampled.g, b: sampled.b, a: a)
    switch source.applyTo {
    case .fill:          motion.fillOverride   = mapped
    case .stroke:        motion.strokeOverride = mapped
    case .fillAndStroke: motion.fillOverride   = mapped; motion.strokeOverride = mapped
    }
}

/// Compute the animated transform for a single cell at a given frame.
/// Combines the motionSet's parametric preset with an optional keyframe path (additive),
/// then layers Order/Chaos jitter on top.
func computeMotion(motionSet: UMMotionSet?, style: CellStyle?, path: UMMotionPath?,
                   frame: Int, phaseOffset: Int,
                   cellIndex: Int,
                   cellW: Double, cellH: Double) -> SpriteMotion {
    var m = SpriteMotion()

    // --- Parametric preset ---
    if let ms = motionSet, ms.motionPreset != .static, ms.motionPreset != .custom {
        m = computeParametric(motionSet: ms, style: style, frame: frame, phaseOffset: phaseOffset, cellW: cellW, cellH: cellH)
    }

    // --- Keyframe path (additive on top of parametric) ---
    if let path {
        let t = frame + phaseOffset
        let p = path.evaluate(atFrame: t, cellW: cellW, cellH: cellH)
        m.dx       += p.dx
        m.dy       += p.dy
        m.rotation += p.rotation
        m.scaleX   *= p.scaleX
        m.scaleY   *= p.scaleY
    }

    // --- Order/Chaos jitter ---
    if let ms = motionSet, ms.orderChaos > 0 {
        let oc   = ms.orderChaos
        let seed = Double(cellIndex) * 1.6180339887
        let t    = Double(frame + phaseOffset) / 60.0
        m.dx       += cellW * 0.30 * oc * sin(t * 2.3 * .pi * 2 + seed * 7.0)
        m.dy       += cellH * 0.30 * oc * sin(t * 1.7 * .pi * 2 + seed * 11.0)
        m.rotation += 90.0        * oc * sin(t * 1.1 * .pi * 2 + seed * 5.0)
        let sj      =               oc * 0.4 * sin(t * 0.9 * .pi * 2 + seed * 3.0)
        m.scaleX   *= max(0.05, 1.0 + sj)
        m.scaleY   *= max(0.05, 1.0 + sj * 0.8)
    }

    return m
}

/// Resolve the polygon list for a cell from its direct shapeID reference.
func resolvePolygons(shapeID: UUID?,
                     shapeMap: [UUID: [Polygon2D]],
                     fallback: [Polygon2D]) -> [Polygon2D] {
    guard let id = shapeID, let polys = shapeMap[id] else { return fallback }
    return polys
}

/// Resolve the ordered EditableClosedPolygon IDs for a shape. Returns [] when no shape is assigned.
func resolvePolygonIDs(shapeID: UUID?, idMap: [UUID: [UUID]]) -> [UUID] {
    guard let id = shapeID, let ids = idMap[id] else { return [] }
    return ids
}

func computeParametric(motionSet: UMMotionSet, style: CellStyle?,
                       frame: Int, phaseOffset: Int,
                       cellW: Double, cellH: Double) -> SpriteMotion {
    guard motionSet.motionPreset != .static, motionSet.motionPreset != .custom
    else { return SpriteMotion() }

    let cycles = Double(frame + phaseOffset) / 60.0 * motionSet.motionSpeed + motionSet.motionPhase
    let θ      = cycles * 2.0 * .pi
    let amount = motionSet.motionAmount
    var m      = SpriteMotion()

    switch motionSet.motionPreset {
    case .static, .custom:
        break

    case .spin:
        // Linear rotation — speed=1, amount=1 → ~2°/frame → full rotation every ~3 s
        m.rotation = cycles * 120.0 * amount

    case .pulse:
        // Sine-wave scale oscillation on both axes simultaneously
        let s = max(0.01, 1.0 + amount * sin(θ))
        m.scaleX = s; m.scaleY = s

    case .wave:
        // Horizontal sine displacement
        m.dx = cellW * 0.3 * amount * sin(θ)

    case .wander:
        // Two sine waves at golden-ratio frequency ratio — quasi-random 2D drift
        m.dx = cellW * 0.25 * amount * sin(θ)
        m.dy = cellH * 0.25 * amount * sin(cycles * 1.6180339887 * 2.0 * .pi + 1.0)

    case .jitter:
        // High-frequency small-amplitude jitter on position and rotation
        m.dx       = cellW * 0.06 * amount * sin(θ * 7.0)
        m.dy       = cellH * 0.06 * amount * cos(θ * 11.0)
        m.rotation = 12.0  * amount * sin(θ * 5.0)

    case .colorCycle:
        // Hue rotation through full spectrum at speed=1, amount=1
        let shift = (cycles * 360.0 * amount).truncatingRemainder(dividingBy: 360.0)
        m.fillOverride   = style?.fillColor.rotatingHue(by: shift)
        m.strokeOverride = style?.strokeColor.rotatingHue(by: shift)
    }

    // Per-axis multipliers: scale deviation from identity, not absolute value
    m.dx       *= motionSet.axisX
    m.dy       *= motionSet.axisY
    m.rotation *= motionSet.axisRotation
    m.scaleX    = 1.0 + (m.scaleX - 1.0) * motionSet.axisScale
    m.scaleY    = 1.0 + (m.scaleY - 1.0) * motionSet.axisScale

    return m
}

// MARK: - Frame buffer renderer (used by ImageRenderer for accumulation and export compositing)

struct FrameCapture: View {
    let existingBuffer: CGImage?
    let backgroundColor: UMColor
    let gridConfig: UMGridConfig
    let cells: [UMGridCell]
    let styles: [CellStyle]
    let motionPaths: [UMMotionPath]
    let projectMotionSets: [UMMotionSet]
    let shapePolygonMap: [UUID: [Polygon2D]]
    let fallbackPolygons: [Polygon2D]
    let stretchSprites: Bool
    let currentFrame: Int
    let gridW: Double
    let gridH: Double
    let cellW: Double
    let cellH: Double
    let scaleX: Double
    let scaleY: Double
    let displayScale: CGFloat
    let colorGrid: [[UMColor]]?
    let colorSource: UMColorSource?
    var strokeScale: Double = 1.0
    var drawBackground: Bool = true
    var layerTransform: CGAffineTransform = .identity
    var gridScrollDriver: UMVectorDriver = .zero
    var gridScrollMode: GridScrollMode = .wrap
    var gridDistortion: UMGridDistortion = .none

    var body: some View {
        Canvas { ctx, size in
            if drawBackground {
                if let buf = existingBuffer {
                    let img = ctx.resolve(Image(decorative: buf, scale: displayScale))
                    ctx.draw(img, in: CGRect(origin: .zero, size: size))
                } else {
                    let bg = backgroundColor
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)))
                }
            }
            if !layerTransform.isIdentity {
                ctx.concatenate(layerTransform)
            }

            let config    = gridConfig
            let styleMap  = Dictionary(uniqueKeysWithValues: styles.map         { ($0.id, $0) })
            let pathMap   = Dictionary(uniqueKeysWithValues: motionPaths.map    { ($0.id, $0) })
            let motionMap = Dictionary(uniqueKeysWithValues: projectMotionSets.map { ($0.id, $0) })
            let fcScroll  = DriverEvaluator.evaluate(gridScrollDriver, frame: currentFrame)
            let fcFracX   = fcScroll.x - floor(fcScroll.x)
            let fcFracY   = fcScroll.y - floor(fcScroll.y)
            let fcSpecs   = gridScrollRenderSpecs(cells: cells, scroll: fcScroll,
                                                   mode: gridScrollMode,
                                                   rows: config.rows, cols: config.cols)

            for spec in fcSpecs {
                let cell      = spec.cell
                let r         = spec.displayRow
                let c         = spec.displayCol
                let style     = styleMap[cell.styleID]
                let motionSet = cell.motionID.flatMap { motionMap[$0] }
                let path      = cell.pathID.flatMap { pathMap[$0] }
                var motion    = computeMotion(motionSet: motionSet, style: style, path: path,
                                              frame: currentFrame,
                                              phaseOffset: cell.phaseOffset,
                                              cellIndex: cell.gridIndex,
                                              cellW: cellW, cellH: cellH)
                if cell.lockedFillColor != nil || cell.lockedStrokeColor != nil {
                    if let fc = cell.lockedFillColor   { motion.fillOverride   = fc }
                    if let sc = cell.lockedStrokeColor { motion.strokeOverride = sc }
                } else if let src = colorSource,
                          let grid = colorGrid,
                          r < grid.count, c < grid[r].count {
                    applyColorMap(grid[r][c], source: src, style: style, to: &motion)
                }
                let dCell = gridDistortion.evaluate(row: r, col: c,
                                                    rows: config.rows, cols: config.cols,
                                                    uniformCellW: cellW, uniformCellH: cellH,
                                                    gridW: gridW, gridH: gridH)
                let dCellW = dCell.cellW, dCellH = dCell.cellH
                let mx = dCell.cx - fcFracX * cellW + cell.positionOffset.dx * scaleX + motion.dx
                let my = dCell.cy - fcFracY * cellH + cell.positionOffset.dy * scaleY + motion.dy
                let fillC   = motion.fillOverride   ?? style?.fillColor   ?? .defaultFill
                let strokeC = motion.strokeOverride ?? style?.strokeColor ?? .defaultStroke
                let strokeW = (style?.strokeWidth ?? 1.5) * strokeScale
                let mode    = style?.renderMode  ?? .filledStroked

                let fcEffectiveShapeID = resolveSequenceShapeID(motionSet: motionSet,
                                                               cellShapeID: cell.shapeID,
                                                               frame: currentFrame,
                                                               phaseOffset: cell.phaseOffset)
                let polygons = resolvePolygons(shapeID: fcEffectiveShapeID,
                                               shapeMap: shapePolygonMap,
                                               fallback: fallbackPolygons)

                if polygons.isEmpty {
                    let rw = (dCellW - 4 * strokeScale) / 2 * motion.scaleX
                    let rh = (dCellH - 4 * strokeScale) / 2 * motion.scaleY
                    ctx.fill(Path(roundedRect: CGRect(x: mx-rw, y: my-rh, width: rw*2, height: rh*2),
                                  cornerRadius: 3),
                             with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
                } else {
                    let dCellHalf = min(dCellW, dCellH)
                    let zoomX = (stretchSprites ? dCellW : dCellHalf) * motion.scaleX
                    let zoomY = (stretchSprites ? dCellH : dCellHalf) * motion.scaleY
                    for polygon in polygons.filter(\.visible) {
                        let cgp = buildPolygonPath(polygon, cx: mx, cy: my,
                                                   zoomX: zoomX, zoomY: zoomY,
                                                   scaleX: cell.scaleX, scaleY: cell.scaleY,
                                                   rotation: cell.rotation + motion.rotation)
                        if mode == .filled || mode == .filledStroked {
                            ctx.fill(Path(cgp),
                                     with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
                        }
                        if mode == .stroked || mode == .filledStroked {
                            ctx.stroke(Path(cgp),
                                       with: .color(Color(red: strokeC.r, green: strokeC.g, blue: strokeC.b, opacity: strokeC.a)),
                                       lineWidth: strokeW)
                        }
                    }
                }
            }
        }
        .frame(width: gridW, height: gridH)
    }
}

// MARK: - Sprite layer capture (ImageRenderer helper, parallel to FrameCapture)

struct SpriteCapture: View {
    let sprites: [UMSprite]
    let projectStyles: [CellStyle]
    let projectMotionSets: [UMMotionSet]
    let projectAnimatedGeometries: [UMAnimatedGeometry]
    let shapePolygonMap: [UUID: [Polygon2D]]
    let shapePolygonIDMap: [UUID: [UUID]]
    let fallbackPolygons: [Polygon2D]
    let currentFrame: Int
    let gridW: Double
    let gridH: Double
    var strokeScale: Double = 1.0
    var layerTransform: CGAffineTransform = .identity

    var body: some View {
        Canvas { ctx, _ in
            if !layerTransform.isIdentity { ctx.concatenate(layerTransform) }
            let styleMap  = Dictionary(uniqueKeysWithValues: projectStyles.map { ($0.id, $0) })
            let motionMap = Dictionary(uniqueKeysWithValues: projectMotionSets.map { ($0.id, $0) })
            let spriteRef = min(gridW, gridH) / 8.0
            for (idx, sprite) in sprites.enumerated() {
                let motionSet = sprite.motionID.flatMap { motionMap[$0] }
                let styleOverrideID = resolveEffectiveSpriteStyleID(sprite: sprite,
                                                                     animatedGeometries: projectAnimatedGeometries,
                                                                     frame: currentFrame)
                let style     = (styleOverrideID ?? sprite.styleID).flatMap { styleMap[$0] }
                let motion    = computeMotion(motionSet: motionSet, style: style, path: nil,
                                              frame: currentFrame, phaseOffset: sprite.phaseOffset,
                                              cellIndex: idx,
                                              cellW: spriteRef * sprite.scaleX,
                                              cellH: spriteRef * sprite.scaleY)
                let driverPos = DriverEvaluator.evaluate(sprite.positionDriver, frame: currentFrame, spriteIndex: idx)
                let stateT = resolveEffectiveSpriteStateTransform(sprite: sprite,
                                                                   animatedGeometries: projectAnimatedGeometries,
                                                                   frame: currentFrame)
                let mx  = sprite.x * gridW + motion.dx + driverPos.x + stateT.offsetX
                let my  = sprite.y * gridH + motion.dy + driverPos.y + stateT.offsetY
                let rot = sprite.rotation + motion.rotation + stateT.rotation
                let effectiveShapeID = resolveEffectiveSpriteShapeID(sprite: sprite, motionSet: motionSet,
                                                                      animatedGeometries: projectAnimatedGeometries,
                                                                      frame: currentFrame)
                let polygons   = resolvePolygons(shapeID: effectiveShapeID,
                                                 shapeMap: shapePolygonMap,
                                                 fallback: fallbackPolygons)
                let polygonIDs = resolvePolygonIDs(shapeID: effectiveShapeID, idMap: shapePolygonIDMap)
                let zoomX = (spriteRef / 2) * sprite.scaleX * motion.scaleX * stateT.scaleX
                let zoomY = (spriteRef / 2) * sprite.scaleY * motion.scaleY * stateT.scaleY

                if polygons.isEmpty {
                    let fc = style?.fillColor ?? .defaultFill
                    ctx.fill(Path(roundedRect: CGRect(x: mx - zoomX, y: my - zoomY, width: zoomX * 2, height: zoomY * 2),
                                  cornerRadius: 3),
                             with: .color(Color(red: fc.r, green: fc.g, blue: fc.b, opacity: fc.a)))
                } else {
                    let fillC   = style?.fillColor   ?? .defaultFill
                    let strokeC = style?.strokeColor ?? .defaultStroke
                    let strokeW = (style?.strokeWidth ?? 1.5) * strokeScale
                    let mode    = style?.renderMode  ?? .filledStroked
                    for (i, polygon) in polygons.filter(\.visible).enumerated() {
                        let ovr = sprite.polygonOverrides[polygonIDs[safe: i]?.uuidString ?? ""]
                        let fC  = ovr?.fill   ?? fillC
                        let sC  = ovr?.stroke ?? strokeC
                        let cgp = buildPolygonPath(polygon, cx: mx, cy: my,
                                                   zoomX: zoomX, zoomY: zoomY,
                                                   scaleX: 1.0, scaleY: 1.0,
                                                   rotation: rot)
                        if mode == .filled || mode == .filledStroked {
                            ctx.fill(Path(cgp),
                                     with: .color(Color(red: fC.r, green: fC.g, blue: fC.b, opacity: fC.a)))
                        }
                        if mode == .stroked || mode == .filledStroked {
                            ctx.stroke(Path(cgp),
                                       with: .color(Color(red: sC.r, green: sC.g, blue: sC.b, opacity: sC.a)),
                                       lineWidth: strokeW)
                        }
                    }
                }
            }
        }
        .frame(width: gridW, height: gridH)
    }
}

// MARK: - Export render helper (module-internal; used by UMVideoExporter)

@MainActor
func umRenderFrame(
    doc: UMGridDocument,
    backgroundColor: UMColor,
    shapePolygonMap: [UUID: [Polygon2D]],
    fallbackPolygons: [Polygon2D],
    projectMotionSets: [UMMotionSet],
    colorMapEngine: UMColorMapEngine,
    backgroundDraw: Bool,
    stretchSprites: Bool,
    frame: Int,
    exportW: Double,
    exportH: Double,
    strokeScale: Double,
    accumulationBuffer: CGImage?
) -> CGImage? {
    let config = doc.gridConfig
    let cellW  = exportW / Double(config.cols)
    let cellH  = exportH / Double(config.rows)
    let sx     = cellW / config.cellWidth
    let sy     = cellH / config.cellHeight
    let loopMode  = doc.colorSource?.videoLoopMode ?? .loop
    let colorGrid = colorMapEngine.currentGrid(animationFrame: frame, loopMode: loopMode)
    let renderer = ImageRenderer(content: FrameCapture(
        existingBuffer:    backgroundDraw ? nil : accumulationBuffer,
        backgroundColor:   backgroundColor,
        gridConfig:        config,
        cells:             doc.cells,
        styles:            doc.styles,
        motionPaths:       doc.paths,
        projectMotionSets: projectMotionSets,
        shapePolygonMap:   shapePolygonMap,
        fallbackPolygons:  fallbackPolygons,
        stretchSprites:    stretchSprites,
        currentFrame:      frame,
        gridW: exportW, gridH: exportH,
        cellW: cellW, cellH: cellH,
        scaleX: sx, scaleY: sy,
        displayScale:      1.0,
        colorGrid:         colorGrid,
        colorSource:       doc.colorSource,
        strokeScale:       strokeScale
    ))
    renderer.scale = 1.0
    renderer.colorMode = .nonLinear
    return renderer.cgImage
}

/// Per-layer camera+parallax transform. parallaxFactor 0=background-fixed, 1=world-space.
func umLayerTransform(
    cameraFrame: UMCameraFrame,
    parallaxFactor: Double,
    layerOffset: UMVec2,
    canvasW: Double, canvasH: Double
) -> CGAffineTransform {
    let cx   = CGFloat(canvasW / 2)
    let cy   = CGFloat(canvasH / 2)
    let dx   = CGFloat(-cameraFrame.pan.x * parallaxFactor + layerOffset.x)
    let dy   = CGFloat(-cameraFrame.pan.y * parallaxFactor + layerOffset.y)
    let zoom = CGFloat(max(0.01, cameraFrame.zoom))
    let rot  = CGFloat(cameraFrame.rotation * .pi / 180)
    return CGAffineTransform.identity
        .translatedBy(x: cx, y: cy)
        .scaledBy(x: zoom, y: zoom)
        .rotated(by: rot)
        .translatedBy(x: -cx + dx, y: -cy + dy)
}

/// Composite all visible layers into a single CGImage for PNG/video export.
/// Each layer is rendered cells-only (transparent background) via ImageRenderer,
/// then blended into a CoreGraphics context at the layer's opacity.
@MainActor
func umRenderComposited(
    layerStates: [UMLayerState],
    backgroundColor: UMColor,
    backgroundImage: CGImage? = nil,
    shapePolygonMap: [UUID: [Polygon2D]],
    shapePolygonIDMap: [UUID: [UUID]],
    fallbackPolygons: [Polygon2D],
    projectMotionSets: [UMMotionSet],
    projectAnimatedGeometries: [UMAnimatedGeometry] = [],
    colorMapEngines: [UUID: UMColorMapEngine],
    backgroundDraw: Bool,
    stretchSprites: Bool,
    frame: Int,
    exportW: Double,
    exportH: Double,
    strokeScale: Double,
    accumulationBuffer: CGImage?,
    camera: UMCamera = .identity
) -> CGImage? {
    let w = Int(exportW); let h = Int(exportH)
    guard w > 0, h > 0 else { return nil }
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                   | CGBitmapInfo.byteOrder32Little.rawValue
    guard let ctx = CGContext(data: nil, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: umCompositingColorSpace,
                              bitmapInfo: bitmapInfo) else { return nil }
    let destRect = CGRect(x: 0, y: 0, width: w, height: h)

    // Accumulation base or background fill
    if let buf = accumulationBuffer, !backgroundDraw {
        ctx.draw(buf, in: destRect)
    } else {
        ctx.setFillColor(CGColor(red: backgroundColor.r, green: backgroundColor.g,
                                 blue: backgroundColor.b, alpha: backgroundColor.a))
        ctx.fill(destRect)
        if let bgImg = backgroundImage { ctx.draw(bgImg, in: destRect) }
    }

    let cameraFrame = camera.evaluate(frame: frame)
    for ls in layerStates where ls.isVisible {
        let layerOff = DriverEvaluator.evaluate(ls.layerOffset, frame: frame)
        let layerXF  = umLayerTransform(cameraFrame: cameraFrame,
                                         parallaxFactor: ls.parallaxFactor,
                                         layerOffset: layerOff,
                                         canvasW: exportW, canvasH: exportH)
        let opacity  = DriverEvaluator.evaluate(ls.opacityDriver, frame: frame)

        if ls.layerMode == .sprite {
            let renderer = ImageRenderer(content: SpriteCapture(
                sprites:                    ls.sprites,
                projectStyles:              ls.engine.document.styles,
                projectMotionSets:          projectMotionSets,
                projectAnimatedGeometries:  projectAnimatedGeometries,
                shapePolygonMap:            shapePolygonMap,
                shapePolygonIDMap:          shapePolygonIDMap,
                fallbackPolygons:           fallbackPolygons,
                currentFrame:               frame,
                gridW: exportW, gridH: exportH,
                strokeScale:                strokeScale,
                layerTransform:             layerXF
            ))
            renderer.scale = 1.0
            renderer.colorMode = .nonLinear
            if let img = renderer.cgImage {
                ctx.setBlendMode(ls.blendMode.cgBlendMode)
                ctx.setAlpha(opacity)
                ctx.draw(img, in: destRect)
                ctx.setAlpha(1.0)
                ctx.setBlendMode(.normal)
            }
            continue
        }

        let lConfig = ls.engine.document.gridConfig
        let lCellW  = exportW / Double(lConfig.cols)
        let lCellH  = exportH / Double(lConfig.rows)
        let lSX     = lCellW / lConfig.cellWidth
        let lSY     = lCellH / lConfig.cellHeight
        let loopMode  = ls.engine.document.colorSource?.videoLoopMode ?? .loop
        let colorGrid = colorMapEngines[ls.id]?.currentGrid(animationFrame: frame, loopMode: loopMode)

        let renderer = ImageRenderer(content: FrameCapture(
            existingBuffer:    nil,
            backgroundColor:   backgroundColor,
            gridConfig:        lConfig,
            cells:             ls.engine.document.cells,
            styles:            ls.engine.document.styles,
            motionPaths:       ls.engine.document.paths,
            projectMotionSets: projectMotionSets,
            shapePolygonMap:   shapePolygonMap,
            fallbackPolygons:  fallbackPolygons,
            stretchSprites:    stretchSprites,
            currentFrame:      frame,
            gridW: exportW, gridH: exportH,
            cellW: lCellW, cellH: lCellH,
            scaleX: lSX, scaleY: lSY,
            displayScale:      1.0,
            colorGrid:         colorGrid,
            colorSource:       ls.engine.document.colorSource,
            strokeScale:       strokeScale,
            drawBackground:    false,
            layerTransform:    layerXF,
            gridScrollDriver:  ls.gridScrollDriver,
            gridScrollMode:    ls.gridScrollMode,
            gridDistortion:    ls.gridDistortion
        ))
        renderer.scale = 1.0
        renderer.colorMode = .nonLinear
        if let img = renderer.cgImage {
            ctx.setBlendMode(ls.blendMode.cgBlendMode)
            ctx.setAlpha(opacity)
            ctx.draw(img, in: destRect)
            ctx.setAlpha(1.0)
            ctx.setBlendMode(.normal)
        }
    }

    return ctx.makeImage()
}

// MARK: - Transport bar

struct TransportBarView: View {
    @Environment(AppController.self) private var controller
    @State private var showTimeline      = false
    @State private var isScrubbing       = false
    @State private var scrubValue        = 0.0
    @State private var wasPlayingBefore  = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if controller.showScrubBar {
                scrubRow
            }
        }
        .sheet(isPresented: $showTimeline) {
            TimelineView()
                .environment(controller)
        }
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            // Rewind
            Button(action: { controller.rewindToStart() }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 11))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 22, minHeight: 22)
            .contentShape(Rectangle())
            .foregroundStyle(Color.primary)
            .help("Rewind to start / exit timeline mode")

            // Play / Pause
            Button(action: { controller.togglePlayback() }) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 22, minHeight: 22)
            .contentShape(Rectangle())
            .foregroundStyle(controller.isPlaying ? Color.accentColor : Color.primary)

            // Record
            Button(action: { controller.toggleRecording() }) {
                Image(systemName: controller.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 14))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 22, minHeight: 22)
            .contentShape(Rectangle())
            .foregroundStyle(controller.isRecording ? Color.red : Color.primary)
            .help(controller.isRecording ? "Stop recording" : "Record timeline states")

            // Frame counter
            Text("\(controller.engine.currentFrame)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            // Start / End fields
            HStack(spacing: 3) {
                Text("S")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                TextField("", value: Binding(
                    get: { controller.startFrame },
                    set: { controller.startFrame = max(0, $0) }
                ), format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 44)
                .help("Start frame")

                Text("E")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                TextField("", value: Binding(
                    get: { controller.endFrame },
                    set: { controller.endFrame = max(1, $0) }
                ), format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 44)
                .help("End frame")
            }

            // Scrub bar toggle
            Button {
                controller.showScrubBar.toggle()
            } label: {
                Image(systemName: controller.showScrubBar ? "slider.horizontal.below.rectangle" : "slider.horizontal.below.rectangle")
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(controller.showScrubBar ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 22, minHeight: 22)
            .contentShape(Rectangle())
            .help(controller.showScrubBar ? "Hide scrub bar" : "Show scrub bar")

            // Timeline navigation (shown when cut states have been recorded)
            if !controller.engine.document.timeline.isEmpty {
                Divider().frame(height: 14)

                Button(action: { controller.stepTimeline(forward: false) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
                .foregroundStyle(Color.primary)
                .help("Previous state")

                Button(action: { showTimeline = true }) {
                    let pos   = controller.timelinePosition
                    let count = controller.engine.document.timeline.count
                    Text(pos < 0 ? "—/\(count)" : "\(pos + 1)/\(count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(pos < 0 ? Color.secondary : Color.primary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
                .help("Open cut timeline editor")

                Button(action: { controller.stepTimeline(forward: true) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
                .foregroundStyle(Color.primary)
                .help("Next state")
            }

            Spacer()

            if let projURL = controller.currentFileURL {
                Text((projURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 220, alignment: .leading)
                Spacer(minLength: 12)
            }

            Button("PNG") {
                controller.exportPNG()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .disabled(controller.isExporting)

            Button("SVG") { }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Group {
                if controller.isExporting {
                    HStack(spacing: 4) {
                        ProgressView(value: controller.exportProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 60)
                        Text("\(Int(controller.exportProgress * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else if !controller.engine.document.timeline.isEmpty {
                    Menu("Video ▾") {
                        Button("Live animation…") { controller.exportVideo() }
                        Button("Cut sequence (\(controller.engine.document.timeline.count) cuts)…") {
                            controller.exportCutVideo()
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.system(size: 12))
                } else {
                    Button("Video") {
                        controller.exportVideo()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var scrubRow: some View {
        let maxF = Double(controller.maxScrubFrames)
        let displayFrame = isScrubbing ? Int(scrubValue) : controller.engine.currentFrame
        return HStack(spacing: 6) {
            Text("\(displayFrame)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : Double(controller.engine.currentFrame) },
                    set: { v in
                        scrubValue = v
                        controller.seekToFrame(Int(v.rounded()))
                    }
                ),
                in: Double(controller.startFrame)...max(Double(controller.startFrame) + 1, maxF),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        wasPlayingBefore = controller.isPlaying
                        if controller.isPlaying { controller.togglePlayback() }
                    } else {
                        if wasPlayingBefore { controller.togglePlayback() }
                    }
                }
            )
            Text("\(Int(maxF))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: controller.engine.currentFrame) { _, val in
            if !isScrubbing { scrubValue = Double(val) }
        }
    }
}

// MARK: - Resample sheet

struct ResampleSheetView: View {
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var targetRows: Double
    @State private var targetCols: Double
    @State private var scale: Double = 1

    init(currentRows: Int, currentCols: Int) {
        _targetRows = State(initialValue: Double(currentRows))
        _targetCols = State(initialValue: Double(currentCols))
    }

    private var newRows: Int { max(1, Int(targetRows.rounded())) }
    private var newCols: Int { max(1, Int(targetCols.rounded())) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Title
            Text("Resample Grid")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Divider()

            // Target size
            sectionLabel("TARGET SIZE")
            InspectorField("Rows") {
                FloatEntryField(value: $targetRows, width: 58, fractionDigits: 0)
            }
            InspectorField("Cols") {
                FloatEntryField(value: $targetCols, width: 58, fractionDigits: 0)
            }

            // Scale factor
            sectionLabel("SCALE FACTOR")
            HStack(spacing: 6) {
                Text("Factor")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                FloatEntryField(value: $scale, width: 58, fractionDigits: 3)
                Button("Apply") { applyScale() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Resize policies — read/write the config so settings persist
            sectionLabel("RESIZE POLICIES")
            InspectorField("Offset") {
                Picker("", selection: Binding(
                    get: { controller.engine.document.gridConfig.resizeOffsetPolicy },
                    set: { controller.engine.document.gridConfig.resizeOffsetPolicy = $0 }
                )) {
                    Text("Preserve").tag(ResizeOffsetPolicy.preserveAbsolute)
                    Text("Scale").tag(ResizeOffsetPolicy.scaleProportional)
                    Text("Reset").tag(ResizeOffsetPolicy.reset)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
            }
            InspectorField("Phase") {
                Picker("", selection: Binding(
                    get: { controller.engine.document.gridConfig.resizePhasePolicy },
                    set: { controller.engine.document.gridConfig.resizePhasePolicy = $0 }
                )) {
                    Text("Inherit").tag(ResizePhasePolicy.inherit)
                    Text("Scatter").tag(ResizePhasePolicy.inheritWithScatter)
                    Text("Reset").tag(ResizePhasePolicy.reset)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
            }
            if controller.engine.document.gridConfig.resizePhasePolicy == .inheritWithScatter {
                InspectorField("Scatter") {
                    ResettableSlider(
                        value: Binding(
                            get: { controller.engine.document.gridConfig.resizePhaseScatter },
                            set: { controller.engine.document.gridConfig.resizePhaseScatter = $0 }
                        ),
                        range: 0...1,
                        defaultValue: 0
                    )
                    Text(controller.engine.document.gridConfig.resizePhaseScatter
                            .formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            sectionLabel("POSITION SCATTER")
            InspectorField("Scatter") {
                ResettableSlider(
                    value: Binding(
                        get: { controller.engine.document.gridConfig.resizePositionScatter },
                        set: { controller.engine.document.gridConfig.resizePositionScatter = $0 }
                    ),
                    range: 0...1,
                    defaultValue: 0
                )
                Text(controller.engine.document.gridConfig.resizePositionScatter
                        .formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            // Preview
            let srcR = controller.engine.document.gridConfig.rows
            let srcC = controller.engine.document.gridConfig.cols
            Text("\(srcR) × \(srcC)  →  \(newRows) × \(newCols)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)

            Divider()

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Resample") {
                    controller.resample(toRows: newRows, cols: newCols)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newRows == srcR && newCols == srcC)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 300)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func applyScale() {
        guard scale > 0 else { return }
        targetRows = max(1, (targetRows * scale).rounded())
        targetCols = max(1, (targetCols * scale).rounded())
    }
}
