import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UMEngine

struct StylePaletteView: View {
    @Environment(AppController.self) private var controller
    @State private var tab: PaletteTab = .project
    @State private var renamingLayerID: UUID? = nil

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
    }

    // MARK: - Project tab

    private var projectTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("LAYERS")

                ForEach(Array(controller.layerStates.enumerated()), id: \.element.id) { idx, ls in
                    layerRow(ls, index: idx)
                }

                Button("+ New Layer") {
                    controller.addLayer()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Divider().padding(.vertical, 4)

                sectionHeader("STYLES")

                ForEach(controller.engine.document.styles) { style in
                    projectStyleRow(style)
                }

                Button("+ New Style") {
                    let style = CellStyle(name: "Style \(controller.engine.document.styles.count + 1)")
                    controller.engine.document.styles.append(style)
                    controller.activeStyleID = style.id
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

                ForEach(controller.engine.document.shapes) { shape in
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Library tab

    private var libraryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Row views

    private func layerRow(_ ls: UMLayerState, index: Int) -> some View {
        let active = (index == controller.activeLayerIndex)
        return HStack(spacing: 5) {
            // Visibility toggle
            Button {
                ls.isVisible.toggle()
            } label: {
                Image(systemName: ls.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(ls.isVisible ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.4))
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            // Active indicator dot
            Circle()
                .fill(active ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 6, height: 6)

            // Name
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

            Spacer()

            // Opacity %
            Text("\(Int((ls.opacity * 100).rounded()))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
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
                    Button("\(pct)%") { ls.opacity = Double(pct) / 100.0 }
                }
            }
            Divider()
            Button("Delete Layer", role: .destructive) { controller.removeLayer(at: index) }
                .disabled(controller.layerStates.count <= 1)
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
            Text(style.name)
                .font(.system(size: 12))
                .lineLimit(1)
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
        .onTapGesture { controller.activeStyleID = style.id }
        .contextMenu {
            Menu("Create Variant") {
                ForEach(StyleTransform.allCases, id: \.label) { t in
                    Button(t.label) { controller.applyTransform(t, to: style.id) }
                }
            }
            Button("Save to Library") { controller.promoteStyleToLibrary(style.id) }
            Divider()
            Button("Delete Style", role: .destructive) { controller.deleteStyle(style.id) }
                .disabled(controller.engine.document.styles.count <= 1)
        }
    }

    private func projectPathRow(_ path: UMMotionPath) -> some View {
        let active = path.id == controller.activePathID
        return HStack(spacing: 6) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 9))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            Text(path.name)
                .font(.system(size: 12))
                .lineLimit(1)
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
            controller.activePathID = (controller.activePathID == path.id) ? nil : path.id
        }
        .contextMenu {
            Button("Save to Library") { controller.promotePathToLibrary(path.id) }
            Divider()
            Button("Delete Path", role: .destructive) { controller.deletePath(path.id) }
        }
    }

    private func libraryStyleRow(_ style: CellStyle) -> some View {
        let inProject = controller.engine.document.styles.contains { $0.id == style.id }
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
        let activeStyle = controller.engine.document.styles.first { $0.id == controller.activeStyleID }
        let assigned = activeStyle?.shapeIDs.contains(shape.id) ?? false
        let seqIndex = activeStyle?.shapeIDs.firstIndex(of: shape.id)
        return HStack(spacing: 6) {
            Image(systemName: "pentagon")
                .font(.system(size: 9))
                .foregroundStyle(assigned ? Color.accentColor : Color.secondary)
            Text(shape.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            if let idx = seqIndex {
                Text("\(idx + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .frame(width: 14)
            }
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
        .background(assigned ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let styleID = controller.activeStyleID else { return }
            controller.toggleShape(shape.id, inStyle: styleID)
        }
        .contextMenu {
            Button("Save to Library") { controller.promoteShapeToLibrary(shape.id) }
            Divider()
            Button("Delete Shape", role: .destructive) { controller.deleteShape(shape.id) }
        }
    }

    private func libraryShapeRow(_ shape: UMShape) -> some View {
        let inProject = controller.engine.document.shapes.contains { $0.id == shape.id }
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

private extension Color {
    static let quaternary = Color(nsColor: .quaternaryLabelColor)
}
