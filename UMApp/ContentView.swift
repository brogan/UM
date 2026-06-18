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
    @State private var showResampleSheet = false

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

            Toggle("Stretch", isOn: Binding(
                get: { controller.stretchSpritesToCell },
                set: { controller.stretchSpritesToCell = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .help("Stretch sprites to fill their cell")

            Button {
                showResampleSheet = true
            } label: {
                Text("\(controller.engine.document.gridConfig.rows) × \(controller.engine.document.gridConfig.cols)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Resample grid resolution")
            .sheet(isPresented: $showResampleSheet) {
                ResampleSheetView(
                    currentRows: controller.engine.document.gridConfig.rows,
                    currentCols: controller.engine.document.gridConfig.cols
                )
            }
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

// MARK: - Grid canvas

struct GridCanvasPlaceholder: View {
    @Environment(AppController.self) private var controller
    @Environment(\.displayScale) private var displayScale
    @State private var lastDragIndex: Int?         = nil
    @State private var lastNudgeLocation: CGPoint? = nil
    // Rubber-band selection state
    @State private var rubberBandStart:   CGPoint? = nil
    @State private var rubberBandCurrent: CGPoint? = nil
    // Cached layout — needed in onEnded where geo is out of scope
    @State private var cachedCellW: Double = 1
    @State private var cachedCellH: Double = 1

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

            let bg = controller.backgroundColor
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                ZStack {
                    if controller.backgroundDraw {
                        Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)
                    }

                    Canvas { ctx, size in
                    // Accumulated buffer base (background draw OFF)
                    if !controller.backgroundDraw {
                        if let buf = controller.frameBuffer {
                            let img = ctx.resolve(Image(decorative: buf, scale: displayScale))
                            ctx.draw(img, in: CGRect(origin: .zero, size: size))
                        } else {
                            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                                     with: .color(Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)))
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

                    // Drawn cells — positionOffset is in reference-pixel space,
                    // multiplied by scale to convert to screen pixels.
                    let polygons    = controller.shapePolygons
                    let useFallback = polygons.isEmpty
                    let cellHalf    = min(cellW, cellH)
                    let stretch     = controller.stretchSpritesToCell
                    let styleMap = Dictionary(uniqueKeysWithValues:
                        controller.engine.document.styles.map { ($0.id, $0) })
                    let pathMap = Dictionary(uniqueKeysWithValues:
                        controller.engine.document.paths.map { ($0.id, $0) })
                    let colorGrid    = controller.colorMapEngine.currentGrid(
                        animationFrame: currentFrame,
                        loopMode: controller.engine.document.colorSource?.videoLoopMode ?? .loop)
                    let colorSource  = controller.engine.document.colorSource

                    for cell in controller.engine.document.cells where cell.isDrawn {
                        let r      = cell.gridIndex / config.cols
                        let c      = cell.gridIndex % config.cols
                        let style  = styleMap[cell.styleID]
                        let path   = cell.pathID.flatMap { pathMap[$0] }
                        var motion = computeMotion(style: style, path: path,
                                                   frame: currentFrame,
                                                   phaseOffset: cell.phaseOffset,
                                                   cellW: cellW, cellH: cellH)
                        if let src = colorSource,
                           let grid = colorGrid,
                           r < grid.count, c < grid[r].count {
                            applyColorMap(grid[r][c], source: src, style: style, to: &motion)
                        }
                        let mx = Double(c) * cellW + cellW / 2 + cell.positionOffset.dx * scaleX + motion.dx
                        let my = Double(r) * cellH + cellH / 2 + cell.positionOffset.dy * scaleY + motion.dy
                        let isSelected = controller.selectedIndices.contains(cell.gridIndex)

                        if useFallback {
                            let rw   = (cellW - 4) / 2 * motion.scaleX
                            let rh   = (cellH - 4) / 2 * motion.scaleY
                            let rect = CGRect(x: mx - rw, y: my - rh, width: rw * 2, height: rh * 2)
                            let fc   = motion.fillOverride ?? style?.fillColor ?? .defaultFill
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                                     with: .color(Color(red: fc.r, green: fc.g, blue: fc.b)
                                         .opacity(isSelected ? min(1, fc.a * 1.3) : fc.a)))
                            if isSelected {
                                ctx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                                           with: .color(.accentColor), lineWidth: 1.5)
                            }
                        } else {
                            let zoomX   = (stretch ? cellW : cellHalf) * motion.scaleX
                            let zoomY   = (stretch ? cellH : cellHalf) * motion.scaleY
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
                                    ctx.fill(Path(cgp),
                                             with: .color(Color(red: fillC.r, green: fillC.g,
                                                                 blue: fillC.b, opacity: fillC.a)))
                                }
                                if mode == .stroked || mode == .filledStroked {
                                    ctx.stroke(Path(cgp),
                                               with: .color(Color(red: strokeC.r, green: strokeC.g,
                                                                   blue: strokeC.b, opacity: strokeC.a)),
                                               lineWidth: strokeW)
                                }
                            }
                            if isSelected {
                                for cgp in paths {
                                    ctx.stroke(Path(cgp),
                                               with: .color(.accentColor.opacity(0.9)),
                                               lineWidth: 2.5)
                                }
                            }
                        }
                    }

                    // Path overlay: trajectory + keyframe dots + animated playhead
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
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            cachedCellW = cellW
                            cachedCellH = cellH
                            switch controller.activeTool {
                            case .select:
                                if rubberBandStart == nil { rubberBandStart = value.startLocation }
                                rubberBandCurrent = value.location
                            case .nudge:
                                handleNudge(at: value.location,
                                            cellW: cellW, cellH: cellH,
                                            scaleX: scaleX, scaleY: scaleY,
                                            config: config)
                            default:
                                handleDrag(at: value.location,
                                           cellW: cellW, cellH: cellH,
                                           config: config)
                            }
                        }
                        .onEnded { value in
                            if controller.activeTool == .select {
                                handleSelectEnd(value: value, config: config)
                                rubberBandStart   = nil
                                rubberBandCurrent = nil
                            }
                            lastDragIndex     = nil
                            lastNudgeLocation = nil
                        }
                )

                // Rubber-band selection overlay
                if controller.activeTool == .select,
                   let start = rubberBandStart, let end = rubberBandCurrent {
                    let rx = min(start.x, end.x)
                    let ry = min(start.y, end.y)
                    let rw = max(1, abs(end.x - start.x))
                    let rh = max(1, abs(end.y - start.y))
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.07))
                        .overlay(
                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(Color.accentColor.opacity(0.75))
                        )
                        .frame(width: rw, height: rh)
                        .position(x: rx + rw / 2, y: ry + rh / 2)
                        .allowsHitTesting(false)
                }
                }
                .frame(width: gridW, height: gridH)
                .clipped()
                .onChange(of: controller.engine.currentFrame) {
                    captureFrameBuffer(gridW: gridW, gridH: gridH,
                                       cellW: cellW, cellH: cellH,
                                       scaleX: scaleX, scaleY: scaleY)
                }
            }
        }
    }

    private func captureFrameBuffer(gridW: Double, gridH: Double,
                                    cellW: Double, cellH: Double,
                                    scaleX: Double, scaleY: Double) {
        guard !controller.backgroundDraw else { return }
        let doc = controller.engine.document
        let loopMode  = doc.colorSource?.videoLoopMode ?? .loop
        let colorGrid = controller.colorMapEngine.currentGrid(
            animationFrame: controller.engine.currentFrame, loopMode: loopMode)
        let renderer = ImageRenderer(content: FrameCapture(
            existingBuffer:  controller.frameBuffer,
            backgroundColor: controller.backgroundColor,
            gridConfig:      doc.gridConfig,
            cells:           doc.cells,
            styles:          doc.styles,
            motionPaths:     doc.paths,
            polygons:        controller.shapePolygons,
            stretchSprites:  controller.stretchSpritesToCell,
            currentFrame:    controller.engine.currentFrame,
            gridW: gridW, gridH: gridH,
            cellW: cellW, cellH: cellH,
            scaleX: scaleX, scaleY: scaleY,
            displayScale: displayScale,
            colorGrid:       colorGrid,
            colorSource:     doc.colorSource,
            strokeScale:     1.0
        ))
        renderer.scale = displayScale
        controller.updateFrameBuffer(renderer.cgImage)
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
            let sid = controller.activeStyleID ?? controller.engine.document.styles.first?.id ?? UUID()
            controller.engine.setCellDrawn(index, drawn: true, styleID: sid)
            controller.engine.document.cells[index].pathID = controller.activePathID
        case .erase:
            controller.engine.setCellDrawn(index, drawn: false, styleID: UUID())
        case .sample:
            if let style = controller.engine.sampleStyle(at: index) {
                controller.activeStyleID = style.id
            }
        case .fill:
            let sid = controller.activeStyleID ?? controller.engine.document.styles.first?.id ?? UUID()
            controller.engine.floodFill(from: index, styleID: sid, pathID: controller.activePathID)
        case .select, .nudge:
            break  // handled separately
        }
    }

    private func handleSelectEnd(value: DragGesture.Value,
                                  config: UMGridConfig) {
        let shift = NSEvent.modifierFlags.contains(.shift)
        let t = value.translation
        let isClick = t.width.magnitude < 4 && t.height.magnitude < 4

        if isClick {
            let loc = value.location
            let col = Int(loc.x / cachedCellW)
            let row = Int(loc.y / cachedCellH)
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
/// Combines the style's parametric preset with an optional keyframe path (additive).
private func computeMotion(style: CellStyle?, path: UMMotionPath?,
                            frame: Int, phaseOffset: Int,
                            cellW: Double, cellH: Double) -> SpriteMotion {
    var m = SpriteMotion()

    // --- Parametric preset ---
    if let style, style.motionPreset != .static, style.motionPreset != .custom {
        m = computeParametric(style: style, frame: frame, phaseOffset: phaseOffset, cellW: cellW, cellH: cellH)
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

    return m
}

private func computeParametric(style: CellStyle, frame: Int, phaseOffset: Int,
                                cellW: Double, cellH: Double) -> SpriteMotion {
    guard style.motionPreset != .static, style.motionPreset != .custom
    else { return SpriteMotion() }

    let cycles = Double(frame + phaseOffset) / 60.0 * style.motionSpeed + style.motionPhase
    let θ      = cycles * 2.0 * .pi
    let amount = style.motionAmount
    var m      = SpriteMotion()

    switch style.motionPreset {
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
        m.fillOverride   = style.fillColor.rotatingHue(by: shift)
        m.strokeOverride = style.strokeColor.rotatingHue(by: shift)
    }
    return m
}

// MARK: - Frame buffer renderer (used by ImageRenderer for background-draw accumulation)

private struct FrameCapture: View {
    let existingBuffer: CGImage?
    let backgroundColor: UMColor
    let gridConfig: UMGridConfig
    let cells: [UMGridCell]
    let styles: [CellStyle]
    let motionPaths: [UMMotionPath]
    let polygons: [Polygon2D]
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

    var body: some View {
        Canvas { ctx, size in
            if let buf = existingBuffer {
                let img = ctx.resolve(Image(decorative: buf, scale: displayScale))
                ctx.draw(img, in: CGRect(origin: .zero, size: size))
            } else {
                let bg = backgroundColor
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)))
            }

            let config   = gridConfig
            let visible  = polygons.filter(\.visible)
            let fallback = polygons.isEmpty
            let half     = min(cellW, cellH)
            let styleMap = Dictionary(uniqueKeysWithValues: styles.map { ($0.id, $0) })
            let pathMap  = Dictionary(uniqueKeysWithValues: motionPaths.map { ($0.id, $0) })

            for cell in cells where cell.isDrawn {
                let r      = cell.gridIndex / config.cols
                let c      = cell.gridIndex % config.cols
                let style  = styleMap[cell.styleID]
                let path   = cell.pathID.flatMap { pathMap[$0] }
                var motion = computeMotion(style: style, path: path,
                                           frame: currentFrame,
                                           phaseOffset: cell.phaseOffset,
                                           cellW: cellW, cellH: cellH)
                if let src = colorSource,
                   let grid = colorGrid,
                   r < grid.count, c < grid[r].count {
                    applyColorMap(grid[r][c], source: src, style: style, to: &motion)
                }
                let mx = Double(c) * cellW + cellW / 2 + cell.positionOffset.dx * scaleX + motion.dx
                let my = Double(r) * cellH + cellH / 2 + cell.positionOffset.dy * scaleY + motion.dy
                let fillC   = motion.fillOverride   ?? style?.fillColor   ?? .defaultFill
                let strokeC = motion.strokeOverride ?? style?.strokeColor ?? .defaultStroke
                let strokeW = (style?.strokeWidth ?? 1.5) * strokeScale
                let mode    = style?.renderMode  ?? .filledStroked

                if fallback {
                    let rw = (cellW - 4 * strokeScale) / 2 * motion.scaleX
                    let rh = (cellH - 4 * strokeScale) / 2 * motion.scaleY
                    ctx.fill(Path(roundedRect: CGRect(x: mx-rw, y: my-rh, width: rw*2, height: rh*2),
                                  cornerRadius: 3),
                             with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
                } else {
                    let zoomX = (stretchSprites ? cellW : half) * motion.scaleX
                    let zoomY = (stretchSprites ? cellH : half) * motion.scaleY
                    for polygon in visible {
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

// MARK: - Export render helper (module-internal; used by UMVideoExporter)

@MainActor
func umRenderFrame(
    doc: UMGridDocument,
    backgroundColor: UMColor,
    polygons: [Polygon2D],
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
        existingBuffer:  backgroundDraw ? nil : accumulationBuffer,
        backgroundColor: backgroundColor,
        gridConfig:      config,
        cells:           doc.cells,
        styles:          doc.styles,
        motionPaths:     doc.paths,
        polygons:        polygons,
        stretchSprites:  stretchSprites,
        currentFrame:    frame,
        gridW: exportW, gridH: exportH,
        cellW: cellW, cellH: cellH,
        scaleX: sx, scaleY: sy,
        displayScale:    1.0,
        colorGrid:       colorGrid,
        colorSource:     doc.colorSource,
        strokeScale:     strokeScale
    ))
    renderer.scale = 1.0
    return renderer.cgImage
}

// MARK: - Transport bar

struct TransportBarView: View {
    @Environment(AppController.self) private var controller
    @State private var showTimeline = false

    var body: some View {
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
            Text("\(controller.engine.currentFrame) fr")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            // Timeline navigation (shown when states have been recorded)
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
                .help("Open timeline editor")

                Button(action: { controller.stepTimeline(forward: true) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .help("Next state")
            }

            Spacer()

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
        .sheet(isPresented: $showTimeline) {
            TimelineView()
                .environment(controller)
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
