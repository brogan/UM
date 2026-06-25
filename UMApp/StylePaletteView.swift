import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UMEngine

struct StylePaletteView: View {
    @Environment(AppController.self) private var controller
    @State private var tab: PaletteTab = .project
    @State private var renamingLayerID:   UUID? = nil
    @State private var renamingStyleID:   UUID? = nil
    @State private var renamingMotionID:  UUID? = nil
    @State private var renamingPathID:    UUID? = nil
    @State private var renamingShapeID:   UUID? = nil
    @State private var dropTargetLayerID:    UUID? = nil
    @State private var showResampleSheet:    Bool  = false
    @State private var showGeneratePalette:  Bool  = false
    @State private var renamingPaletteID:    UUID? = nil
    @State private var editingGeoID:         UUID? = nil

    private enum PaletteTab { case project, library }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Project").tag(PaletteTab.project)
                Text("Library").tag(PaletteTab.library)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            switch tab {
            case .project: projectTab
            case .library: libraryTab
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: Binding(
            get: { editingGeoID != nil },
            set: { if !$0 { editingGeoID = nil } }
        )) {
            if let geoID = editingGeoID {
                AnimatedGeometryEditorView(geoID: geoID)
                    .environment(controller)
            }
        }
    }

    // MARK: - Project tab

    private var projectTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("LAYERS")

                ForEach(Array(controller.layerStates.enumerated()), id: \.element.id) { idx, ls in
                    layerRow(ls, index: idx)
                }

                Menu("+ New Layer") {
                    Button("Grid Layer")   { controller.addLayer() }
                    Button("Sprite Layer") { controller.addSpriteLayer() }
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                resolutionSection

                Divider().padding(.vertical, 4)

                sectionHeader("STYLES")

                ForEach(controller.projectStyles) { style in
                    projectStyleRow(style)
                }

                Button("+ New Style") {
                    let style = CellStyle(name: "Style \(controller.projectStyles.count + 1)")
                    controller.projectStyles.append(style)
                    controller.activeStyleID = style.id
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Divider().padding(.vertical, 4)

                sectionHeader("MOTIONS")

                ForEach(controller.projectMotionSets) { ms in
                    projectMotionRow(ms)
                }

                Button("+ New Motion") {
                    controller.addMotionSet()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Divider().padding(.vertical, 4)

                pathsSectionHeader

                ForEach(controller.engine.document.paths) { path in
                    projectPathRow(path)
                }

                Button("+ New Path") {
                    controller.createPath()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Divider().padding(.vertical, 4)

                sectionHeader("SHAPES")

                ForEach(controller.projectShapes) { shape in
                    projectShapeRow(shape)
                }

                Button("+ Import Shape…") {
                    importShapesFromFile()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Button("+ Import Layers as Shapes…") {
                    importShapeLayersFromFile()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 7)

                Divider().padding(.vertical, 4)

                sectionHeader("PALETTES")

                ForEach(controller.projectColorPalettes) { palette in
                    projectPaletteRow(palette)
                }

                if controller.colorMapEngine.isLoaded {
                    Button("+ Generate from Color Map…") {
                        showGeneratePalette = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .sheet(isPresented: $showGeneratePalette) {
                        GeneratePaletteSheet(isPresented: $showGeneratePalette)
                            .environment(controller)
                    }
                } else {
                    Text("Load a Color Map to generate palettes.")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }

                Divider().padding(.vertical, 4)

                sectionHeader("SPRITE SETS")

                ForEach(controller.projectAnimatedGeometries) { geo in
                    spriteSetsRow(geo)
                }

                Button("+ New Sprite Set") {
                    controller.addAnimatedGeometry()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Library tab

    private var libraryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("RESOLUTION")

                if controller.globalResolutionPresets.isEmpty {
                    Text("No presets saved.\nPromote a project preset (↑) to add one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(controller.globalResolutionPresets) { preset in
                            libraryResolutionChip(preset)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }

                Divider().padding(.vertical, 4)

                sectionHeader("STYLES")

                if controller.globalLibrary.styles.isEmpty {
                    Text("No styles saved.\nPromote a project style (↑) to add one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(controller.globalLibrary.styles) { style in
                        libraryStyleRow(style)
                    }
                }

                Divider().padding(.vertical, 4)

                sectionHeader("MOTIONS")

                if controller.globalLibrary.motionSets.isEmpty {
                    Text("No motions saved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else {
                    ForEach(controller.globalLibrary.motionSets) { ms in
                        libraryMotionRow(ms)
                    }
                }

                Divider().padding(.vertical, 4)

                sectionHeader("PATHS")

                if controller.globalLibrary.paths.isEmpty {
                    Text("No paths saved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else {
                    ForEach(controller.globalLibrary.paths) { path in
                        libraryPathRow(path)
                    }
                }

                Divider().padding(.vertical, 4)

                sectionHeader("SHAPES")

                if controller.globalShapes.isEmpty {
                    Text("No shapes saved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else {
                    ForEach(controller.globalShapes) { shape in
                        libraryShapeRow(shape)
                    }
                }

                Divider().padding(.vertical, 4)

                sectionHeader("PALETTES")

                if controller.globalLibrary.colorPalettes.isEmpty {
                    Text("No palettes saved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else {
                    ForEach(controller.globalLibrary.colorPalettes) { palette in
                        libraryPaletteRow(palette)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Row views

    private func layerRow(_ ls: UMLayerState, index: Int) -> some View {
        let active = (index == controller.activeLayerIndex)
        return VStack(alignment: .leading, spacing: 3) {
            // Row 1: visibility, active dot, name
            HStack(spacing: 5) {
                Button {
                    ls.isVisible.toggle()
                } label: {
                    Image(systemName: ls.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(ls.isVisible ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.4))
                        .frame(width: 14)
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(active ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)

                if ls.layerMode == .sprite {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                if renamingLayerID == ls.id {
                    TextField("Layer name", text: Binding(
                        get: { ls.name },
                        set: { ls.name = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { renamingLayerID = nil }
                } else {
                    Text(ls.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .onTapGesture(count: 2) { renamingLayerID = ls.id }
                }
            }

            // Row 2: opacity
            HStack(spacing: 4) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                    .help("Opacity")
                Slider(value: Binding(
                    get: { ls.opacity },
                    set: { ls.opacity = $0; ls.opacityDriver.base = $0 }
                ), in: 0...1)
                    .controlSize(.mini)
                Text("\(Int((ls.opacity * 100).rounded()))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .frame(width: 28, alignment: .trailing)
            }

            // Row 3: parallax
            HStack(spacing: 4) {
                Image(systemName: "camera")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                    .help("Parallax factor: 0 = background-fixed, 1 = full camera tracking")
                Slider(value: Binding(get: { ls.parallaxFactor }, set: { ls.parallaxFactor = $0 }), in: 0...1)
                    .controlSize(.mini)
                    .help("Parallax factor")
                Text("\(Int((ls.parallaxFactor * 100).rounded()))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? Color.accentColor.opacity(0.1) : Color.clear)
        .overlay(alignment: .top) {
            if dropTargetLayerID == ls.id {
                Color.accentColor.frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .draggable(ls.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let fromIndex = controller.layerStates.firstIndex(where: { $0.id.uuidString == idString }),
                  fromIndex != index
            else { return false }
            controller.moveLayer(from: fromIndex, to: index)
            return true
        } isTargeted: { targeted in
            dropTargetLayerID = targeted ? ls.id : nil
        }
        .onTapGesture {
            renamingLayerID = nil
            controller.selectLayer(index)
        }
        .contextMenu {
            Button("Rename") { renamingLayerID = ls.id }
            Button("Duplicate") { controller.duplicateLayer(at: index) }
            Divider()
            Menu("Opacity") {
                ForEach([100, 75, 50, 25], id: \.self) { pct in
                    Button("\(pct)%") {
                        let v = Double(pct) / 100.0
                        ls.opacity = v
                        ls.opacityDriver.base = v
                    }
                }
            }
            Divider()
            Button("Delete Layer", role: .destructive) { controller.removeLayer(at: index) }
                .disabled(controller.layerStates.count <= 1)
        }
    }

    // MARK: - Resolution section

    private static let builtInPresets: [(rows: Int, cols: Int)] = [
        (4, 4), (6, 6), (8, 8), (12, 12), (16, 16), (20, 20), (32, 32)
    ]

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("RESOLUTION")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    showResampleSheet = true
                } label: {
                    Text("Other…")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Open resample sheet for custom dimensions and resize policies")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .sheet(isPresented: $showResampleSheet) {
                ResampleSheetView(
                    currentRows: controller.engine.document.gridConfig.rows,
                    currentCols: controller.engine.document.gridConfig.cols
                )
            }

            let currentRows = controller.engine.document.gridConfig.rows
            let currentCols = controller.engine.document.gridConfig.cols

            FlowLayout(spacing: 4) {
                ForEach(Self.builtInPresets, id: \.rows) { p in
                    resolutionChip(rows: p.rows, cols: p.cols,
                                   active: currentRows == p.rows && currentCols == p.cols,
                                   removable: false)
                }
                ForEach(controller.projectResolutionPresets) { preset in
                    resolutionChip(rows: preset.rows, cols: preset.cols,
                                   active: currentRows == preset.rows && currentCols == preset.cols,
                                   removable: true,
                                   onRemove: { controller.deleteResolutionPreset(preset.id) })
                    .contextMenu {
                        let inLibrary = controller.globalResolutionPresets.contains { $0.rows == preset.rows && $0.cols == preset.cols }
                        Button("Save to Library") {
                            controller.addResolutionPreset(rows: preset.rows, cols: preset.cols, global: true)
                        }
                        .disabled(inLibrary)
                        Button("Remove", role: .destructive) {
                            controller.deleteResolutionPreset(preset.id)
                        }
                    }
                }
                Button {
                    controller.addResolutionPreset(rows: currentRows, cols: currentCols)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 20)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Save \(currentRows)×\(currentCols) as a project preset")
                .disabled(Self.builtInPresets.contains(where: { $0.rows == currentRows && $0.cols == currentCols })
                          || controller.projectResolutionPresets.contains(where: { $0.rows == currentRows && $0.cols == currentCols }))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    private func resolutionChip(rows: Int, cols: Int, active: Bool, removable: Bool,
                                 onRemove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 2) {
            Button("\(rows)×\(cols)") {
                controller.resample(toRows: rows, cols: cols)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(active ? Color.white : Color.primary)
            if removable, let remove = onRemove {
                Button { remove() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(active ? Color.white.opacity(0.7) : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(active ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Motion rows

    private func projectMotionRow(_ ms: UMMotionSet) -> some View {
        let active = ms.id == controller.activeMotionID
        return HStack(spacing: 6) {
            Image(systemName: ms.motionPreset == .static ? "minus" : "waveform")
                .font(.system(size: 9))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            if renamingMotionID == ms.id {
                TextField("Motion name", text: Binding(
                    get: { controller.projectMotionSets.first { $0.id == ms.id }?.name ?? ms.name },
                    set: { newName in
                        if let i = controller.projectMotionSets.firstIndex(where: { $0.id == ms.id }) {
                            controller.projectMotionSets[i].name = newName
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { renamingMotionID = nil }
            } else {
                Text(ms.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { renamingMotionID = ms.id }
            }
            Spacer()
            Text(ms.motionPreset.shortLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
            if ms.orderChaos > 0 {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.orange.opacity(0.6 + ms.orderChaos * 0.4))
            }
            Button {
                controller.promoteMotionSetToLibrary(ms.id)
            } label: {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Save to library")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            renamingMotionID = nil
            controller.activeMotionID = (controller.activeMotionID == ms.id) ? nil : ms.id
        }
        .contextMenu {
            Button("Rename") { renamingMotionID = ms.id }
            Button("Save to Library") { controller.promoteMotionSetToLibrary(ms.id) }
            Divider()
            Button("Delete Motion", role: .destructive) { controller.deleteMotionSet(ms.id) }
        }
    }

    private func libraryMotionRow(_ ms: UMMotionSet) -> some View {
        let inProject = controller.projectMotionSets.contains { $0.id == ms.id }
        return HStack(spacing: 6) {
            Image(systemName: ms.motionPreset == .static ? "minus" : "waveform")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(ms.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(inProject ? .secondary : .primary)
            Spacer()
            Text(ms.motionPreset.shortLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
            Button {
                controller.importMotionSetFromLibrary(ms.id)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(inProject ? Color.quaternary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inProject)
            .help(inProject ? "Already in project" : "Import to project")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from library", role: .destructive) {
                controller.removeMotionSetFromLibrary(ms.id)
            }
        }
    }

    private var pathsSectionHeader: some View {
        HStack(spacing: 0) {
            Text("PATHS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                controller.showPathOverlay.toggle()
            } label: {
                Image(systemName: controller.showPathOverlay ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(controller.showPathOverlay ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(controller.showPathOverlay ? "Hide path overlay" : "Show path overlay")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private func projectStyleRow(_ style: CellStyle) -> some View {
        let active = style.id == controller.activeStyleID
        return HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
            if renamingStyleID == style.id {
                TextField("Style name", text: Binding(
                    get: { controller.projectStyles.first { $0.id == style.id }?.name ?? style.name },
                    set: { newName in
                        if let i = controller.projectStyles.firstIndex(where: { $0.id == style.id }) {
                            controller.projectStyles[i].name = newName
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { renamingStyleID = nil }
            } else {
                Text(style.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { renamingStyleID = style.id }
            }
            Spacer()
            Button {
                controller.promoteStyleToLibrary(style.id)
            } label: {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Save to library")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { renamingStyleID = nil; controller.activeStyleID = style.id }
        .contextMenu {
            Button("Rename") { renamingStyleID = style.id }
            Menu("Create Variant") {
                ForEach(StyleTransform.allCases, id: \.label) { t in
                    Button(t.label) { controller.applyTransform(t, to: style.id) }
                }
            }
            Button("Save to Library") { controller.promoteStyleToLibrary(style.id) }
            Divider()
            Button("Delete Style", role: .destructive) { controller.deleteStyle(style.id) }
                .disabled(controller.projectStyles.count <= 1)
        }
    }

    private func projectPathRow(_ path: UMMotionPath) -> some View {
        let active = path.id == controller.activePathID
        return HStack(spacing: 6) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 9))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            if renamingPathID == path.id {
                TextField("Path name", text: Binding(
                    get: { controller.engine.document.paths.first { $0.id == path.id }?.name ?? path.name },
                    set: { newName in
                        if let i = controller.engine.document.paths.firstIndex(where: { $0.id == path.id }) {
                            controller.engine.document.paths[i].name = newName
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { renamingPathID = nil }
            } else {
                Text(path.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { renamingPathID = path.id }
            }
            Spacer()
            Text("\(path.keyframes.count) kf")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
            Button {
                controller.promotePathToLibrary(path.id)
            } label: {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Save to library")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            renamingPathID = nil
            controller.activePathID = (controller.activePathID == path.id) ? nil : path.id
        }
        .contextMenu {
            Button("Rename") { renamingPathID = path.id }
            Button("Save to Library") { controller.promotePathToLibrary(path.id) }
            Divider()
            Button("Delete Path", role: .destructive) { controller.deletePath(path.id) }
        }
    }

    private func libraryStyleRow(_ style: CellStyle) -> some View {
        let inProject = controller.projectStyles.contains { $0.id == style.id }
        return HStack(spacing: 6) {
            Circle()
                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                .frame(width: 6, height: 6)
            Text(style.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(inProject ? .secondary : .primary)
            Spacer()
            Button {
                controller.importStyleFromLibrary(style.id)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(inProject ? Color.quaternary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inProject)
            .help(inProject ? "Already in project" : "Import to project")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from library", role: .destructive) {
                controller.removeStyleFromLibrary(style.id)
            }
        }
    }

    private func libraryPathRow(_ path: UMMotionPath) -> some View {
        let inProject = controller.engine.document.paths.contains { $0.id == path.id }
        return HStack(spacing: 6) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(path.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(inProject ? .secondary : .primary)
            Spacer()
            Button {
                controller.importPathFromLibrary(path.id)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(inProject ? Color.quaternary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inProject)
            .help(inProject ? "Already in project" : "Import to project")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from library", role: .destructive) {
                controller.removePathFromLibrary(path.id)
            }
        }
    }

    private func projectShapeRow(_ shape: UMShape) -> some View {
        let active = controller.activeShapeID == shape.id
        return HStack(spacing: 6) {
            Image(systemName: "pentagon")
                .font(.system(size: 9))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            if renamingShapeID == shape.id {
                TextField("Shape name", text: Binding(
                    get: { controller.projectShapes.first { $0.id == shape.id }?.name ?? shape.name },
                    set: { newName in
                        if let i = controller.projectShapes.firstIndex(where: { $0.id == shape.id }) {
                            controller.projectShapes[i].name = newName
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { renamingShapeID = nil }
            } else {
                Text(shape.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { renamingShapeID = shape.id }
            }
            Spacer()
            Button {
                controller.promoteShapeToLibrary(shape.id)
            } label: {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Save to library")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            renamingShapeID = nil
            controller.activeShapeID = (controller.activeShapeID == shape.id) ? nil : shape.id
        }
        .contextMenu {
            Button("Rename") { renamingShapeID = shape.id }
            Button("Save to Library") { controller.promoteShapeToLibrary(shape.id) }
            Divider()
            Button("Delete Shape", role: .destructive) { controller.deleteShape(shape.id) }
        }
    }

    private func libraryShapeRow(_ shape: UMShape) -> some View {
        let inProject = controller.projectShapes.contains { $0.id == shape.id }
        return HStack(spacing: 6) {
            Image(systemName: "pentagon")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(shape.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(inProject ? .secondary : .primary)
            Spacer()
            Button {
                controller.importShapeFromLibrary(shape.id)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(inProject ? Color.quaternary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inProject)
            .help(inProject ? "Already in project" : "Import to project")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from library", role: .destructive) {
                controller.removeShapeFromLibrary(shape.id)
            }
        }
    }

    // MARK: - Palette rows

    private func projectPaletteRow(_ palette: UMColorPalette) -> some View {
        let active = controller.activeColorPaletteID == palette.id
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(active ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
                if renamingPaletteID == palette.id {
                    TextField("Palette name", text: Binding(
                        get: { palette.name },
                        set: { newName in
                            if let i = controller.projectColorPalettes.firstIndex(where: { $0.id == palette.id }) {
                                controller.projectColorPalettes[i].name = newName
                            }
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { renamingPaletteID = nil }
                } else {
                    Text(palette.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .onTapGesture(count: 2) { renamingPaletteID = palette.id }
                }
                Spacer()
                Button {
                    controller.promoteColorPaletteToLibrary(palette.id)
                } label: {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Save to library")
            }
            swatchStrip(palette.colors)
                .padding(.leading, 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            renamingPaletteID = nil
            controller.activeColorPaletteID = palette.id
        }
        .contextMenu {
            Button("Rename") { renamingPaletteID = palette.id }
            Button("Save to Library") { controller.promoteColorPaletteToLibrary(palette.id) }
            Divider()
            Button("Delete Palette", role: .destructive) { controller.deleteColorPalette(palette.id) }
        }
    }

    private func libraryResolutionChip(_ preset: AppController.UMResolutionPreset) -> some View {
        let inProject = controller.projectResolutionPresets.contains { $0.rows == preset.rows && $0.cols == preset.cols }
        return HStack(spacing: 4) {
            Text(preset.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(inProject ? Color.secondary : Color.primary)
            Button {
                controller.addResolutionPreset(rows: preset.rows, cols: preset.cols, global: false)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(inProject ? Color.quaternary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inProject)
            .help(inProject ? "Already in project" : "Import to project")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contextMenu {
            Button("Remove from library", role: .destructive) {
                controller.deleteResolutionPreset(preset.id, global: true)
            }
        }
    }

    private func libraryPaletteRow(_ palette: UMColorPalette) -> some View {
        let inProject = controller.projectColorPalettes.contains { $0.id == palette.id }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(palette.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(inProject ? .secondary : .primary)
                Spacer()
                Button {
                    controller.importColorPaletteFromLibrary(palette.id)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(inProject ? Color.quaternary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inProject)
                .help(inProject ? "Already in project" : "Import to project")
            }
            swatchStrip(palette.colors)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from library", role: .destructive) {
                controller.removeColorPaletteFromLibrary(palette.id)
            }
        }
    }

    private func swatchStrip(_ colors: [UMColor]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(colors.prefix(32).enumerated()), id: \.offset) { _, color in
                Rectangle()
                    .fill(Color(red: color.r, green: color.g, blue: color.b, opacity: color.a))
                    .frame(height: 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func importShapesFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Loom Shape"
        panel.message = "Select one or more Loom polygon set JSON files"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        let loomProjects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".loom_projects")
        if FileManager.default.fileExists(atPath: loomProjects.path) {
            panel.directoryURL = loomProjects
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { controller.importShape(from: url) }
    }

    private func importShapeLayersFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Layers as Shapes"
        panel.message = "Select a multi-layer Loom geometry file — each visible layer becomes a separate shape and a Sprite Set is created automatically."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        let loomProjects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".loom_projects")
        if FileManager.default.fileExists(atPath: loomProjects.path) {
            panel.directoryURL = loomProjects
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { controller.importShapeLayers(from: url) }
    }

    // MARK: - Sprite Sets row

    private func spriteSetsRow(_ geo: UMAnimatedGeometry) -> some View {
        let isActive = controller.activeAnimatedGeometryID == geo.id
        return HStack(spacing: 6) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 16)

            Text(geo.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)

            Spacer()

            Text("\(geo.states.count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button {
                editingGeoID = geo.id
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.activeAnimatedGeometryID = isActive ? nil : geo.id
        }
        .contextMenu {
            Button("Edit…") { editingGeoID = geo.id }
            Divider()
            Button("Delete", role: .destructive) {
                controller.removeAnimatedGeometry(id: geo.id)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }
}

// MARK: - Generate palette sheet

private struct GeneratePaletteSheet: View {
    @Environment(AppController.self) private var controller
    @Binding var isPresented: Bool

    @State private var name:         String = ""
    @State private var selectedSize: PaletteSize = .medium

    private enum PaletteSize: String, CaseIterable, Identifiable {
        case small  = "4×4  (16 colors)"
        case medium = "4×8  (32 colors)"
        case large  = "8×8  (64 colors)"
        var id: String { rawValue }
        var rows: Int { self == .large ? 8 : 4 }
        var cols: Int { self == .small ? 4 : 8 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate Color Palette")
                .font(.headline)
            HStack {
                Text("Name")
                    .frame(width: 44, alignment: .leading)
                TextField("Palette name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Size")
                    .frame(width: 44, alignment: .leading)
                Picker("", selection: $selectedSize) {
                    ForEach(PaletteSize.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Generate") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    let label = n.isEmpty ? "Palette \(controller.projectColorPalettes.count + 1)" : n
                    controller.generateColorPalette(name: label,
                                                    rows: selectedSize.rows,
                                                    cols: selectedSize.cols)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            name = "Palette \(controller.projectColorPalettes.count + 1)"
        }
    }
}

private extension Color {
    static let quaternary = Color(nsColor: .quaternaryLabelColor)
}

// Simple left-to-right wrapping layout for chip rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 200
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
