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
        let expanded = expandedStateIDs.contains(state.id)
        return VStack(spacing: 0) {
        HStack(spacing: 8) {
            // Expand toggle
            Button {
                if expandedStateIDs.contains(state.id) {
                    expandedStateIDs.remove(state.id)
                } else {
                    expandedStateIDs.insert(state.id)
                }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
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
        .background(isActive ? Color.accentColor.opacity(0.07) : Color.clear)
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
        Canvas { ctx, size in
            guard let g = geo,
                  let shapeID = g.resolveShapeID(atFrame: previewFrame)
            else { return }

            let stateT   = g.resolveStateTransform(atFrame: previewFrame)
            let styleID  = g.resolveStyleID(atFrame: previewFrame)
            let style    = styleID.flatMap { id in controller.projectStyles.first { $0.id == id } }
                        ?? controller.projectStyles.first
            let polygons = (controller.shapePolygonMap[shapeID] ?? controller.shapePolygons)
                           .filter(\.visible)

            let zoom = min(size.width, size.height) * 0.38
            let cx   = size.width  / 2 + stateT.offsetX
            let cy   = size.height / 2 + stateT.offsetY
            let zx   = zoom * stateT.scaleX
            let zy   = zoom * stateT.scaleY
            let rot  = stateT.rotation

            let fillC   = style?.fillColor   ?? .defaultFill
            let strokeC = style?.strokeColor ?? .defaultStroke
            let strokeW = style?.strokeWidth ?? 1.5
            let mode    = style?.renderMode  ?? .filledStroked

            if polygons.isEmpty {
                let rect = CGRect(x: cx - zx, y: cy - zy, width: zx * 2, height: zy * 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4),
                         with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
            } else {
                for polygon in polygons {
                    let cgp = buildPolygonPath(polygon, cx: cx, cy: cy,
                                               zoomX: zx, zoomY: zy,
                                               scaleX: 1.0, scaleY: 1.0, rotation: rot)
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
        .frame(height: 160)
        .background(Color(white: 0.1))
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
