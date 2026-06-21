import AppKit
import SwiftUI
import UMEngine

// MARK: - Private row model

private enum TLRowKind {
    case cameraSummary
    case cameraLane(UMCameraLane)
    case layerSummary(Int)               // layer index
    case layerLane(Int, UMTimelineLane)  // layer index, lane
    case spriteLane(Int, UUID)           // layer index, sprite ID
}

private struct TLRow {
    var kind: TLRowKind
    var y:    CGFloat  // top, relative to end of ruler area
}

// MARK: - Private selection & drag

private enum TLSelection: Hashable {
    case layer(layerIndex: Int, lane: UMTimelineLane, keyframeIdx: Int)
    case camera(lane: UMCameraLane, keyframeIdx: Int)
    case sprite(layerIndex: Int, spriteID: UUID, keyframeIdx: Int)
}

private enum TLDragKind { case none, seek, pan, layerKF, cameraKF, spriteKF, rubberBand, markerStrip, startHandle, endHandle }

private struct LayerKFHit: Equatable {
    var layerIndex: Int; var lane: UMTimelineLane; var keyframeIdx: Int
}
private struct CameraKFHit: Equatable {
    var lane: UMCameraLane; var keyframeIdx: Int
}
private struct SpriteKFHit: Equatable {
    var layerIndex: Int; var spriteID: UUID; var keyframeIdx: Int
}

private struct TLSnapshot {
    var camera: UMCamera
    var layers: [(id: UUID, opacity: UMDoubleDriver, offset: UMVectorDriver, gridScroll: UMVectorDriver,
                  sprites: [(id: UUID, positionDriver: UMVectorDriver)])]
}

// MARK: - UMTimelinePanel

struct UMTimelinePanel: View {
    @Environment(AppController.self) private var controller

    @State private var panelHeight:      CGFloat  = 200
    @State private var resizeStartH:     CGFloat? = nil
    @State private var zoom:             Double   = 4.0   // px per frame
    @State private var hOffset:          Double   = 0.0   // horizontal scroll, px
    @State private var cameraExpanded:   Bool     = false
    @State private var expandedLayers:   Set<UUID>   = []
    @State private var hiddenLanes:      Set<String> = []
    @State private var dragKind:         TLDragKind  = .none
    @State private var isDragInit:       Bool     = false
    @State private var prevDragTX:       CGFloat  = 0
    @State private var wasPlaying:       Bool     = false
    @State private var layerKFDrag:   (hit: LayerKFHit,  previewFrame: Int)? = nil
    @State private var cameraKFDrag:  (hit: CameraKFHit, previewFrame: Int)? = nil
    @State private var spriteKFDrag:  (hit: SpriteKFHit, previewFrame: Int)? = nil
    @State private var rubberStart:      CGPoint? = nil
    @State private var rubberEnd:        CGPoint? = nil
    @State private var selectedItems:    Set<TLSelection> = []
    @State private var timingScalePct:   Double = 100
    @State private var undoStack:        [TLSnapshot] = []
    @State private var selectedMarkerID: UUID?    = nil
    @State private var markerRenameText: String   = ""
    @State private var scrollMonitor:    Any?     = nil
    @State private var mouseOver:        Bool     = false

    private let headerW:    CGFloat = 160
    private let rowH:       CGFloat = 22
    private let rulerH:     CGFloat = 28
    private let markerH:    CGFloat = 18
    private let handleH:    CGFloat = 26
    private let minPanelH:  CGFloat = 80
    private let maxPanelH:  CGFloat = 600
    private let hitTol:     CGFloat = 8
    private var totalRulerH: CGFloat { markerH + rulerH }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            if !controller.isTimelineCollapsed {
                GeometryReader { outer in
                    let rows     = buildRows()
                    let contentH = totalRulerH + CGFloat(rows.count) * rowH
                    ScrollView(.vertical, showsIndicators: true) {
                        HStack(spacing: 0) {
                            headerColumn(rows: rows, contentH: contentH)
                                .frame(width: headerW, height: contentH, alignment: .top)
                            Divider()
                            GeometryReader { geo in
                                timelineCanvas(size: geo.size, rows: rows, contentH: contentH)
                                    .frame(width: geo.size.width, height: contentH)
                            }
                            .frame(height: contentH)
                        }
                        .frame(minWidth: outer.size.width, alignment: .leading)
                        .frame(height: contentH)
                    }
                }
                .frame(height: max(0, panelHeight - handleH))
                // Keyboard shortcuts
                .background(keyboardShortcutsView)
            }
        }
        .frame(height: controller.isTimelineCollapsed ? handleH : panelHeight)
        .background(Color(NSColor.controlBackgroundColor))
        .onHover { mouseOver = $0 }
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
    }

    // MARK: Keyboard shortcuts

    @ViewBuilder
    private var keyboardShortcutsView: some View {
        Group {
            Button("") { undoLastChange() }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            Button("") { deleteSelectedKeyframes() }
                .keyboardShortcut(.delete, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
            Button("") { selectAllKeyframes() }
                .keyboardShortcut("a", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            Button("") { copySelectedKeyframes() }
                .keyboardShortcut("c", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            Button("") { pasteKeyframes() }
                .keyboardShortcut("v", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
    }

    // MARK: Resize handle

    private var resizeHandle: some View {
        ZStack {
            Color(NSColor.separatorColor).frame(height: 0.5).frame(maxWidth: .infinity).frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 5) {
                Image(systemName: "chevron.up").font(.system(size: 7, weight: .semibold))
                Capsule().fill(Color.secondary.opacity(0.45)).frame(width: 48, height: 4)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(.tertiary)
        }
        .frame(height: handleH)
        .contentShape(Rectangle())
        .onHover { if $0 { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    if controller.isTimelineCollapsed {
                        controller.isTimelineCollapsed = false
                        resizeStartH = max(panelHeight, minPanelH)
                    }
                    let start = resizeStartH ?? panelHeight
                    resizeStartH = start
                    panelHeight = max(minPanelH, min(maxPanelH, start - v.translation.height))
                }
                .onEnded { _ in resizeStartH = nil }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                controller.isTimelineCollapsed.toggle()
                if !controller.isTimelineCollapsed { panelHeight = max(panelHeight, minPanelH) }
            }
        )
    }

    // MARK: Row layout

    private func buildRows() -> [TLRow] {
        var rows: [TLRow] = []
        rows.append(TLRow(kind: .cameraSummary, y: CGFloat(rows.count) * rowH))
        if cameraExpanded {
            for lane in UMCameraLane.allCases where !hiddenLanes.contains(camLaneID(lane)) {
                rows.append(TLRow(kind: .cameraLane(lane), y: CGFloat(rows.count) * rowH))
            }
        }
        for (i, ls) in controller.layerStates.enumerated() {
            rows.append(TLRow(kind: .layerSummary(i), y: CGFloat(rows.count) * rowH))
            if expandedLayers.contains(ls.id) {
                if ls.layerMode == .sprite {
                    // Sprite layers: opacity and offset apply; gridScroll does not
                    for lane in [UMTimelineLane.opacity, .offset] where !hiddenLanes.contains(layerLaneID(ls.id, lane)) {
                        rows.append(TLRow(kind: .layerLane(i, lane), y: CGFloat(rows.count) * rowH))
                    }
                    for sprite in ls.sprites where !hiddenLanes.contains(spriteLaneID(ls.id, sprite.id)) {
                        rows.append(TLRow(kind: .spriteLane(i, sprite.id), y: CGFloat(rows.count) * rowH))
                    }
                } else {
                    for lane in UMTimelineLane.allCases where !hiddenLanes.contains(layerLaneID(ls.id, lane)) {
                        rows.append(TLRow(kind: .layerLane(i, lane), y: CGFloat(rows.count) * rowH))
                    }
                }
            }
        }
        return rows
    }

    // MARK: Header column

    private func headerColumn(rows: [TLRow], contentH: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { zoom = max(1.0, zoom / 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
                Button { zoom = min(64.0, zoom * 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
                Spacer()
                // Add marker at current frame
                Button {
                    let f = controller.engine.currentFrame
                    let m = UMTimelineMarker(frame: f, name: "")
                    controller.timelineMarkers.append(m)
                    controller.timelineMarkers.sort { $0.frame < $1.frame }
                    selectedMarkerID = m.id
                    markerRenameText = ""
                } label: {
                    Image(systemName: "bookmark.fill").font(.system(size: 10)).foregroundStyle(.orange.opacity(0.8))
                }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle()).help("Add marker at current frame")
                if !selectedItems.isEmpty {
                    Button { deleteSelectedKeyframes() } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.red.opacity(0.7))
                    }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle()).help("Delete selected keyframes")
                }
            }
            .frame(height: markerH).padding(.horizontal, 6)

            // Timing-scale row (shown when ≥2 KFs selected)
            if selectedItems.count >= 2 {
                HStack(spacing: 3) {
                    Text("Scale").font(.system(size: 9)).foregroundStyle(.secondary)
                    TextField("", value: $timingScalePct,
                              format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 36)
                    Text("%").font(.system(size: 9)).foregroundStyle(.secondary)
                    Button("↔") { applyTimingScale() }
                        .font(.system(size: 10)).buttonStyle(.plain)
                        .frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                        .foregroundStyle(Color.accentColor)
                        .help("Scale selected KF timing from earliest-frame pivot")
                }
                .frame(height: markerH).padding(.horizontal, 6)
                .background(Color.accentColor.opacity(0.06))
            }

            // Marker rename row (shown below bookmark button row when marker selected)
            if let mid = selectedMarkerID,
               let idx = controller.timelineMarkers.firstIndex(where: { $0.id == mid }) {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill").font(.system(size: 9)).foregroundStyle(.orange)
                    TextField("Marker name", text: Binding(
                        get: { controller.timelineMarkers[safe: idx]?.name ?? "" },
                        set: { controller.timelineMarkers[safe: idx]?.name = $0 }
                    ))
                    .textFieldStyle(.plain).font(.system(size: 10))
                    .onSubmit { selectedMarkerID = nil }
                    Button { controller.timelineMarkers.remove(at: idx); selectedMarkerID = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.red.opacity(0.7))
                    }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                }
                .frame(height: rulerH).padding(.horizontal, 6)
                .background(Color.orange.opacity(0.07))
            } else {
                // Ruler spacer (draws nothing, canvas ruler draws the ticks)
                Color.clear.frame(height: rulerH)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                headerRow(row)
            }
            Spacer(minLength: 0)
        }
        .clipped()
    }

    @ViewBuilder
    private func headerRow(_ row: TLRow) -> some View {
        switch row.kind {
        case .cameraSummary:
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { cameraExpanded.toggle() }
                } label: {
                    Image(systemName: cameraExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).frame(width: 10)
                }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                Image(systemName: "camera").font(.system(size: 9)).foregroundStyle(.teal)
                Text("Camera").font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .frame(height: rowH).padding(.leading, 5)

        case .cameraLane(let lane):
            laneHeaderRow(label: lane.label, color: lane.color, isEnabled: camLaneEnabled(lane),
                          onHide: { hiddenLanes.insert(camLaneID(lane)) })

        case .layerSummary(let i):
            let ls = controller.layerStates[i]
            let isActive   = i == controller.activeLayerIndex
            let isExpanded = expandedLayers.contains(ls.id)
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isExpanded { expandedLayers.remove(ls.id) } else { expandedLayers.insert(ls.id) }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).frame(width: 10)
                }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(ls.name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                Spacer()
            }
            .frame(height: rowH).padding(.leading, 5)
            .background(isActive ? Color.accentColor.opacity(0.07) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { controller.selectLayer(i) }

        case .layerLane(let i, let lane):
            let ls = controller.layerStates[i]
            let isEnabled: Bool = {
                switch lane {
                case .opacity:    return ls.opacityDriver.mode    != .constant
                case .offset:     return ls.layerOffset.mode      != .constant
                case .gridScroll: return ls.gridScrollDriver.mode != .constant
                }
            }()
            laneHeaderRow(label: lane.label, color: lane.color, isEnabled: isEnabled,
                          onHide: { hiddenLanes.insert(layerLaneID(ls.id, lane)) })

        case .spriteLane(let i, let spriteID):
            let ls = controller.layerStates[i]
            let sprite = ls.sprites.first(where: { $0.id == spriteID })
            let name = sprite?.name ?? "Sprite"
            let isEnabled = sprite?.positionDriver.mode == .keyframe
            laneHeaderRow(label: "↑ \(name)", color: .purple, isEnabled: isEnabled,
                          onHide: { hiddenLanes.insert(spriteLaneID(ls.id, spriteID)) })
        }
    }

    private func laneHeaderRow(label: String, color: Color, isEnabled: Bool,
                                onHide: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 14)
            Circle().fill(color.opacity(0.55)).frame(width: 5, height: 5)
            Text(label).font(.system(size: 10)).foregroundStyle(isEnabled ? .secondary : .quaternary).lineLimit(1)
            Spacer(minLength: 2)
            Button(action: onHide) {
                Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle()).help("Hide lane")
        }
        .frame(height: rowH).padding(.horizontal, 6).padding(.leading, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
    }

    // MARK: Timeline canvas

    private func timelineCanvas(size: CGSize, rows: [TLRow], contentH: CGFloat) -> some View {
        Canvas { ctx, sz in
            drawRowBackgrounds(&ctx, size: sz, rows: rows)
            drawGrid(&ctx, size: sz)
            drawRuler(&ctx, size: sz)
            drawMarkerStrip(&ctx, size: sz)
            drawKeyframes(&ctx, size: sz, rows: rows)
            drawRubberBand(&ctx)
            drawPlayhead(&ctx, size: sz)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in onDragChanged(v, canvasWidth: size.width, rows: buildRows()) }
                .onEnded   { v in onDragEnded(v,   canvasWidth: size.width, rows: buildRows()) }
        )
        .onContinuousHover { phase in
            if case .active(let loc) = phase, hitTestRulerHandle(at: loc) != nil {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: Drawing

    private func drawRowBackgrounds(_ ctx: inout GraphicsContext, size: CGSize, rows: [TLRow]) {
        for row in rows {
            let y = totalRulerH + row.y
            let color: Color
            switch row.kind {
            case .cameraSummary:
                color = Color(NSColor.controlBackgroundColor).opacity(0.9)
            case .cameraLane:
                color = Color(NSColor.windowBackgroundColor).opacity(0.6)
            case .layerSummary(let i):
                color = i == controller.activeLayerIndex
                    ? Color.accentColor.opacity(0.06)
                    : Color(NSColor.controlBackgroundColor).opacity(0.85)
            case .layerLane:
                color = Color(NSColor.windowBackgroundColor).opacity(0.55)
            case .spriteLane:
                color = Color.purple.opacity(0.04)
            }
            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rowH)), with: .color(color))
        }
        // Horizontal separators
        var hPath = Path()
        var y = totalRulerH + rowH
        while y <= size.height {
            hPath.move(to: CGPoint(x: 0, y: y))
            hPath.addLine(to: CGPoint(x: size.width, y: y))
            y += rowH
        }
        ctx.stroke(hPath, with: .color(Color.secondary.opacity(0.12)), lineWidth: 0.5)
    }

    private func drawGrid(_ ctx: inout GraphicsContext, size: CGSize) {
        let (major, _) = tickIntervals()
        let px = CGFloat(zoom)
        let first = (Int(CGFloat(hOffset) / px) / major) * major
        let last  = Int((CGFloat(hOffset) + size.width) / px) + major
        var path = Path()
        var f = first
        while f <= last {
            let x = CGFloat(f) * px - CGFloat(hOffset)
            if x >= 0 && x <= size.width {
                path.move(to: CGPoint(x: x, y: totalRulerH))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            f += major
        }
        ctx.stroke(path, with: .color(Color.secondary.opacity(0.07)), lineWidth: 0.5)
    }

    private func drawMarkerStrip(_ ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: markerH)),
                 with: .color(Color(NSColor.windowBackgroundColor).opacity(0.8)))
        ctx.stroke(Path {
            $0.move(to: CGPoint(x: 0, y: markerH)); $0.addLine(to: CGPoint(x: size.width, y: markerH))
        }, with: .color(Color.secondary.opacity(0.12)), lineWidth: 0.5)

        let px = CGFloat(zoom)
        for marker in controller.timelineMarkers {
            let x = CGFloat(marker.frame) * px - CGFloat(hOffset)
            guard x > -20 && x < size.width + 20 else { continue }
            let isSelected = marker.id == selectedMarkerID
            let accent: Color = isSelected ? .accentColor : .orange
            // Triangle head
            ctx.fill(Path {
                $0.move(to: CGPoint(x: x, y: markerH - 1))
                $0.addLine(to: CGPoint(x: x - 5, y: 2))
                $0.addLine(to: CGPoint(x: x + 5, y: 2))
                $0.closeSubpath()
            }, with: .color(accent.opacity(isSelected ? 1.0 : 0.75)))
            // Vertical tick
            ctx.stroke(Path {
                $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: markerH))
            }, with: .color(accent.opacity(0.6)), lineWidth: 1)
            // Label (right of tick if it fits)
            if !marker.name.isEmpty {
                let labelX = x + 4
                if labelX < size.width - 4 {
                    ctx.draw(Text(marker.name)
                        .font(.system(size: 8))
                        .foregroundStyle(accent.opacity(0.9)),
                        at: CGPoint(x: labelX, y: 1), anchor: .topLeading)
                }
            }
        }
    }

    private func drawRuler(_ ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(x: 0, y: markerH, width: size.width, height: rulerH)),
                 with: .color(Color(NSColor.windowBackgroundColor)))
        let (major, minor) = tickIntervals()
        let px    = CGFloat(zoom)
        let first = (Int(CGFloat(hOffset) / px) / minor) * minor
        let last  = Int((CGFloat(hOffset) + size.width) / px) + major
        var f = first
        while f <= last {
            let x = CGFloat(f) * px - CGFloat(hOffset)
            guard x >= 0 && x <= size.width else { f += minor; continue }
            let isMajor = f % major == 0
            let tickH: CGFloat = isMajor ? 10 : 5
            ctx.stroke(Path {
                $0.move(to: CGPoint(x: x, y: totalRulerH - tickH))
                $0.addLine(to: CGPoint(x: x, y: totalRulerH))
            }, with: .color(isMajor ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.22)), lineWidth: 1)
            if isMajor {
                ctx.draw(Text("\(f)").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.secondary),
                         at: CGPoint(x: x + 2, y: totalRulerH - 12), anchor: .bottomLeading)
            }
            f += minor
        }
        ctx.stroke(Path {
            $0.move(to: CGPoint(x: 0, y: totalRulerH)); $0.addLine(to: CGPoint(x: size.width, y: totalRulerH))
        }, with: .color(Color.secondary.opacity(0.18)), lineWidth: 0.5)

        // Start/end frame handle triangles (pointing up, sitting at bottom of ruler)
        let handleY = CGFloat(markerH) + CGFloat(rulerH)
        let hSz: CGFloat = 6

        let sx = CGFloat(controller.startFrame) * px - CGFloat(hOffset)
        if sx > -hSz && sx < size.width + hSz {
            // Shaded region left of start
            if sx > 0 {
                ctx.fill(Path(CGRect(x: 0, y: markerH, width: sx, height: rulerH)),
                         with: .color(Color.secondary.opacity(0.08)))
            }
            ctx.fill(Path {
                $0.move(to: CGPoint(x: sx,      y: handleY))
                $0.addLine(to: CGPoint(x: sx - hSz, y: handleY - hSz * 1.5))
                $0.addLine(to: CGPoint(x: sx + hSz, y: handleY - hSz * 1.5))
                $0.closeSubpath()
            }, with: .color(Color.orange.opacity(0.85)))
            ctx.stroke(Path {
                $0.move(to: CGPoint(x: sx, y: markerH)); $0.addLine(to: CGPoint(x: sx, y: handleY))
            }, with: .color(Color.orange.opacity(0.55)), lineWidth: 1)
        }

        let ex = CGFloat(controller.endFrame) * px - CGFloat(hOffset)
        if ex > -hSz && ex < size.width + hSz {
            // Shaded region right of end
            if ex < size.width {
                ctx.fill(Path(CGRect(x: ex, y: markerH, width: size.width - ex, height: rulerH)),
                         with: .color(Color.secondary.opacity(0.08)))
            }
            ctx.fill(Path {
                $0.move(to: CGPoint(x: ex,      y: handleY))
                $0.addLine(to: CGPoint(x: ex - hSz, y: handleY - hSz * 1.5))
                $0.addLine(to: CGPoint(x: ex + hSz, y: handleY - hSz * 1.5))
                $0.closeSubpath()
            }, with: .color(Color.red.opacity(0.75)))
            ctx.stroke(Path {
                $0.move(to: CGPoint(x: ex, y: markerH)); $0.addLine(to: CGPoint(x: ex, y: handleY))
            }, with: .color(Color.red.opacity(0.45)), lineWidth: 1)
        }
    }

    private func drawKeyframes(_ ctx: inout GraphicsContext, size: CGSize, rows: [TLRow]) {
        let px = CGFloat(zoom)
        for row in rows {
            let midY = totalRulerH + row.y + rowH * 0.5
            switch row.kind {

            case .cameraSummary:
                let allFrames = Set(UMCameraLane.allCases.flatMap { $0.keyframeFrames(from: controller.camera) })
                for frame in allFrames {
                    let x = CGFloat(frame) * px - CGFloat(hOffset)
                    guard x > -8 && x < size.width + 8 else { continue }
                    drawDiamond(&ctx, x: x, y: midY, sz: 4.5, color: .teal, selected: false, dragging: false)
                }

            case .cameraLane(let lane):
                for (ki, frame) in lane.keyframeFrames(from: controller.camera).enumerated() {
                    let isDragging = cameraKFDrag?.hit == CameraKFHit(lane: lane, keyframeIdx: ki)
                    let isSelected = selectedItems.contains(.camera(lane: lane, keyframeIdx: ki))
                    let df = isDragging ? (cameraKFDrag?.previewFrame ?? frame) : frame
                    let x  = CGFloat(df) * px - CGFloat(hOffset)
                    guard x > -8 && x < size.width + 8 else { continue }
                    drawDiamond(&ctx, x: x, y: midY, sz: 4.0, color: lane.color,
                                selected: isSelected, dragging: isDragging)
                }

            case .layerSummary(let i):
                let ls = controller.layerStates[i]
                var allFrames = Set(ls.opacityDriver.keyframes.map(\.frame)
                                  + ls.layerOffset.keyframes.map(\.frame)
                                  + ls.gridScrollDriver.keyframes.map(\.frame))
                for sprite in ls.sprites { allFrames.formUnion(sprite.positionDriver.keyframes.map(\.frame)) }
                for frame in allFrames {
                    let x = CGFloat(frame) * px - CGFloat(hOffset)
                    guard x > -8 && x < size.width + 8 else { continue }
                    drawDiamond(&ctx, x: x, y: midY, sz: 4.5, color: .accentColor, selected: false, dragging: false)
                }

            case .layerLane(let i, let lane):
                let ls = controller.layerStates[i]
                for (ki, frame) in lane.keyframeFrames(from: ls).enumerated() {
                    let isDragging = layerKFDrag?.hit == LayerKFHit(layerIndex: i, lane: lane, keyframeIdx: ki)
                    let isSelected = selectedItems.contains(.layer(layerIndex: i, lane: lane, keyframeIdx: ki))
                    let df = isDragging ? (layerKFDrag?.previewFrame ?? frame) : frame
                    let x  = CGFloat(df) * px - CGFloat(hOffset)
                    guard x > -8 && x < size.width + 8 else { continue }
                    drawDiamond(&ctx, x: x, y: midY, sz: 4.0, color: lane.color,
                                selected: isSelected, dragging: isDragging)
                }

            case .spriteLane(let i, let spriteID):
                let ls = controller.layerStates[i]
                guard let sprite = ls.sprites.first(where: { $0.id == spriteID }) else { continue }
                for (ki, kf) in sprite.positionDriver.keyframes.enumerated() {
                    let hit = SpriteKFHit(layerIndex: i, spriteID: spriteID, keyframeIdx: ki)
                    let isDragging = spriteKFDrag?.hit == hit
                    let isSelected = selectedItems.contains(.sprite(layerIndex: i, spriteID: spriteID, keyframeIdx: ki))
                    let df = isDragging ? (spriteKFDrag?.previewFrame ?? kf.frame) : kf.frame
                    let x  = CGFloat(df) * px - CGFloat(hOffset)
                    guard x > -8 && x < size.width + 8 else { continue }
                    drawDiamond(&ctx, x: x, y: midY, sz: 4.0, color: .purple,
                                selected: isSelected, dragging: isDragging)
                }
            }
        }
    }

    private func drawPlayhead(_ ctx: inout GraphicsContext, size: CGSize) {
        let x = CGFloat(controller.engine.currentFrame) * CGFloat(zoom) - CGFloat(hOffset)
        guard x >= -1 && x <= size.width + 1 else { return }
        ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                   with: .color(Color.red.opacity(0.75)), lineWidth: 1.5)
        ctx.fill(Path {
            $0.move(to: CGPoint(x: x - 5, y: 0))
            $0.addLine(to: CGPoint(x: x + 5, y: 0))
            $0.addLine(to: CGPoint(x: x, y: 9))
            $0.closeSubpath()
        }, with: .color(Color.red.opacity(0.75)))
    }

    private func drawDiamond(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, sz: CGFloat,
                              color: Color, selected: Bool, dragging: Bool) {
        let s = dragging ? sz * 1.4 : sz
        let path = Path {
            $0.move(to:    CGPoint(x: x,     y: y - s))
            $0.addLine(to: CGPoint(x: x + s, y: y))
            $0.addLine(to: CGPoint(x: x,     y: y + s))
            $0.addLine(to: CGPoint(x: x - s, y: y))
            $0.closeSubpath()
        }
        ctx.fill(path, with: .color(color.opacity(dragging ? 1.0 : 0.85)))
        if selected {
            ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        } else if dragging {
            ctx.stroke(path, with: .color(color), lineWidth: 1.0)
        }
    }

    private func drawRubberBand(_ ctx: inout GraphicsContext) {
        guard let s = rubberStart, let e = rubberEnd,
              abs(s.x - e.x) > 2 || abs(s.y - e.y) > 2 else { return }
        let rect = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(s.x - e.x), height: abs(s.y - e.y))
        let path = Path(rect)
        ctx.fill(path, with: .color(Color.accentColor.opacity(0.1)))
        ctx.stroke(path, with: .color(Color.accentColor.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    // MARK: Hit testing

    private func rowAt(_ point: CGPoint, in rows: [TLRow]) -> TLRow? {
        let cy = point.y - totalRulerH
        guard cy >= 0 else { return nil }
        return rows.first { cy >= $0.y && cy < $0.y + rowH }
    }

    private func hitTestLayerKF(at point: CGPoint, rows: [TLRow]) -> LayerKFHit? {
        guard let row = rowAt(point, in: rows), case .layerLane(let i, let lane) = row.kind else { return nil }
        let ls = controller.layerStates[i]
        let clickFrame = Double(point.x + CGFloat(hOffset)) / zoom
        let tol = Double(hitTol) / zoom
        let frames = lane.keyframeFrames(from: ls)
        guard !frames.isEmpty,
              let (idx, _) = frames.enumerated().min(by: { abs(Double($0.element) - clickFrame) < abs(Double($1.element) - clickFrame) }),
              abs(Double(frames[idx]) - clickFrame) <= tol
        else { return nil }
        return LayerKFHit(layerIndex: i, lane: lane, keyframeIdx: idx)
    }

    private func hitTestCameraKF(at point: CGPoint, rows: [TLRow]) -> CameraKFHit? {
        guard let row = rowAt(point, in: rows), case .cameraLane(let lane) = row.kind else { return nil }
        let clickFrame = Double(point.x + CGFloat(hOffset)) / zoom
        let tol = Double(hitTol) / zoom
        let frames = lane.keyframeFrames(from: controller.camera)
        guard !frames.isEmpty,
              let (idx, _) = frames.enumerated().min(by: { abs(Double($0.element) - clickFrame) < abs(Double($1.element) - clickFrame) }),
              abs(Double(frames[idx]) - clickFrame) <= tol
        else { return nil }
        return CameraKFHit(lane: lane, keyframeIdx: idx)
    }

    private func hitTestRulerHandle(at point: CGPoint) -> TLDragKind? {
        guard point.y >= markerH && point.y <= totalRulerH else { return nil }
        let px = CGFloat(zoom)
        let tol = max(CGFloat(hitTol), 8)
        let sx = CGFloat(controller.startFrame) * px - CGFloat(hOffset)
        let ex = CGFloat(controller.endFrame)   * px - CGFloat(hOffset)
        if abs(point.x - sx) <= tol { return .startHandle }
        if abs(point.x - ex) <= tol { return .endHandle }
        return nil
    }

    private func hitTestSpriteKF(at point: CGPoint, rows: [TLRow]) -> SpriteKFHit? {
        guard let row = rowAt(point, in: rows), case .spriteLane(let i, let spriteID) = row.kind else { return nil }
        guard let ls = controller.layerStates[safe: i],
              let sprite = ls.sprites.first(where: { $0.id == spriteID }) else { return nil }
        let clickFrame = Double(point.x + CGFloat(hOffset)) / zoom
        let tol = Double(hitTol) / zoom
        let frames = sprite.positionDriver.keyframes.map(\.frame)
        guard !frames.isEmpty,
              let (idx, _) = frames.enumerated().min(by: { abs(Double($0.element) - clickFrame) < abs(Double($1.element) - clickFrame) }),
              abs(Double(frames[idx]) - clickFrame) <= tol
        else { return nil }
        return SpriteKFHit(layerIndex: i, spriteID: spriteID, keyframeIdx: idx)
    }

    // MARK: Gesture handlers

    private func onDragChanged(_ v: DragGesture.Value, canvasWidth: CGFloat, rows: [TLRow]) {
        if !isDragInit {
            isDragInit = true
            prevDragTX = 0
            if v.startLocation.y < markerH {
                dragKind = .markerStrip
            } else if let handleKind = hitTestRulerHandle(at: v.startLocation) {
                dragKind = handleKind
            } else if v.startLocation.y < totalRulerH {
                dragKind  = .seek
                wasPlaying = controller.isPlaying
                if controller.isPlaying { controller.togglePlayback() }
            } else if let hit = hitTestCameraKF(at: v.startLocation, rows: rows) {
                dragKind     = .cameraKF
                cameraKFDrag = (hit, storedCameraFrame(hit))
                tapSelectItem(.camera(lane: hit.lane, keyframeIdx: hit.keyframeIdx), additive: shiftDown)
            } else if let hit = hitTestSpriteKF(at: v.startLocation, rows: rows) {
                dragKind     = .spriteKF
                spriteKFDrag = (hit, storedSpriteFrame(hit))
                tapSelectItem(.sprite(layerIndex: hit.layerIndex, spriteID: hit.spriteID, keyframeIdx: hit.keyframeIdx), additive: shiftDown)
            } else if let hit = hitTestLayerKF(at: v.startLocation, rows: rows) {
                dragKind    = .layerKF
                layerKFDrag = (hit, storedLayerFrame(hit))
                tapSelectItem(.layer(layerIndex: hit.layerIndex, lane: hit.lane, keyframeIdx: hit.keyframeIdx), additive: shiftDown)
            } else if optionDown {
                dragKind = .pan
            } else {
                dragKind   = .rubberBand
                rubberStart = v.startLocation
                rubberEnd   = v.location
            }
        }

        switch dragKind {
        case .seek:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            controller.seekToFrame(f)
        case .layerKF:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = layerKFDrag { layerKFDrag = (s.hit, f) }
        case .cameraKF:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = cameraKFDrag { cameraKFDrag = (s.hit, f) }
        case .spriteKF:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = spriteKFDrag { spriteKFDrag = (s.hit, f) }
        case .startHandle:
            let f = max(0, min(controller.endFrame - 1,
                               Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded())))
            controller.startFrame = f
        case .endHandle:
            let f = max(controller.startFrame + 1,
                        Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            controller.endFrame = f
        case .pan:
            let delta = v.translation.width - prevDragTX
            hOffset   = max(0, hOffset - Double(delta))
            prevDragTX = v.translation.width
        case .rubberBand:
            rubberEnd = v.location
        case .markerStrip, .none: break
        }
    }

    private func onDragEnded(_ v: DragGesture.Value, canvasWidth: CGFloat, rows: [TLRow]) {
        let isTap = abs(v.translation.width) < 4 && abs(v.translation.height) < 4
        defer {
            isDragInit = false
            prevDragTX = 0
        }
        switch dragKind {
        case .seek:
            if wasPlaying { controller.togglePlayback() }
        case .layerKF:
            if !isTap, let s = layerKFDrag { commitLayerKFDrag(s) }
            if isTap { seekToKF(layerKFDrag?.previewFrame) }
            layerKFDrag = nil
        case .cameraKF:
            if !isTap, let s = cameraKFDrag { commitCameraKFDrag(s) }
            if isTap { seekToKF(cameraKFDrag?.previewFrame) }
            cameraKFDrag = nil
        case .spriteKF:
            if !isTap, let s = spriteKFDrag { commitSpriteKFDrag(s) }
            if isTap { seekToKF(spriteKFDrag?.previewFrame) }
            spriteKFDrag = nil
        case .startHandle:
            if isTap { controller.seekToFrame(controller.startFrame) }
        case .endHandle:
            if isTap { controller.seekToFrame(controller.endFrame) }
        case .pan:
            if isTap { handleTap(at: v.startLocation, rows: rows) }
        case .rubberBand:
            if isTap {
                handleTap(at: v.startLocation, rows: rows)
            } else if let s = rubberStart, let e = rubberEnd {
                let rect = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                                  width: abs(s.x - e.x), height: abs(s.y - e.y))
                selectKFsInRect(rect, rows: rows, additive: shiftDown)
            }
            rubberStart = nil; rubberEnd = nil
        case .markerStrip:
            if isTap {
                let frame = max(0, Int(Double(v.startLocation.x + CGFloat(hOffset)) / zoom + 0.5))
                handleMarkerTap(frame: frame)
            }
        case .none: break
        }
        dragKind = .none
    }

    private func handleTap(at point: CGPoint, rows: [TLRow]) {
        guard let row = rowAt(point, in: rows) else { clearSelection(); return }
        let frame = max(0, Int(Double(point.x + CGFloat(hOffset)) / zoom + 0.5))
        switch row.kind {
        case .cameraLane(let lane):
            addCameraKeyframe(lane: lane, frame: frame)
        case .layerLane(let i, let lane):
            addLayerKeyframe(layerIndex: i, lane: lane, frame: frame)
        case .spriteLane(let i, let spriteID):
            addSpriteKeyframe(layerIndex: i, spriteID: spriteID, frame: frame)
        case .layerSummary(let i):
            controller.selectLayer(i); clearSelection()
        default:
            clearSelection()
        }
    }

    private func seekToKF(_ frame: Int?) {
        if let f = frame { controller.seekToFrame(f) }
    }

    private func handleMarkerTap(frame: Int) {
        let tol = max(1, Int(Double(hitTol) / zoom))
        if let marker = controller.timelineMarkers.first(where: { abs($0.frame - frame) <= tol }) {
            // Select existing marker and seek
            selectedMarkerID = marker.id
            markerRenameText = marker.name
            controller.seekToFrame(marker.frame)
        } else {
            // Deselect
            selectedMarkerID = nil
        }
    }

    // MARK: Copy / paste

    private func copySelectedKeyframes() {
        guard !selectedItems.isEmpty else { return }
        var items: [UMKFClipboard.Item] = []
        // Find minimum frame as anchor
        var minFrame = Int.max
        for item in selectedItems {
            let f: Int
            switch item {
            case .layer(let i, let lane, let ki):
                guard let ls = controller.layerStates[safe: i] else { continue }
                f = lane.keyframeFrames(from: ls)[safe: ki] ?? 0
            case .camera(let lane, let ki):
                f = lane.keyframeFrames(from: controller.camera)[safe: ki] ?? 0
            case .sprite(let i, let spriteID, let ki):
                guard let ls = controller.layerStates[safe: i],
                      let sprite = ls.sprites.first(where: { $0.id == spriteID }) else { continue }
                f = sprite.positionDriver.keyframes[safe: ki]?.frame ?? 0
            }
            minFrame = min(minFrame, f)
        }
        guard minFrame < Int.max else { return }

        for item in selectedItems {
            switch item {
            case .layer(let i, let lane, let ki):
                guard let ls = controller.layerStates[safe: i] else { continue }
                let frames = lane.keyframeFrames(from: ls)
                guard let frame = frames[safe: ki] else { continue }
                let offset = frame - minFrame
                switch lane {
                case .opacity:
                    guard let kf = ls.opacityDriver.keyframes[safe: ki] else { continue }
                    items.append(.layerOpacity(layerIndex: i, frameOffset: offset, value: kf.value, easing: kf.easing))
                case .offset:
                    guard let kf = ls.layerOffset.keyframes[safe: ki] else { continue }
                    items.append(.layerOffset(layerIndex: i, frameOffset: offset, value: kf.value, easing: kf.easing))
                case .gridScroll:
                    guard let kf = ls.gridScrollDriver.keyframes[safe: ki] else { continue }
                    items.append(.layerGridScroll(layerIndex: i, frameOffset: offset, value: kf.value, easing: kf.easing))
                }
            case .camera(let lane, let ki):
                let frames = lane.keyframeFrames(from: controller.camera)
                guard let frame = frames[safe: ki] else { continue }
                let offset = frame - minFrame
                switch lane {
                case .pan:
                    guard let kf = controller.camera.pan.keyframes[safe: ki] else { continue }
                    items.append(.cameraPan(frameOffset: offset, value: kf.value, easing: kf.easing))
                case .zoom:
                    guard let kf = controller.camera.zoom.keyframes[safe: ki] else { continue }
                    items.append(.cameraZoom(frameOffset: offset, value: kf.value, easing: kf.easing))
                case .rotation:
                    guard let kf = controller.camera.rotation.keyframes[safe: ki] else { continue }
                    items.append(.cameraRotation(frameOffset: offset, value: kf.value, easing: kf.easing))
                }
            case .sprite(let i, let spriteID, let ki):
                guard let ls = controller.layerStates[safe: i],
                      let sprite = ls.sprites.first(where: { $0.id == spriteID }),
                      let kf = sprite.positionDriver.keyframes[safe: ki] else { continue }
                let offset = kf.frame - minFrame
                items.append(.spritePos(layerIndex: i, spriteID: spriteID, frameOffset: offset, value: kf.value, easing: kf.easing))
            }
        }
        if !items.isEmpty {
            controller.kfClipboard = UMKFClipboard(items: items, anchorFrame: minFrame)
        }
    }

    private func pasteKeyframes() {
        guard let cb = controller.kfClipboard, !cb.items.isEmpty else { return }
        recordUndo()
        let base = controller.engine.currentFrame
        clearSelection()
        for item in cb.items {
            switch item {
            case .layerOpacity(let i, let offset, let value, let easing):
                guard let ls = controller.layerStates[safe: i] else { continue }
                let f = base + offset
                ls.opacityDriver.mode = .keyframe
                ls.opacityDriver.keyframes.removeAll { $0.frame == f }
                ls.opacityDriver.keyframes.append(UMDoubleKeyframe(frame: f, value: value, easing: easing))
                ls.opacityDriver.keyframes.sort { $0.frame < $1.frame }
                if let ki = ls.opacityDriver.keyframes.firstIndex(where: { $0.frame == f }) {
                    selectedItems.insert(.layer(layerIndex: i, lane: .opacity, keyframeIdx: ki))
                }
            case .layerOffset(let i, let offset, let value, let easing):
                guard let ls = controller.layerStates[safe: i] else { continue }
                let f = base + offset
                ls.layerOffset.mode = .keyframe
                ls.layerOffset.keyframes.removeAll { $0.frame == f }
                ls.layerOffset.keyframes.append(UMVectorKeyframe(frame: f, value: value, easing: easing))
                ls.layerOffset.keyframes.sort { $0.frame < $1.frame }
                if let ki = ls.layerOffset.keyframes.firstIndex(where: { $0.frame == f }) {
                    selectedItems.insert(.layer(layerIndex: i, lane: .offset, keyframeIdx: ki))
                }
            case .layerGridScroll(let i, let offset, let value, let easing):
                guard let ls = controller.layerStates[safe: i] else { continue }
                let f = base + offset
                ls.gridScrollDriver.mode = .keyframe
                ls.gridScrollDriver.keyframes.removeAll { $0.frame == f }
                ls.gridScrollDriver.keyframes.append(UMVectorKeyframe(frame: f, value: value, easing: easing))
                ls.gridScrollDriver.keyframes.sort { $0.frame < $1.frame }
                if let ki = ls.gridScrollDriver.keyframes.firstIndex(where: { $0.frame == f }) {
                    selectedItems.insert(.layer(layerIndex: i, lane: .gridScroll, keyframeIdx: ki))
                }
            case .cameraPan(let offset, let value, let easing):
                let f = base + offset
                controller.camera.pan.mode = .keyframe
                controller.camera.pan.keyframes.removeAll { $0.frame == f }
                controller.camera.pan.keyframes.append(UMVectorKeyframe(frame: f, value: value, easing: easing))
                controller.camera.pan.keyframes.sort { $0.frame < $1.frame }
                if let ki = controller.camera.pan.keyframes.firstIndex(where: { $0.frame == f }) {
                    selectedItems.insert(.camera(lane: .pan, keyframeIdx: ki))
                }
            case .cameraZoom(let offset, let value, let easing):
                let f = base + offset
                controller.camera.zoom.mode = .keyframe
                controller.camera.zoom.keyframes.removeAll { $0.frame == f }
                controller.camera.zoom.keyframes.append(UMDoubleKeyframe(frame: f, value: value, easing: easing))
                controller.camera.zoom.keyframes.sort { $0.frame < $1.frame }
                if let ki = controller.camera.zoom.keyframes.firstIndex(where: { $0.frame == f }) {
                    selectedItems.insert(.camera(lane: .zoom, keyframeIdx: ki))
                }
            case .cameraRotation(let offset, let value, let easing):
                let f = base + offset
                controller.camera.rotation.mode = .keyframe
                controller.camera.rotation.keyframes.removeAll { $0.frame == f }
                controller.camera.rotation.keyframes.append(UMDoubleKeyframe(frame: f, value: value, easing: easing))
                controller.camera.rotation.keyframes.sort { $0.frame < $1.frame }
                if let ki = controller.camera.rotation.keyframes.firstIndex(where: { $0.frame == f }) {
                    selectedItems.insert(.camera(lane: .rotation, keyframeIdx: ki))
                }
            case .spritePos(let i, let spriteID, let offset, let value, let easing):
                guard let ls = controller.layerStates[safe: i],
                      let si = ls.sprites.firstIndex(where: { $0.id == spriteID }) else { continue }
                let f = base + offset
                ls.sprites[si].positionDriver.mode = .keyframe
                ls.sprites[si].positionDriver.keyframes.removeAll { $0.frame == f }
                ls.sprites[si].positionDriver.keyframes.append(UMVectorKeyframe(frame: f, value: value, easing: easing))
                ls.sprites[si].positionDriver.keyframes.sort { $0.frame < $1.frame }
                if let ki = ls.sprites[si].positionDriver.keyframes.firstIndex(where: { $0.frame == f }) {
                    selectedItems.insert(.sprite(layerIndex: i, spriteID: spriteID, keyframeIdx: ki))
                }
            }
        }
        syncSelectionToController()
    }

    // MARK: Keyframe mutations

    private func addLayerKeyframe(layerIndex: Int, lane: UMTimelineLane, frame: Int) {
        guard layerIndex < controller.layerStates.count else { return }
        recordUndo()
        let ls = controller.layerStates[layerIndex]
        switch lane {
        case .opacity:
            let val = DriverEvaluator.evaluate(ls.opacityDriver, frame: frame)
            var d   = ls.opacityDriver
            d.mode  = .keyframe
            d.keyframes.removeAll { $0.frame == frame }
            d.keyframes.append(UMDoubleKeyframe(frame: frame, value: val))
            d.keyframes.sort { $0.frame < $1.frame }
            ls.opacityDriver = d
        case .offset:
            let val = DriverEvaluator.evaluate(ls.layerOffset, frame: frame)
            var d   = ls.layerOffset
            d.mode  = .keyframe
            d.keyframes.removeAll { $0.frame == frame }
            d.keyframes.append(UMVectorKeyframe(frame: frame, value: val))
            d.keyframes.sort { $0.frame < $1.frame }
            ls.layerOffset = d
        case .gridScroll:
            let val = DriverEvaluator.evaluate(ls.gridScrollDriver, frame: frame)
            var d   = ls.gridScrollDriver
            d.mode  = .keyframe
            d.keyframes.removeAll { $0.frame == frame }
            d.keyframes.append(UMVectorKeyframe(frame: frame, value: val))
            d.keyframes.sort { $0.frame < $1.frame }
            ls.gridScrollDriver = d
        }
        let frames = lane.keyframeFrames(from: ls)
        if let idx = frames.firstIndex(of: frame) {
            tapSelectItem(.layer(layerIndex: layerIndex, lane: lane, keyframeIdx: idx), additive: false)
        }
        controller.seekToFrame(frame)
    }

    private func addCameraKeyframe(lane: UMCameraLane, frame: Int) {
        recordUndo()
        switch lane {
        case .pan:
            let val = DriverEvaluator.evaluate(controller.camera.pan, frame: frame)
            controller.camera.pan.mode = .keyframe
            controller.camera.pan.keyframes.removeAll { $0.frame == frame }
            controller.camera.pan.keyframes.append(UMVectorKeyframe(frame: frame, value: val))
            controller.camera.pan.keyframes.sort { $0.frame < $1.frame }
        case .zoom:
            let val = DriverEvaluator.evaluate(controller.camera.zoom, frame: frame)
            controller.camera.zoom.mode = .keyframe
            controller.camera.zoom.keyframes.removeAll { $0.frame == frame }
            controller.camera.zoom.keyframes.append(UMDoubleKeyframe(frame: frame, value: val))
            controller.camera.zoom.keyframes.sort { $0.frame < $1.frame }
        case .rotation:
            let val = DriverEvaluator.evaluate(controller.camera.rotation, frame: frame)
            controller.camera.rotation.mode = .keyframe
            controller.camera.rotation.keyframes.removeAll { $0.frame == frame }
            controller.camera.rotation.keyframes.append(UMDoubleKeyframe(frame: frame, value: val))
            controller.camera.rotation.keyframes.sort { $0.frame < $1.frame }
        }
        let frames = lane.keyframeFrames(from: controller.camera)
        if let idx = frames.firstIndex(of: frame) {
            tapSelectItem(.camera(lane: lane, keyframeIdx: idx), additive: false)
        }
        controller.seekToFrame(frame)
    }

    private func addSpriteKeyframe(layerIndex: Int, spriteID: UUID, frame: Int) {
        guard let ls = controller.layerStates[safe: layerIndex],
              let si = ls.sprites.firstIndex(where: { $0.id == spriteID }) else { return }
        recordUndo()
        let val = DriverEvaluator.evaluate(ls.sprites[si].positionDriver, frame: frame)
        var d = ls.sprites[si].positionDriver
        d.mode = .keyframe
        d.keyframes.removeAll { $0.frame == frame }
        d.keyframes.append(UMVectorKeyframe(frame: frame, value: val))
        d.keyframes.sort { $0.frame < $1.frame }
        ls.sprites[si].positionDriver = d
        if let ki = ls.sprites[si].positionDriver.keyframes.firstIndex(where: { $0.frame == frame }) {
            tapSelectItem(.sprite(layerIndex: layerIndex, spriteID: spriteID, keyframeIdx: ki), additive: false)
        }
        controller.seekToFrame(frame)
    }

    private func commitSpriteKFDrag(_ state: (hit: SpriteKFHit, previewFrame: Int)) {
        let (hit, newFrame) = (state.hit, state.previewFrame)
        guard let ls = controller.layerStates[safe: hit.layerIndex],
              let si = ls.sprites.firstIndex(where: { $0.id == hit.spriteID }),
              hit.keyframeIdx < ls.sprites[si].positionDriver.keyframes.count else { return }
        recordUndo()
        ls.sprites[si].positionDriver.keyframes[hit.keyframeIdx].frame = newFrame
        ls.sprites[si].positionDriver.keyframes.sort { $0.frame < $1.frame }
        if let ki = ls.sprites[si].positionDriver.keyframes.firstIndex(where: { $0.frame == newFrame }) {
            tapSelectItem(.sprite(layerIndex: hit.layerIndex, spriteID: hit.spriteID, keyframeIdx: ki), additive: false)
        }
        syncSelectionToController()
    }

    private func commitLayerKFDrag(_ state: (hit: LayerKFHit, previewFrame: Int)) {
        let (hit, newFrame) = (state.hit, state.previewFrame)
        guard hit.layerIndex < controller.layerStates.count else { return }
        recordUndo()
        let ls = controller.layerStates[hit.layerIndex]
        switch hit.lane {
        case .opacity:
            guard hit.keyframeIdx < ls.opacityDriver.keyframes.count else { return }
            ls.opacityDriver.keyframes[hit.keyframeIdx].frame = newFrame
            ls.opacityDriver.keyframes.sort { $0.frame < $1.frame }
        case .offset:
            guard hit.keyframeIdx < ls.layerOffset.keyframes.count else { return }
            ls.layerOffset.keyframes[hit.keyframeIdx].frame = newFrame
            ls.layerOffset.keyframes.sort { $0.frame < $1.frame }
        case .gridScroll:
            guard hit.keyframeIdx < ls.gridScrollDriver.keyframes.count else { return }
            ls.gridScrollDriver.keyframes[hit.keyframeIdx].frame = newFrame
            ls.gridScrollDriver.keyframes.sort { $0.frame < $1.frame }
        }
        let frames = hit.lane.keyframeFrames(from: ls)
        if let idx = frames.firstIndex(of: newFrame) {
            tapSelectItem(.layer(layerIndex: hit.layerIndex, lane: hit.lane, keyframeIdx: idx), additive: false)
        }
        syncSelectionToController()
    }

    private func commitCameraKFDrag(_ state: (hit: CameraKFHit, previewFrame: Int)) {
        let (hit, newFrame) = (state.hit, state.previewFrame)
        recordUndo()
        switch hit.lane {
        case .pan:
            guard hit.keyframeIdx < controller.camera.pan.keyframes.count else { return }
            controller.camera.pan.keyframes[hit.keyframeIdx].frame = newFrame
            controller.camera.pan.keyframes.sort { $0.frame < $1.frame }
        case .zoom:
            guard hit.keyframeIdx < controller.camera.zoom.keyframes.count else { return }
            controller.camera.zoom.keyframes[hit.keyframeIdx].frame = newFrame
            controller.camera.zoom.keyframes.sort { $0.frame < $1.frame }
        case .rotation:
            guard hit.keyframeIdx < controller.camera.rotation.keyframes.count else { return }
            controller.camera.rotation.keyframes[hit.keyframeIdx].frame = newFrame
            controller.camera.rotation.keyframes.sort { $0.frame < $1.frame }
        }
        let frames = hit.lane.keyframeFrames(from: controller.camera)
        if let idx = frames.firstIndex(of: newFrame) {
            tapSelectItem(.camera(lane: hit.lane, keyframeIdx: idx), additive: false)
        }
        syncSelectionToController()
    }

    private func deleteSelectedKeyframes() {
        guard !selectedItems.isEmpty else { return }
        recordUndo()
        // Collect deletions per driver, sorted in reverse so indices stay valid
        let sorted = selectedItems.sorted { a, b in
            switch (a, b) {
            case (.layer(let ai, let al, let aki), .layer(let bi, let bl, let bki)):
                if ai != bi { return ai > bi }
                if al.rawValue != bl.rawValue { return al.rawValue > bl.rawValue }
                return aki > bki
            case (.camera(let al, let aki), .camera(let bl, let bki)):
                return al == bl ? aki > bki : al.rawValue > bl.rawValue
            case (.sprite(let ai, let as_, let aki), .sprite(let bi, let bs, let bki)):
                if ai != bi { return ai > bi }
                if as_.uuidString != bs.uuidString { return as_.uuidString > bs.uuidString }
                return aki > bki
            case (.camera, .layer): return true
            case (.layer, .camera): return false
            default: return false
            }
        }
        for item in sorted {
            switch item {
            case .layer(let i, let lane, let ki):
                guard i < controller.layerStates.count else { continue }
                let ls = controller.layerStates[i]
                switch lane {
                case .opacity:
                    guard ki < ls.opacityDriver.keyframes.count else { continue }
                    ls.opacityDriver.keyframes.remove(at: ki)
                    if ls.opacityDriver.keyframes.isEmpty { ls.opacityDriver.mode = .constant }
                case .offset:
                    guard ki < ls.layerOffset.keyframes.count else { continue }
                    ls.layerOffset.keyframes.remove(at: ki)
                    if ls.layerOffset.keyframes.isEmpty { ls.layerOffset.mode = .constant }
                case .gridScroll:
                    guard ki < ls.gridScrollDriver.keyframes.count else { continue }
                    ls.gridScrollDriver.keyframes.remove(at: ki)
                    if ls.gridScrollDriver.keyframes.isEmpty { ls.gridScrollDriver.mode = .constant }
                }
            case .camera(let lane, let ki):
                switch lane {
                case .pan:
                    guard ki < controller.camera.pan.keyframes.count else { continue }
                    controller.camera.pan.keyframes.remove(at: ki)
                    if controller.camera.pan.keyframes.isEmpty { controller.camera.pan.mode = .constant }
                case .zoom:
                    guard ki < controller.camera.zoom.keyframes.count else { continue }
                    controller.camera.zoom.keyframes.remove(at: ki)
                    if controller.camera.zoom.keyframes.isEmpty { controller.camera.zoom.mode = .constant }
                case .rotation:
                    guard ki < controller.camera.rotation.keyframes.count else { continue }
                    controller.camera.rotation.keyframes.remove(at: ki)
                    if controller.camera.rotation.keyframes.isEmpty { controller.camera.rotation.mode = .constant }
                }
            case .sprite(let i, let spriteID, let ki):
                guard let ls = controller.layerStates[safe: i],
                      let si = ls.sprites.firstIndex(where: { $0.id == spriteID }),
                      ki < ls.sprites[si].positionDriver.keyframes.count else { continue }
                ls.sprites[si].positionDriver.keyframes.remove(at: ki)
                if ls.sprites[si].positionDriver.keyframes.isEmpty {
                    ls.sprites[si].positionDriver.mode = .constant
                }
            }
        }
        clearSelection()
    }

    private func applyTimingScale() {
        guard selectedItems.count >= 2, timingScalePct != 100 else { return }
        recordUndo()

        // Find pivot = earliest frame among selected KFs
        var pivotFrame = Int.max
        for item in selectedItems {
            let f: Int
            switch item {
            case .layer(let i, let lane, let ki):
                guard let ls = controller.layerStates[safe: i],
                      let frame = lane.keyframeFrames(from: ls)[safe: ki] else { continue }
                f = frame
            case .camera(let lane, let ki):
                guard let frame = lane.keyframeFrames(from: controller.camera)[safe: ki] else { continue }
                f = frame
            case .sprite(let i, let spriteID, let ki):
                guard let ls = controller.layerStates[safe: i],
                      let sprite = ls.sprites.first(where: { $0.id == spriteID }),
                      let frame = sprite.positionDriver.keyframes[safe: ki]?.frame else { continue }
                f = frame
            }
            pivotFrame = min(pivotFrame, f)
        }
        guard pivotFrame < Int.max else { return }

        let scale = timingScalePct / 100.0

        // Move each selected KF's frame — modify before re-sorting
        for item in selectedItems {
            switch item {
            case .layer(let i, let lane, let ki):
                guard let ls = controller.layerStates[safe: i] else { continue }
                switch lane {
                case .opacity:
                    guard ki < ls.opacityDriver.keyframes.count else { continue }
                    let old = ls.opacityDriver.keyframes[ki].frame
                    ls.opacityDriver.keyframes[ki].frame = pivotFrame + max(0, Int((Double(old - pivotFrame) * scale).rounded()))
                case .offset:
                    guard ki < ls.layerOffset.keyframes.count else { continue }
                    let old = ls.layerOffset.keyframes[ki].frame
                    ls.layerOffset.keyframes[ki].frame = pivotFrame + max(0, Int((Double(old - pivotFrame) * scale).rounded()))
                case .gridScroll:
                    guard ki < ls.gridScrollDriver.keyframes.count else { continue }
                    let old = ls.gridScrollDriver.keyframes[ki].frame
                    ls.gridScrollDriver.keyframes[ki].frame = pivotFrame + max(0, Int((Double(old - pivotFrame) * scale).rounded()))
                }
            case .camera(let lane, let ki):
                switch lane {
                case .pan:
                    guard ki < controller.camera.pan.keyframes.count else { continue }
                    let old = controller.camera.pan.keyframes[ki].frame
                    controller.camera.pan.keyframes[ki].frame = pivotFrame + max(0, Int((Double(old - pivotFrame) * scale).rounded()))
                case .zoom:
                    guard ki < controller.camera.zoom.keyframes.count else { continue }
                    let old = controller.camera.zoom.keyframes[ki].frame
                    controller.camera.zoom.keyframes[ki].frame = pivotFrame + max(0, Int((Double(old - pivotFrame) * scale).rounded()))
                case .rotation:
                    guard ki < controller.camera.rotation.keyframes.count else { continue }
                    let old = controller.camera.rotation.keyframes[ki].frame
                    controller.camera.rotation.keyframes[ki].frame = pivotFrame + max(0, Int((Double(old - pivotFrame) * scale).rounded()))
                }
            case .sprite(let i, let spriteID, let ki):
                guard let ls = controller.layerStates[safe: i],
                      let si = ls.sprites.firstIndex(where: { $0.id == spriteID }),
                      ki < ls.sprites[si].positionDriver.keyframes.count else { continue }
                let old = ls.sprites[si].positionDriver.keyframes[ki].frame
                ls.sprites[si].positionDriver.keyframes[ki].frame = pivotFrame + max(0, Int((Double(old - pivotFrame) * scale).rounded()))
            }
        }

        // Re-sort affected driver arrays
        let affectedLayers = Set(selectedItems.compactMap {
            if case .layer(let i, _, _) = $0 { i } else { nil }
        })
        let affectedCamLanes = Set(selectedItems.compactMap {
            if case .camera(let lane, _) = $0 { lane } else { nil }
        })
        let affectedSprites = Set(selectedItems.compactMap { item -> String? in
            if case .sprite(let i, let sid, _) = item { "\(i):\(sid.uuidString)" } else { nil }
        })
        for i in affectedLayers {
            guard let ls = controller.layerStates[safe: i] else { continue }
            ls.opacityDriver.keyframes.sort     { $0.frame < $1.frame }
            ls.layerOffset.keyframes.sort       { $0.frame < $1.frame }
            ls.gridScrollDriver.keyframes.sort  { $0.frame < $1.frame }
        }
        for lane in affectedCamLanes {
            switch lane {
            case .pan:      controller.camera.pan.keyframes.sort      { $0.frame < $1.frame }
            case .zoom:     controller.camera.zoom.keyframes.sort     { $0.frame < $1.frame }
            case .rotation: controller.camera.rotation.keyframes.sort { $0.frame < $1.frame }
            }
        }
        for key in affectedSprites {
            let parts = key.split(separator: ":")
            guard parts.count == 2, let i = Int(parts[0]), let sid = UUID(uuidString: String(parts[1])),
                  let ls = controller.layerStates[safe: i],
                  let si = ls.sprites.firstIndex(where: { $0.id == sid }) else { continue }
            ls.sprites[si].positionDriver.keyframes.sort { $0.frame < $1.frame }
        }
        clearSelection()
    }

    private func selectAllKeyframes() {
        let rows = buildRows()
        var items = Set<TLSelection>()
        for row in rows {
            switch row.kind {
            case .cameraLane(let lane):
                for (ki, _) in lane.keyframeFrames(from: controller.camera).enumerated() {
                    items.insert(.camera(lane: lane, keyframeIdx: ki))
                }
            case .layerLane(let i, let lane):
                guard i < controller.layerStates.count else { continue }
                let ls = controller.layerStates[i]
                for (ki, _) in lane.keyframeFrames(from: ls).enumerated() {
                    items.insert(.layer(layerIndex: i, lane: lane, keyframeIdx: ki))
                }
            case .spriteLane(let i, let spriteID):
                guard let ls = controller.layerStates[safe: i],
                      let sprite = ls.sprites.first(where: { $0.id == spriteID }) else { continue }
                for (ki, _) in sprite.positionDriver.keyframes.enumerated() {
                    items.insert(.sprite(layerIndex: i, spriteID: spriteID, keyframeIdx: ki))
                }
            default: break
            }
        }
        selectedItems = items
        syncSelectionToController()
    }

    // MARK: Selection

    private func tapSelectItem(_ item: TLSelection, additive: Bool) {
        if additive { selectedItems.insert(item) } else { selectedItems = [item] }
        syncSelectionToController()
    }

    private func clearSelection() {
        selectedItems.removeAll()
        controller.selectedTimelineKF = nil
        controller.selectedCameraKF   = nil
        controller.selectedSpriteKF   = nil
    }

    private func selectKFsInRect(_ rect: CGRect, rows: [TLRow], additive: Bool) {
        let px = CGFloat(zoom)
        var items = Set<TLSelection>()
        for row in rows {
            let midY = totalRulerH + row.y + rowH * 0.5
            guard midY >= rect.minY && midY <= rect.maxY else { continue }
            switch row.kind {
            case .cameraLane(let lane):
                for (ki, frame) in lane.keyframeFrames(from: controller.camera).enumerated() {
                    let x = CGFloat(frame) * px - CGFloat(hOffset)
                    if x >= rect.minX && x <= rect.maxX { items.insert(.camera(lane: lane, keyframeIdx: ki)) }
                }
            case .layerLane(let i, let lane):
                guard i < controller.layerStates.count else { continue }
                let ls = controller.layerStates[i]
                for (ki, frame) in lane.keyframeFrames(from: ls).enumerated() {
                    let x = CGFloat(frame) * px - CGFloat(hOffset)
                    if x >= rect.minX && x <= rect.maxX {
                        items.insert(.layer(layerIndex: i, lane: lane, keyframeIdx: ki))
                    }
                }
            case .spriteLane(let i, let spriteID):
                guard let ls = controller.layerStates[safe: i],
                      let sprite = ls.sprites.first(where: { $0.id == spriteID }) else { continue }
                for (ki, kf) in sprite.positionDriver.keyframes.enumerated() {
                    let x = CGFloat(kf.frame) * px - CGFloat(hOffset)
                    if x >= rect.minX && x <= rect.maxX {
                        items.insert(.sprite(layerIndex: i, spriteID: spriteID, keyframeIdx: ki))
                    }
                }
            default: break
            }
        }
        if additive { selectedItems.formUnion(items) } else { selectedItems = items }
        syncSelectionToController()
    }

    private func syncSelectionToController() {
        guard let first = selectedItems.first else {
            controller.selectedTimelineKF = nil
            controller.selectedCameraKF   = nil
            controller.selectedSpriteKF   = nil
            return
        }
        switch first {
        case .layer(let i, let lane, let ki):
            controller.selectedTimelineKF = UMTimelineKFSelection(layerIndex: i, lane: lane, keyframeIdx: ki)
            controller.selectedCameraKF   = nil
            controller.selectedSpriteKF   = nil
        case .camera(let lane, let ki):
            controller.selectedCameraKF   = UMCameraKFSelection(lane: lane, keyframeIdx: ki)
            controller.selectedTimelineKF = nil
            controller.selectedSpriteKF   = nil
        case .sprite(let i, let spriteID, let ki):
            controller.selectedSpriteKF   = UMSpriteKFSelection(layerIndex: i, spriteID: spriteID, keyframeIdx: ki)
            controller.selectedTimelineKF = nil
            controller.selectedCameraKF   = nil
        }
    }

    // MARK: Undo

    private func recordUndo() {
        let snap = TLSnapshot(
            camera: controller.camera,
            layers: controller.layerStates.map { ls in
                (id: ls.id,
                 opacity: ls.opacityDriver,
                 offset: ls.layerOffset,
                 gridScroll: ls.gridScrollDriver,
                 sprites: ls.sprites.map { (id: $0.id, positionDriver: $0.positionDriver) })
            }
        )
        undoStack.append(snap)
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
    }

    private func undoLastChange() {
        guard let snap = undoStack.popLast() else { return }
        controller.camera = snap.camera
        for item in snap.layers {
            guard let ls = controller.layerStates.first(where: { $0.id == item.id }) else { continue }
            ls.opacityDriver    = item.opacity
            ls.layerOffset      = item.offset
            ls.gridScrollDriver = item.gridScroll
            for spriteSnap in item.sprites {
                guard let si = ls.sprites.firstIndex(where: { $0.id == spriteSnap.id }) else { continue }
                ls.sprites[si].positionDriver = spriteSnap.positionDriver
            }
        }
        clearSelection()
    }

    // MARK: Helpers

    private func storedLayerFrame(_ hit: LayerKFHit) -> Int {
        guard hit.layerIndex < controller.layerStates.count else { return 0 }
        let ls = controller.layerStates[hit.layerIndex]
        let frames = hit.lane.keyframeFrames(from: ls)
        return frames.indices.contains(hit.keyframeIdx) ? frames[hit.keyframeIdx] : 0
    }

    private func storedCameraFrame(_ hit: CameraKFHit) -> Int {
        let frames = hit.lane.keyframeFrames(from: controller.camera)
        return frames.indices.contains(hit.keyframeIdx) ? frames[hit.keyframeIdx] : 0
    }

    private func camLaneEnabled(_ lane: UMCameraLane) -> Bool {
        switch lane {
        case .pan:      return controller.camera.pan.mode      != .constant
        case .zoom:     return controller.camera.zoom.mode     != .constant
        case .rotation: return controller.camera.rotation.mode != .constant
        }
    }

    private func tickIntervals() -> (major: Int, minor: Int) {
        switch zoom {
        case 20...: return (10, 1)
        case 8...:  return (10, 5)
        case 4...:  return (20, 10)
        case 2...:  return (50, 10)
        default:    return (100, 25)
        }
    }

    private func camLaneID(_ lane: UMCameraLane)                    -> String { "cam-\(lane.rawValue)" }
    private func layerLaneID(_ id: UUID, _ lane: UMTimelineLane)    -> String { "\(id)-\(lane.rawValue)" }
    private func spriteLaneID(_ layerID: UUID, _ spriteID: UUID)    -> String { "spr-\(layerID)-\(spriteID)" }

    private func storedSpriteFrame(_ hit: SpriteKFHit) -> Int {
        guard let ls = controller.layerStates[safe: hit.layerIndex],
              let sprite = ls.sprites.first(where: { $0.id == hit.spriteID }),
              sprite.positionDriver.keyframes.indices.contains(hit.keyframeIdx) else { return 0 }
        return sprite.positionDriver.keyframes[hit.keyframeIdx].frame
    }

    private var shiftDown:  Bool { NSEvent.modifierFlags.contains(.shift) }
    private var optionDown: Bool { NSEvent.modifierFlags.contains(.option) }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] ev in
            guard self.mouseOver else { return ev }
            if ev.modifierFlags.contains(.option) {
                // Option+scroll = zoom
                let delta = abs(ev.scrollingDeltaX) > abs(ev.scrollingDeltaY)
                    ? Double(ev.scrollingDeltaX) : Double(ev.scrollingDeltaY)
                let newZoom = max(1.0, min(64.0, self.zoom * (1 + delta * 0.05)))
                // Keep playhead in view during zoom
                let pivotFrame = Double(self.controller.engine.currentFrame)
                let pivotPx    = pivotFrame * self.zoom - self.hOffset
                self.zoom    = newZoom
                self.hOffset = max(0, pivotFrame * newZoom - pivotPx)
                return nil
            } else if ev.modifierFlags.isEmpty || ev.modifierFlags == [] {
                // Horizontal scroll without modifiers = pan
                let dx = Double(ev.scrollingDeltaX)
                if abs(dx) > 0.1 { self.hOffset = max(0, self.hOffset + dx); return nil }
            }
            return ev
        }
    }

    private func removeScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }
}
