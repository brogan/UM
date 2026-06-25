import SwiftUI
import UMEngine

// MARK: - AnimatedGeometryEditorView

/// Editor sheet for a single UMAnimatedGeometry (Sprite Set).
/// Shows a list of states with shape picker, hold-frames field, and a preview
/// scrubber that highlights the active state at the current frame.
struct AnimatedGeometryEditorView: View {
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    let geoID: UUID
    @State private var previewFrame: Int = 0
    @State private var editingName: String = ""
    @State private var addingState: Bool = false
    @State private var expandedStateIDs: Set<UUID> = []
    @State private var isPlaying: Bool = false
    /// The state explicitly selected for editing (expand toggle sets this).
    /// When set, the preview shows onion skin and drag updates this state's offsetX/Y.
    @State private var editingStateID: UUID? = nil
    /// Base offset captured when a canvas drag begins.
    @State private var dragBaseOffset: CGSize = .zero

    private var geoIndex: Int? {
        controller.projectAnimatedGeometries.firstIndex { $0.id == geoID }
    }
    private var geo: UMAnimatedGeometry? {
        geoIndex.map { controller.projectAnimatedGeometries[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stateList
            Divider()
            previewCanvas
            Divider()
            previewScrubber
        }
        .frame(width: 400, height: 680)
        .onAppear {
            editingName = geo?.name ?? ""
        }
        .onReceive(Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()) { _ in
            guard isPlaying, let g = geo else { return }
            let total = g.totalCycleFrames
            previewFrame = (previewFrame + 1) % max(1, total)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .onSubmit { commitName() }
                .onChange(of: editingName) { commitName() }

            Spacer()

            if let g = geo {
                Picker("Loop", selection: Binding(
                    get: { g.loopMode },
                    set: { newMode in
                        guard var updated = geo else { return }
                        updated.loopMode = newMode
                        controller.updateAnimatedGeometry(updated)
                    }
                )) {
                    ForEach(UMAnimatedGeometryLoopMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - State list

    private var stateList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let g = geo {
                    let resolvedID = g.resolveShapeID(atFrame: previewFrame)
                    ForEach(Array(g.states.enumerated()), id: \.element.id) { idx, state in
                        stateRow(state: state, index: idx,
                                 isActive: state.shapeID == resolvedID,
                                 geo: g)
                        if idx < g.states.count - 1 { Divider().padding(.leading, 12) }
                    }
                }

                addStateButton
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func stateRow(state: UMAnimatedGeometryState, index: Int,
                          isActive: Bool, geo: UMAnimatedGeometry) -> some View {
        let expanded   = expandedStateIDs.contains(state.id)
        let isEditing  = editingStateID == state.id
        return VStack(spacing: 0) {
        HStack(spacing: 8) {
            // Expand toggle — also selects this state as the editing focus
            Button {
                if expandedStateIDs.contains(state.id) {
                    expandedStateIDs.remove(state.id)
                    if editingStateID == state.id { editingStateID = nil }
                } else {
                    expandedStateIDs.insert(state.id)
                    editingStateID = state.id
                    isPlaying = false
                    previewFrame = firstFrame(ofStateAt: index, in: geo)
                    dragBaseOffset = CGSize(width: state.offsetX, height: state.offsetY)
                }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(isEditing ? Color.accentColor : .secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            // Active indicator
            Circle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))

            // Shape picker
            Picker("Shape", selection: Binding(
                get: { state.shapeID },
                set: { newID in updateStateShape(index: index, shapeID: newID) }
            )) {
                ForEach(controller.projectShapes) { sh in
                    Text(sh.name).tag(sh.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)

            Spacer()

            // Style override picker
            Picker("Style", selection: Binding(
                get: { state.styleID },
                set: { newID in updateStateStyle(index: index, styleID: newID) }
            )) {
                Text("–").tag(UUID?.none)
                ForEach(controller.projectStyles) { st in
                    Text(st.name).tag(Optional(st.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 90)

            // Hold frames
            HStack(spacing: 2) {
                Text("Hold").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("", value: Binding(
                    get: { state.holdFrames },
                    set: { updateStateHold(index: index, holdFrames: max(1, $0)) }
                ), format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 36)
            }

            // Delete
            Button {
                removeState(at: index)
            } label: {
                Image(systemName: "minus.circle").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            // Reorder
            VStack(spacing: 2) {
                Button { moveState(from: index, by: -1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 9))
                }
                .buttonStyle(.plain).disabled(index == 0)
                Button { moveState(from: index, by: 1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
                .buttonStyle(.plain).disabled(index == geo.states.count - 1)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)

        if expanded {
            transformSubRow(state: state, index: index)
        }
        } // VStack
        .background(isEditing ? Color.accentColor.opacity(0.10) : (isActive ? Color.accentColor.opacity(0.04) : Color.clear))
    }

    private var addStateButton: some View {
        HStack {
            if controller.projectShapes.isEmpty {
                Text("Import shapes to add states")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Menu {
                    ForEach(controller.projectShapes) { sh in
                        Button(sh.name) { appendState(shapeID: sh.id) }
                    }
                } label: {
                    Label("Add State", systemImage: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            Spacer()
        }
    }

    // MARK: - Preview canvas

    private var previewCanvas: some View {
        // Pre-capture all model data as value-type snapshots in main-actor context.
        // Canvas draw closures are @Sendable nonisolated, so they cannot access
        // @MainActor-isolated properties or call instance methods on self.
        let snapGeo          = geo
        let snapPolygonMap   = controller.shapePolygonMap
        let snapFallbackPolys = controller.shapePolygons
        let snapStyles       = controller.projectStyles
        let snapEditingID    = editingStateID
        let snapFrame        = previewFrame

        return VStack(spacing: 0) {
            Canvas { ctx, size in
                guard let g = snapGeo, !g.states.isEmpty else { return }

                // Determine active state index from the edit focus or current frame.
                let activeIdx: Int
                if let editID = snapEditingID,
                   let idx = g.states.firstIndex(where: { $0.id == editID }) {
                    activeIdx = idx
                } else {
                    let fwd = g.totalForwardFrames
                    let f   = fwd > 0 ? ((snapFrame % fwd) + fwd) % fwd : 0
                    var cursor = 0
                    var found  = max(0, g.states.count - 1)
                    for (i, st) in g.states.enumerated() {
                        cursor += max(1, st.holdFrames)
                        if f < cursor { found = i; break }
                    }
                    activeIdx = found
                }
                guard g.states.indices.contains(activeIdx) else { return }
                let activeState = g.states[activeIdx]

                // Bounding-box fit zoom using active state's polygon extents.
                let fitPolys = (snapPolygonMap[activeState.shapeID] ?? snapFallbackPolys).filter(\.visible)
                var minX = Double.infinity, maxX = -Double.infinity
                var minY = Double.infinity, maxY = -Double.infinity
                for poly in fitPolys { for pt in poly.points {
                    minX = min(minX, pt.x); maxX = max(maxX, pt.x)
                    minY = min(minY, pt.y); maxY = max(maxY, pt.y)
                }}
                let fitZoom: Double
                let shapeCX: Double
                let shapeCY: Double
                if maxX > minX && maxY > minY {
                    fitZoom = min(size.width * 0.65 / (maxX - minX), size.height * 0.65 / (maxY - minY))
                    shapeCX = (minX + maxX) / 2; shapeCY = (minY + maxY) / 2
                } else {
                    fitZoom = min(size.width, size.height) * 0.38
                    shapeCX = 0; shapeCY = 0
                }

                // Onion skin ghost helper — uses only captured snapshots (no self/controller).
                func drawGhost(idx: Int, opacity: Double) {
                    guard g.states.indices.contains(idx) else { return }
                    let st = g.states[idx]
                    let ghostPolys = (snapPolygonMap[st.shapeID] ?? snapFallbackPolys).filter(\.visible)
                    let gcx = size.width  / 2 - shapeCX * fitZoom + st.offsetX
                    let gcy = size.height / 2 + shapeCY * fitZoom + st.offsetY
                    for poly in ghostPolys {
                        let cgp = buildPolygonPath(poly, cx: gcx, cy: gcy,
                                                   zoomX: fitZoom * st.scaleX, zoomY: fitZoom * st.scaleY,
                                                   scaleX: 1.0, scaleY: 1.0, rotation: st.rotation)
                        ctx.fill(Path(cgp), with: .color(Color(white: 0.45, opacity: opacity)))
                    }
                }

                // Onion skin ±1 states (only when a state is explicitly focused for editing).
                if snapEditingID != nil && g.states.count > 1 {
                    let prevIdx = (activeIdx - 1 + g.states.count) % g.states.count
                    let nextIdx = (activeIdx + 1) % g.states.count
                    if prevIdx != activeIdx { drawGhost(idx: prevIdx, opacity: 0.22) }
                    if nextIdx != activeIdx && nextIdx != prevIdx { drawGhost(idx: nextIdx, opacity: 0.22) }
                }

                // Active state at full opacity.
                let acx = size.width  / 2 - shapeCX * fitZoom + activeState.offsetX
                let acy = size.height / 2 + shapeCY * fitZoom + activeState.offsetY
                let azx = fitZoom * activeState.scaleX
                let azy = fitZoom * activeState.scaleY
                let polygons = (snapPolygonMap[activeState.shapeID] ?? snapFallbackPolys).filter(\.visible)

                let style   = activeState.styleID.flatMap { id in snapStyles.first { $0.id == id } }
                          ?? snapStyles.first
                let fillC   = style?.fillColor   ?? .defaultFill
                let strokeC = style?.strokeColor ?? .defaultStroke
                let strokeW = style?.strokeWidth ?? 1.5
                let mode    = style?.renderMode  ?? .filledStroked

                if polygons.isEmpty {
                    let rect = CGRect(x: acx - azx, y: acy - azy, width: azx * 2, height: azy * 2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 4),
                             with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
                } else {
                    for polygon in polygons {
                        let cgp = buildPolygonPath(polygon, cx: acx, cy: acy,
                                                   zoomX: azx, zoomY: azy,
                                                   scaleX: 1.0, scaleY: 1.0, rotation: activeState.rotation)
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
            // Drag updates the editing state's offsetX/Y (1:1 canvas-pixel mapping; runs on main actor).
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard let editID = editingStateID,
                              let g = geo,
                              let idx = g.states.firstIndex(where: { $0.id == editID })
                        else { return }
                        updateState(at: idx) {
                            $0.offsetX = dragBaseOffset.width  + value.translation.width
                            $0.offsetY = dragBaseOffset.height + value.translation.height
                        }
                    }
                    .onEnded { _ in
                        if let editID = editingStateID,
                           let g = geo,
                           let idx = g.states.firstIndex(where: { $0.id == editID }) {
                            let st = g.states[idx]
                            dragBaseOffset = CGSize(width: st.offsetX, height: st.offsetY)
                        }
                    }
            )
            .frame(height: 160)
            .background(Color(white: 0.82))

            // Drag hint — visible only when a state is selected for editing
            if editingStateID != nil {
                Text("drag to reposition · expand chevron to change focus state")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 3)
            }
        }
    }

    // MARK: - Preview scrubber

    private var previewScrubber: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11))
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                let total = max(1, geo?.totalCycleFrames ?? 1)
                Slider(value: Binding(
                    get: { Double(previewFrame) },
                    set: { previewFrame = Int($0); isPlaying = false }
                ), in: 0...Double(max(1, total - 1)), step: 1)

                Text("\(previewFrame)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            if let g = geo, let resolvedID = g.resolveShapeID(atFrame: previewFrame),
               let shape = controller.projectShapes.first(where: { $0.id == resolvedID }) {
                Text(shape.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Transform sub-row

    private func transformSubRow(state: UMAnimatedGeometryState, index: Int) -> some View {
        HStack(spacing: 4) {
            tField("Δx", value: state.offsetX)  { v in updateState(at: index) { $0.offsetX  = v } }
            tField("Δy", value: state.offsetY)  { v in updateState(at: index) { $0.offsetY  = v } }
            Spacer()
            tField("°",  value: state.rotation) { v in updateState(at: index) { $0.rotation = v } }
            Spacer()
            tField("Sx", value: state.scaleX)   { v in updateState(at: index) { $0.scaleX   = v } }
            tField("Sy", value: state.scaleY)   { v in updateState(at: index) { $0.scaleY   = v } }
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.bottom, 6)
    }

    private func tField(_ label: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("", value: Binding(get: { value }, set: set), format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 46)
        }
    }

    private func updateState(at index: Int, _ mutate: (inout UMAnimatedGeometryState) -> Void) {
        guard var updated = geo, updated.states.indices.contains(index) else { return }
        mutate(&updated.states[index])
        controller.updateAnimatedGeometry(updated)
    }

    // MARK: - Preview helpers

    /// First frame index of the state at position `index` in the states array.
    private func firstFrame(ofStateAt index: Int, in g: UMAnimatedGeometry) -> Int {
        g.states.prefix(index).reduce(0) { $0 + max(1, $1.holdFrames) }
    }

    // MARK: - Mutations

    private func commitName() {
        guard var updated = geo, updated.name != editingName else { return }
        updated.name = editingName
        controller.updateAnimatedGeometry(updated)
    }

    private func appendState(shapeID: UUID) {
        guard var updated = geo else { return }
        updated.states.append(UMAnimatedGeometryState(shapeID: shapeID))
        controller.updateAnimatedGeometry(updated)
    }

    private func removeState(at index: Int) {
        guard var updated = geo, updated.states.indices.contains(index) else { return }
        updated.states.remove(at: index)
        controller.updateAnimatedGeometry(updated)
    }

    private func moveState(from index: Int, by delta: Int) {
        guard var updated = geo else { return }
        let dest = index + delta
        guard updated.states.indices.contains(dest) else { return }
        updated.states.swapAt(index, dest)
        controller.updateAnimatedGeometry(updated)
    }

    private func updateStateShape(index: Int, shapeID: UUID) {
        guard var updated = geo, updated.states.indices.contains(index) else { return }
        updated.states[index].shapeID = shapeID
        controller.updateAnimatedGeometry(updated)
    }

    private func updateStateStyle(index: Int, styleID: UUID?) {
        guard var updated = geo, updated.states.indices.contains(index) else { return }
        updated.states[index].styleID = styleID
        controller.updateAnimatedGeometry(updated)
    }

    private func updateStateHold(index: Int, holdFrames: Int) {
        guard var updated = geo, updated.states.indices.contains(index) else { return }
        updated.states[index].holdFrames = holdFrames
        controller.updateAnimatedGeometry(updated)
    }
}
