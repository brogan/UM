import SwiftUI
import UMEngine
import LoomEngine

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
                    .frame(width: 16)
                Text(controller.stampPhaseOffset >= 0
                     ? "+\(controller.stampPhaseOffset)"
                     : "\(controller.stampPhaseOffset)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 28)
                    .multilineTextAlignment(.center)
                Button("+") { controller.stampPhaseOffset += 1 }
                    .buttonStyle(.plain)
                    .frame(width: 16)
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
                .frame(width: 16)
                Text("\(controller.engine.document.gridConfig.phaseStepFrames) fr")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 36)
                    .multilineTextAlignment(.center)
                Button("+") {
                    controller.engine.document.gridConfig.phaseStepFrames =
                        min(240, controller.engine.document.gridConfig.phaseStepFrames + 1)
                }
                .buttonStyle(.plain)
                .frame(width: 16)
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
}

private struct AccumulationSnapshot: @unchecked Sendable {
    let layers: [LayerAccumulationData]
    let previousBuffer: CGImage?
    let backgroundColor: UMColor
    let backgroundImage: CGImage?
    let shapePolygonMap: [UUID: [Polygon2D]]
    let fallbackPolygons: [Polygon2D]
    let projectMotionSets: [UMMotionSet]
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
                                   space: CGColorSpaceCreateDeviceRGB(),
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
        mainCtx.setAlpha(layer.opacity)
        mainCtx.draw(layerImage, in: frame)
        mainCtx.setAlpha(1.0)
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
                               space: CGColorSpaceCreateDeviceRGB(),
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
            let style     = sprite.styleID.flatMap { styleMap[$0] }
            let motionSet = sprite.motionID.flatMap { motionMap[$0] }
            let motion    = computeMotion(motionSet: motionSet, style: style, path: nil,
                                          frame: snap.frame, phaseOffset: sprite.phaseOffset,
                                          cellIndex: idx,
                                          cellW: spriteRef * sprite.scaleX,
                                          cellH: spriteRef * sprite.scaleY)
            let mx = (sprite.x * layer.gridW + motion.dx) * dsf
            let my = (sprite.y * layer.gridH + motion.dy) * dsf
            let polygons = resolvePolygons(shapeID: sprite.shapeID,
                                           shapeMap: snap.shapePolygonMap,
                                           fallback: snap.fallbackPolygons)
            let zoomX = (spriteRef / 2) * sprite.scaleX * motion.scaleX * dsf
            let zoomY = (spriteRef / 2) * sprite.scaleY * motion.scaleY * dsf
            let rot   = sprite.rotation + motion.rotation
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
                for (polyIdx, polygon) in polygons.filter(\.visible).enumerated() {
                    let ovr = sprite.polygonOverrides[polyIdx]
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
    @State private var spriteDragID:     UUID?    = nil
    @State private var spriteDragOffset: CGPoint  = .zero
    // Zoom/pan state
    @State private var baseZoom: Double = 1.0
    @State private var scrollMonitor: Any? = nil
    // Hover preview state
    @State private var hoverViewPoint: CGPoint? = nil

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
                        ctx.stroke(linePath,
                                   with: .color(Color(red: gc.r, green: gc.g, blue: gc.b, opacity: gc.a)),
                                   lineWidth: controller.gridLineWidth)
                    }

                    // Drawn cells — render each layer into an isolated compositing group.
                    let shapePolyMap  = controller.shapePolygonMap
                    let fallbackPolys = controller.shapePolygons
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
                            ctx.drawLayer { layerCtx in
                                layerCtx.opacity = lOpacity
                                if !lLayerXF.isIdentity { layerCtx.concatenate(lLayerXF) }
                                let styleMap  = Dictionary(uniqueKeysWithValues: controller.projectStyles.map { ($0.id, $0) })
                                let spriteRef = min(gridW, gridH) / 8.0
                                for (idx, sprite) in ls.sprites.enumerated() {
                                    let style     = sprite.styleID.flatMap { styleMap[$0] }
                                    let motionSet = sprite.motionID.flatMap { lMotionMap[$0] }
                                    let motion    = computeMotion(motionSet: motionSet, style: style, path: nil,
                                                                  frame: currentFrame,
                                                                  phaseOffset: sprite.phaseOffset,
                                                                  cellIndex: idx,
                                                                  cellW: spriteRef * sprite.scaleX,
                                                                  cellH: spriteRef * sprite.scaleY)
                                    let mx  = sprite.x * gridW + motion.dx
                                    let my  = sprite.y * gridH + motion.dy
                                    let rot = sprite.rotation + motion.rotation
                                    let polygons = resolvePolygons(shapeID: sprite.shapeID,
                                                                   shapeMap: shapePolyMap,
                                                                   fallback: fallbackPolys)
                                    let zoomX = (spriteRef / 2) * sprite.scaleX * motion.scaleX
                                    let zoomY = (spriteRef / 2) * sprite.scaleY * motion.scaleY
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
                                        let paths   = polygons.filter(\.visible).enumerated().map { (polyIdx, polygon) -> CGPath in
                                            buildPolygonPath(polygon, cx: mx, cy: my,
                                                             zoomX: zoomX, zoomY: zoomY,
                                                             scaleX: 1.0, scaleY: 1.0,
                                                             rotation: rot)
                                        }
                                        for (polyIdx, cgp) in paths.enumerated() {
                                            let ovr   = sprite.polygonOverrides[polyIdx]
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
                        let lCellHalf = min(lCellW, lCellH)
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
                        ctx.drawLayer { layerCtx in
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
                                let mx = Double(c) * lCellW + lCellW / 2 - lFracX * lCellW + cell.positionOffset.dx * lScaleX + motion.dx
                                let my = Double(r) * lCellH + lCellH / 2 - lFracY * lCellH + cell.positionOffset.dy * lScaleY + motion.dy
                                let isSelected = isActiveLayer && controller.selectedIndices.contains(cell.gridIndex)

                                let lEffectiveShapeID = resolveSequenceShapeID(motionSet: motionSet,
                                                                               cellShapeID: cell.shapeID,
                                                                               frame: currentFrame,
                                                                               phaseOffset: cell.phaseOffset)
                                let polygons = resolvePolygons(shapeID: lEffectiveShapeID,
                                                               shapeMap: shapePolyMap,
                                                               fallback: fallbackPolys)

                                if polygons.isEmpty {
                                    let rw   = (lCellW - 4) / 2 * motion.scaleX
                                    let rh   = (lCellH - 4) / 2 * motion.scaleY
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
                                    let zoomX   = (stretch ? lCellW : lCellHalf) * motion.scaleX
                                    let zoomY   = (stretch ? lCellH : lCellHalf) * motion.scaleY
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

                        // Keyframe relative positions
                        let kfRelPts: [CGPoint] = activePath.keyframes.map { kf in
                            let (dx, dy, _, _, _) = activePath.evaluate(atFrame: kf.frame, cellW: cellW, cellH: cellH)
                            return CGPoint(x: dx, y: dy)
                        }

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

                            // Keyframe dots
                            for kfPt in kfRelPts {
                                let p = CGPoint(x: cx + kfPt.x, y: cy + kfPt.y)
                                ctx.fill(Path(ellipseIn: CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)),
                                         with: .color(Color.accentColor.opacity(0.85)))
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
                            // Sprite layer intercept
                            let activeLS = controller.layerStates[controller.activeLayerIndex]
                            if activeLS.layerMode == .sprite {
                                if spriteDragID == nil {
                                    let startPt = canvasPoint(value.startLocation,
                                                              viewSize: geo.size,
                                                              gridW: gridW, gridH: gridH)
                                    if let hit = spriteHitTest(at: startPt, in: activeLS,
                                                               gridW: gridW, gridH: gridH) {
                                        controller.activeSpriteID = hit.id
                                        spriteDragID     = hit.id
                                        // offset = display position of sprite - click position (display)
                                        spriteDragOffset = CGPoint(x: hit.x * gridW - startPt.x,
                                                                   y: hit.y * gridH - startPt.y)
                                    }
                                }
                                if let dragID = spriteDragID {
                                    let newX = (pt.x + spriteDragOffset.x) / gridW
                                    let newY = (pt.y + spriteDragOffset.y) / gridH
                                    controller.moveSprite(id: dragID,
                                                         to: CGPoint(x: newX, y: newY))
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
                            let activeLS = controller.layerStates[controller.activeLayerIndex]
                            if activeLS.layerMode == .sprite {
                                if spriteDragID != nil {
                                    spriteDragID     = nil
                                    spriteDragOffset = .zero
                                } else {
                                    let dist = hypot(value.translation.width, value.translation.height)
                                    if dist < 8 {
                                        let startPt = canvasPoint(value.startLocation,
                                                                  viewSize: geo.size,
                                                                  gridW: cachedGridW, gridH: cachedGridH)
                                        if spriteHitTest(at: startPt, in: activeLS,
                                                         gridW: cachedGridW, gridH: cachedGridH) == nil {
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
                                gridH:     gridH
                            )
                        },
                        previousBuffer:    controller.frameBuffer,
                        backgroundColor:   controller.backgroundColor,
                        backgroundImage:   controller.backgroundCGImage,
                        shapePolygonMap:   controller.shapePolygonMap,
                        fallbackPolygons:  controller.shapePolygons,
                        projectMotionSets: controller.projectMotionSets,
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


    private func canvasPoint(_ viewPt: CGPoint, viewSize: CGSize,
                             gridW: Double, gridH: Double) -> CGPoint {
        let zoom = controller.canvasZoom
        let pan  = controller.canvasPan
        let tx   = (viewSize.width  - gridW * zoom) / 2 + pan.width
        let ty   = (viewSize.height - gridH * zoom) / 2 + pan.height
        return CGPoint(x: (viewPt.x - tx) / zoom, y: (viewPt.y - ty) / zoom)
    }

    private func spriteHitTest(at pt: CGPoint, in ls: UMLayerState,
                               gridW: Double, gridH: Double) -> UMSprite? {
        let ref = min(gridW, gridH) / 8.0
        return ls.sprites.last { sprite in
            let sx = sprite.x * gridW
            let sy = sprite.y * gridH
            let hw = (ref / 2) * sprite.scaleX
            let hh = (ref / 2) * sprite.scaleY
            return abs(pt.x - sx) < hw && abs(pt.y - sy) < hh
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

private func buildPolygonPath(_ polygon: Polygon2D,
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

private struct SpriteMotion {
    var dx:             Double = 0
    var dy:             Double = 0
    var scaleX:         Double = 1
    var scaleY:         Double = 1
    var rotation:       Double = 0    // degrees added to cell.rotation
    var fillOverride:   UMColor? = nil
    var strokeOverride: UMColor? = nil
}

/// Inject sampled image/video color into motion's fill and/or stroke override channels.
private func applyColorMap(_ sampled: UMColor, source: UMColorSource,
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
private func computeMotion(motionSet: UMMotionSet?, style: CellStyle?, path: UMMotionPath?,
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
private func resolvePolygons(shapeID: UUID?,
                              shapeMap: [UUID: [Polygon2D]],
                              fallback: [Polygon2D]) -> [Polygon2D] {
    guard let id = shapeID, let polys = shapeMap[id] else { return fallback }
    return polys
}

private func computeParametric(motionSet: UMMotionSet, style: CellStyle?,
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
            let half      = min(cellW, cellH)
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
                let mx = Double(c) * cellW + cellW / 2 - fcFracX * cellW + cell.positionOffset.dx * scaleX + motion.dx
                let my = Double(r) * cellH + cellH / 2 - fcFracY * cellH + cell.positionOffset.dy * scaleY + motion.dy
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
                    let rw = (cellW - 4 * strokeScale) / 2 * motion.scaleX
                    let rh = (cellH - 4 * strokeScale) / 2 * motion.scaleY
                    ctx.fill(Path(roundedRect: CGRect(x: mx-rw, y: my-rh, width: rw*2, height: rh*2),
                                  cornerRadius: 3),
                             with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
                } else {
                    let zoomX = (stretchSprites ? cellW : half) * motion.scaleX
                    let zoomY = (stretchSprites ? cellH : half) * motion.scaleY
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
    let shapePolygonMap: [UUID: [Polygon2D]]
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
                let style     = sprite.styleID.flatMap { styleMap[$0] }
                let motionSet = sprite.motionID.flatMap { motionMap[$0] }
                let motion    = computeMotion(motionSet: motionSet, style: style, path: nil,
                                              frame: currentFrame, phaseOffset: sprite.phaseOffset,
                                              cellIndex: idx,
                                              cellW: spriteRef * sprite.scaleX,
                                              cellH: spriteRef * sprite.scaleY)
                let mx  = sprite.x * gridW + motion.dx
                let my  = sprite.y * gridH + motion.dy
                let rot = sprite.rotation + motion.rotation
                let polygons = resolvePolygons(shapeID: sprite.shapeID,
                                               shapeMap: shapePolygonMap,
                                               fallback: fallbackPolygons)
                let zoomX = (spriteRef / 2) * sprite.scaleX * motion.scaleX
                let zoomY = (spriteRef / 2) * sprite.scaleY * motion.scaleY

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
                    for (polyIdx, polygon) in polygons.filter(\.visible).enumerated() {
                        let ovr = sprite.polygonOverrides[polyIdx]
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
    fallbackPolygons: [Polygon2D],
    projectMotionSets: [UMMotionSet],
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
                              space: CGColorSpaceCreateDeviceRGB(),
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
                sprites:           ls.sprites,
                projectStyles:     ls.engine.document.styles,
                projectMotionSets: projectMotionSets,
                shapePolygonMap:   shapePolygonMap,
                fallbackPolygons:  fallbackPolygons,
                currentFrame:      frame,
                gridW: exportW, gridH: exportH,
                strokeScale:       strokeScale,
                layerTransform:    layerXF
            ))
            renderer.scale = 1.0
            if let img = renderer.cgImage {
                ctx.setAlpha(opacity)
                ctx.draw(img, in: destRect)
                ctx.setAlpha(1.0)
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
            gridScrollMode:    ls.gridScrollMode
        ))
        renderer.scale = 1.0
        if let img = renderer.cgImage {
            ctx.setAlpha(opacity)
            ctx.draw(img, in: destRect)
            ctx.setAlpha(1.0)
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
            .foregroundStyle(Color.primary)
            .help("Rewind to start / exit timeline mode")

            // Play / Pause
            Button(action: { controller.togglePlayback() }) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.isPlaying ? Color.accentColor : Color.primary)

            // Record
            Button(action: { controller.toggleRecording() }) {
                Image(systemName: controller.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 14))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
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
            .help(controller.showScrubBar ? "Hide scrub bar" : "Show scrub bar")

            // Timeline navigation (shown when cut states have been recorded)
            if !controller.engine.document.timeline.isEmpty {
                Divider().frame(height: 14)

                Button(action: { controller.stepTimeline(forward: false) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
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
                .help("Open cut timeline editor")

                Button(action: { controller.stepTimeline(forward: true) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
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
