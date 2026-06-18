import SwiftUI
import Observation
import AppKit
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import UMEngine
import LoomEngine

// MARK: - Per-layer mutable state

/// In-memory state for a single composition layer. Holds the engine (document + undo stack)
/// plus layer-level properties that survive layer switching.
@Observable
@MainActor
final class UMLayerState: Identifiable {
    let id: UUID
    var name: String
    var isVisible: Bool
    var opacity: Double
    var engine: UMGridEngine
    var activeStyleID: UUID?

    init(layer: UMLayer) {
        self.id            = layer.id
        self.name          = layer.name
        self.isVisible     = layer.isVisible
        self.opacity       = layer.opacity
        self.engine        = UMGridEngine(document: layer.document)
        self.activeStyleID = layer.document.styles.first?.id
    }

    func toUMLayer() -> UMLayer {
        UMLayer(id: id, name: name, isVisible: isVisible, opacity: opacity,
                document: engine.document)
    }
}

// MARK: - App controller

@Observable
@MainActor
final class AppController {

    // MARK: Layer stack

    var layerStates: [UMLayerState] = []
    var activeLayerIndex: Int = 0

    /// The active layer's engine — always in sync via selectLayer / addLayer / read.
    /// Kept as a stored @Observable var so all existing engine.X observation chains work.
    var engine: UMGridEngine

    /// Project-level style palette — shared across all layers.
    /// didSet propagates to every layer engine so rendering always sees current styles.
    var projectStyles: [CellStyle] = [] {
        didSet {
            for ls in layerStates { ls.engine.document.styles = projectStyles }
        }
    }

    /// Switch to a layer by index, saving per-layer UI state back to the departing layer.
    func selectLayer(_ index: Int) {
        guard index >= 0, index < layerStates.count, index != activeLayerIndex else { return }
        UMLogger.shared.log("selectLayer \(activeLayerIndex)→\(index) styles:\(projectStyles.count)")
        layerStates[activeLayerIndex].activeStyleID = activeStyleID
        activeLayerIndex = index
        let layer = layerStates[index]
        engine          = layer.engine
        activeStyleID   = layer.activeStyleID
        selectedIndices = []
        activePathID    = nil
    }

    func addLayer(name: String? = nil) {
        let config = engine.document.gridConfig
        var doc    = UMGridDocument.makeDefault(rows: config.rows, cols: config.cols)
        doc.styles = projectStyles
        let label  = name ?? "Layer \(layerStates.count + 1)"
        let ls     = UMLayerState(layer: UMLayer(name: label, document: doc))
        UMLogger.shared.log("addLayer '\(label)' \(projectStyles.count) styles, total layers→\(layerStates.count + 1)")
        layerStates.append(ls)
        selectLayer(layerStates.count - 1)
        rebuildShapePolygonMap()
    }

    func removeLayer(at index: Int) {
        guard layerStates.count > 1, index >= 0, index < layerStates.count else { return }
        layerStates.remove(at: index)
        let newIndex = min(activeLayerIndex, layerStates.count - 1)
        activeLayerIndex = newIndex
        engine          = layerStates[newIndex].engine
        activeStyleID   = layerStates[newIndex].activeStyleID
        selectedIndices = []
        rebuildShapePolygonMap()
    }

    func duplicateLayer(at index: Int) {
        guard index >= 0, index < layerStates.count else { return }
        let src = layerStates[index]
        let ls  = UMLayerState(layer: UMLayer(name: src.name + " Copy",
                                              isVisible: src.isVisible,
                                              opacity: src.opacity,
                                              document: src.engine.document))
        layerStates.insert(ls, at: index + 1)
        selectLayer(index + 1)
        rebuildShapePolygonMap()
    }

    func moveLayer(from: Int, to: Int) {
        guard from != to,
              from >= 0, from < layerStates.count,
              to   >= 0, to   < layerStates.count else { return }
        let isActive = (activeLayerIndex == from)
        let layer = layerStates.remove(at: from)
        let dest  = to > from ? to - 1 : to
        layerStates.insert(layer, at: dest)
        if isActive { activeLayerIndex = dest }
    }

    // MARK: Polygons

    var shapePolygons: [Polygon2D] = []        // bundled default
    var shapePolygonMap: [UUID: [Polygon2D]] = [:]

    // MARK: Global UI state

    var activeTool: PaintTool        = .draw
    var transformMode: TransformMode = .move
    var stampPhaseOffset: Int        = 0
    var stretchSpritesToCell: Bool   = true
    var showGrid: Bool               = false
    var gridColor: UMColor           = UMColor(r: 0.5, g: 0.5, b: 0.5, a: 1)
    var gridLineWidth: Double        = 0.5
    var backgroundColor: UMColor     = UMColor(r: 1, g: 1, b: 1, a: 1)
    var isPlaying: Bool              = false
    var selectedIndices: Set<Int>    = []
    var activeStyleID: UUID?         = nil

    var currentFileURL: URL? = nil
    var globalLibrary: UMLibrary = .empty
    var globalShapes:  [UMShape] = []

    private var playbackTask: Task<Void, Never>?
    private nonisolated(unsafe) var keyMonitor: Any?

    // MARK: Init

    init() {
        let doc = UMGridDocument.makeTestGrid()
        let ls  = UMLayerState(layer: UMLayer(name: "Layer 1", document: doc))
        layerStates      = [ls]
        engine           = ls.engine
        activeLayerIndex = 0
        projectStyles    = doc.styles
        activeStyleID    = doc.styles.first?.id
        loadShapePolygons()
        rebuildShapePolygonMap()
        ensureProjectsDirectory()
        // Initialise logger (creates log file, registers exception handler)
        UMLogger.shared.logState(prefix: "init", layers: 1,
                                  styles: doc.styles.count, cells: doc.cells.count)
        loadGlobalLibrary()
        loadGlobalShapes()
        startKeyMonitor()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    private func loadShapePolygons() {
        guard let url = Bundle.main.url(forResource: "s", withExtension: "json",
                                        subdirectory: "polygonSets"),
              let geoDoc = try? EditableGeometryJSONLoader.load(url: url),
              let polygons = try? geoDoc.runtimePolygons()
        else { return }
        shapePolygons = polygons
    }

    private func rebuildShapePolygonMap() {
        var map: [UUID: [Polygon2D]] = [:]
        for ls in layerStates {
            for shape in ls.engine.document.shapes {
                guard let data  = shape.geometryJSON.data(using: .utf8),
                      let geo   = try? EditableGeometryJSONLoader.decode(from: data),
                      let polys = try? geo.runtimePolygons()
                else { continue }
                map[shape.id] = polys
            }
        }
        shapePolygonMap = map
    }

    // MARK: Accumulation buffer

    var backgroundDraw: Bool = true {
        didSet { if backgroundDraw { frameBuffer = nil } }
    }
    private(set) var frameBuffer: CGImage? = nil

    // MARK: Export settings

    var exportMultiplier: Int    = 1
    var exportScaleDrawing: Bool = true
    var exportFPS: Int           = 24
    var exportFrameCount: Int    = 96
    var isExporting: Bool        = false
    var exportProgress: Double   = 0.0

    var exportDurationSeconds: Double { Double(exportFrameCount) / Double(max(1, exportFPS)) }

    // MARK: Recording & timeline (active layer only)

    var isRecording: Bool = false
    var recordingInterval: Int = 48
    var timelinePosition: Int = -1
    private var stateFrameCount: Int = 0

    var recordingIntervalSeconds: Double {
        get { Double(recordingInterval) / 24.0 }
        set { recordingInterval = max(12, min(192, Int((newValue * 24).rounded()))) }
    }

    func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            timelinePosition = -1
            stateFrameCount  = 0
            if !isPlaying { togglePlayback() }
        } else {
            if isPlaying { togglePlayback() }
        }
    }

    func captureState() {
        let state = UMTimelineState(gridConfig: engine.document.gridConfig,
                                    cells: engine.document.cells,
                                    styles: projectStyles,
                                    holdFrames: recordingInterval)
        engine.document.timeline.append(state)
        if engine.document.timeline.count > 500 {
            engine.document.timeline.removeFirst()
        }
    }

    func navigateToState(_ index: Int) {
        let timeline = engine.document.timeline
        guard index >= 0, index < timeline.count else { return }
        let state = timeline[index]
        engine.document.gridConfig = state.gridConfig
        engine.document.cells      = state.cells
        projectStyles              = state.styles
        selectedIndices = []
        timelinePosition = index
        stateFrameCount  = 0
        if let id = activeStyleID, !projectStyles.contains(where: { $0.id == id }) {
            activeStyleID = projectStyles.first?.id
        }
    }

    func stepTimeline(forward: Bool) {
        let count = engine.document.timeline.count
        guard count > 0 else { return }
        let base = timelinePosition < 0 ? (forward ? 0 : count - 1)
                                        : (forward ? timelinePosition + 1 : timelinePosition - 1)
        navigateToState((base + count) % count)
    }

    func clearTimeline() {
        engine.document.timeline.removeAll()
        timelinePosition = -1
        stateFrameCount  = 0
    }

    func deleteTimelineState(_ index: Int) {
        guard index >= 0, index < engine.document.timeline.count else { return }
        engine.document.timeline.remove(at: index)
        if engine.document.timeline.isEmpty {
            timelinePosition = -1
        } else if timelinePosition >= engine.document.timeline.count {
            timelinePosition = engine.document.timeline.count - 1
        }
        stateFrameCount = 0
    }

    func updateFrameBuffer(_ image: CGImage?) {
        frameBuffer = image
    }

    func rewindToStart() {
        frameBuffer     = nil
        stateFrameCount = 0
        for ls in layerStates { ls.engine.seek(toFrame: 0) }
        if !engine.document.timeline.isEmpty {
            navigateToState(0)
        } else {
            timelinePosition = -1
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            if !engine.document.timeline.isEmpty && timelinePosition < 0 {
                navigateToState(0)
            }
            if timelinePosition >= 0 { stateFrameCount = 0 }
            playbackTask = Task { @MainActor [weak self] in
                while let self, !Task.isCancelled, self.isPlaying {
                    // Advance all layers in lockstep
                    for ls in self.layerStates { ls.engine.advance() }

                    if self.isRecording && self.engine.currentFrame % self.recordingInterval == 0 {
                        self.captureState()
                    }

                    if !self.isRecording && self.timelinePosition >= 0 {
                        let tl  = self.engine.document.timeline
                        guard !tl.isEmpty else { self.timelinePosition = -1; continue }
                        let idx = min(self.timelinePosition, tl.count - 1)
                        self.stateFrameCount += 1
                        if self.stateFrameCount >= tl[idx].holdFrames {
                            self.stateFrameCount = 0
                            let next = (idx + 1) % tl.count
                            self.timelinePosition = next
                            self.engine.document.gridConfig = tl[next].gridConfig
                            self.engine.document.cells      = tl[next].cells
                            self.projectStyles              = tl[next].styles
                            self.selectedIndices = []
                        }
                    }

                    try? await Task.sleep(nanoseconds: 41_666_667)
                }
            }
        } else {
            playbackTask?.cancel()
            playbackTask = nil
        }
    }

    func resample(toRows newRows: Int, cols newCols: Int) {
        engine.resample(toRows: newRows, cols: newCols)
        selectedIndices = selectedIndices.filter { $0 < newRows * newCols }
        if colorMapEngine.isLoaded {
            colorMapEngine.resample(rows: newRows, cols: newCols)
        }
    }

    var activeStyle: CellStyle? {
        guard let id = activeStyleID else { return nil }
        return projectStyles.first { $0.id == id }
    }

    // MARK: Projects directory

    static var defaultProjectsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UM Projects", isDirectory: true)
    }

    var projectsDirectory: URL {
        let stored = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
        return stored.isEmpty ? Self.defaultProjectsDirectory
                              : URL(fileURLWithPath: stored, isDirectory: true)
    }

    private func ensureProjectsDirectory() {
        let dir = projectsDirectory
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var documentTitle: String {
        guard let url = currentFileURL else { return "UM — Untitled" }
        return "UM — \(url.deletingPathExtension().lastPathComponent)"
    }

    // MARK: Save / Load

    func newDocument() {
        UMLogger.shared.log("newDocument")
        let doc = UMGridDocument.makeTestGrid()
        let ls  = UMLayerState(layer: UMLayer(name: "Layer 1", document: doc))
        layerStates      = [ls]
        engine           = ls.engine
        activeLayerIndex = 0
        projectStyles    = doc.styles
        activeStyleID    = doc.styles.first?.id
        selectedIndices  = []
        currentFileURL   = nil
        rebuildShapePolygonMap()
    }

    func saveDocument() {
        if let url = currentFileURL { write(to: url) } else { saveDocumentAs() }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.title = "Save UM Project"
        panel.directoryURL = currentFileURL?.deletingLastPathComponent() ?? projectsDirectory
        panel.nameFieldStringValue = currentFileURL?
            .deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.allowedFileTypes = ["umproj"]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.currentFileURL = url
                self?.write(to: url)
            }
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.title = "Open UM Project"
        panel.directoryURL = projectsDirectory
        panel.allowedFileTypes = ["umproj"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in self?.read(from: url) }
        }
    }

    private func write(to url: URL) {
        layerStates[activeLayerIndex].activeStyleID = activeStyleID
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let layers = layerStates.map { $0.toUMLayer() }
        guard let data = try? enc.encode(layers) else {
            UMLogger.shared.log("ERROR write(to:) encode failed")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            UMLogger.shared.log("saved \(url.lastPathComponent) \(layerStates.count)L")
        } catch {
            UMLogger.shared.log("ERROR write(to:) \(error)")
        }
    }

    private func read(from url: URL) {
        guard let data   = try? Data(contentsOf: url),
              let layers = try? JSONDecoder().decode([UMLayer].self, from: data),
              !layers.isEmpty
        else {
            UMLogger.shared.log("ERROR read(from:) decode failed \(url.lastPathComponent)")
            return
        }
        layerStates      = layers.map { UMLayerState(layer: $0) }
        activeLayerIndex = 0
        engine           = layerStates[0].engine
        // Layer 0's styles are canonical; sync to all layers (handles old files where styles diverged).
        projectStyles    = layerStates[0].engine.document.styles
        activeStyleID    = layerStates[0].activeStyleID ?? projectStyles.first?.id
        selectedIndices  = []
        currentFileURL   = url
        rebuildShapePolygonMap()
        colorMapEngine.clear()
        if let src = layerStates[0].engine.document.colorSource {
            let rows = layerStates[0].engine.document.gridConfig.rows
            let cols = layerStates[0].engine.document.gridConfig.cols
            colorMapEngine.load(url: URL(fileURLWithPath: src.filePath), rows: rows, cols: cols)
        }
        UMLogger.shared.logState(prefix: "read \(url.lastPathComponent)",
                                  layers: layerStates.count,
                                  styles: projectStyles.count,
                                  cells:  engine.document.cells.filter { $0.isDrawn }.count)
    }

    // MARK: Global library

    private static var globalLibraryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UM", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    private func loadGlobalLibrary() {
        let url = Self.globalLibraryURL
        guard let data = try? Data(contentsOf: url),
              let lib  = try? JSONDecoder().decode(UMLibrary.self, from: data)
        else { return }
        globalLibrary = lib
    }

    private func saveGlobalLibrary() {
        let url = Self.globalLibraryURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(globalLibrary) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Style transforms

    func applyTransform(_ transform: StyleTransform, to styleID: UUID) {
        guard let style = projectStyles.first(where: { $0.id == styleID }) else { return }
        let variant = style.applying(transform)
        projectStyles.append(variant)
        activeStyleID = variant.id
    }

    func deleteStyle(_ styleID: UUID) {
        guard projectStyles.count > 1 else { return }
        engine.pushUndoSnapshot()
        let fallbackID = projectStyles.first { $0.id != styleID }?.id ?? UUID()
        // Reassign cells across all layers, not just the active one.
        for ls in layerStates {
            for i in ls.engine.document.cells.indices where ls.engine.document.cells[i].styleID == styleID {
                ls.engine.document.cells[i].styleID = fallbackID
            }
        }
        projectStyles.removeAll { $0.id == styleID }
        if activeStyleID == styleID { activeStyleID = projectStyles.first?.id }
    }

    // MARK: Style library

    func promoteStyleToLibrary(_ styleID: UUID) {
        guard let style = projectStyles.first(where: { $0.id == styleID }) else { return }
        if let idx = globalLibrary.styles.firstIndex(where: { $0.id == styleID }) {
            globalLibrary.styles[idx] = style
        } else {
            globalLibrary.styles.append(style)
        }
        saveGlobalLibrary()
    }

    func importStyleFromLibrary(_ libraryStyleID: UUID) {
        guard let style = globalLibrary.styles.first(where: { $0.id == libraryStyleID }) else { return }
        guard !projectStyles.contains(where: { $0.id == libraryStyleID }) else { return }
        projectStyles.append(style)
        activeStyleID = style.id
    }

    func removeStyleFromLibrary(_ libraryStyleID: UUID) {
        globalLibrary.styles.removeAll { $0.id == libraryStyleID }
        saveGlobalLibrary()
    }

    // MARK: Path management

    var activePathID: UUID?      = nil
    var showPathOverlay: Bool    = true
    var colorMapEngine: UMColorMapEngine = UMColorMapEngine()

    var activePath: UMMotionPath? {
        guard let id = activePathID else { return nil }
        return engine.document.paths.first { $0.id == id }
    }

    func createPath() {
        let p = UMMotionPath(name: "Path \(engine.document.paths.count + 1)")
        engine.document.paths.append(p)
        activePathID = p.id
    }

    func deletePath(_ id: UUID) {
        engine.document.paths.removeAll { $0.id == id }
        for i in engine.document.cells.indices where engine.document.cells[i].pathID == id {
            engine.document.cells[i].pathID = nil
        }
        if activePathID == id { activePathID = engine.document.paths.first?.id }
    }

    func assignPathToSelection(_ pathID: UUID?) {
        guard !selectedIndices.isEmpty else { return }
        engine.pushUndoSnapshot()
        for i in selectedIndices where i < engine.document.cells.count {
            engine.document.cells[i].pathID = pathID
        }
    }

    func addKeyframe(frame: Int, to pathID: UUID) {
        guard let pi = engine.document.paths.firstIndex(where: { $0.id == pathID }) else { return }
        let path = engine.document.paths[pi]
        let (dx, dy, rot, sx, sy) = path.evaluate(atFrame: frame, cellW: 1, cellH: 1)
        let kf = PathKeyframe(frame: frame, dx: dx, dy: dy, rotation: rot, scaleX: sx, scaleY: sy)
        engine.document.paths[pi].addKeyframe(kf)
    }

    func removeKeyframe(id kfID: UUID, from pathID: UUID) {
        guard let pi = engine.document.paths.firstIndex(where: { $0.id == pathID }),
              engine.document.paths[pi].keyframes.count > 2
        else { return }
        engine.document.paths[pi].removeKeyframe(id: kfID)
    }

    // MARK: Path library

    func promotePathToLibrary(_ pathID: UUID) {
        guard let path = engine.document.paths.first(where: { $0.id == pathID }) else { return }
        if let idx = globalLibrary.paths.firstIndex(where: { $0.id == pathID }) {
            globalLibrary.paths[idx] = path
        } else {
            globalLibrary.paths.append(path)
        }
        saveGlobalLibrary()
    }

    func importPathFromLibrary(_ libraryPathID: UUID) {
        guard let path = globalLibrary.paths.first(where: { $0.id == libraryPathID }) else { return }
        guard !engine.document.paths.contains(where: { $0.id == libraryPathID }) else { return }
        engine.document.paths.append(path)
    }

    func removePathFromLibrary(_ libraryPathID: UUID) {
        globalLibrary.paths.removeAll { $0.id == libraryPathID }
        saveGlobalLibrary()
    }

    // MARK: Color map

    func loadColorSource(url: URL) {
        engine.document.colorSource = UMColorSource(filePath: url.path)
        let rows = engine.document.gridConfig.rows
        let cols = engine.document.gridConfig.cols
        colorMapEngine.load(url: url, rows: rows, cols: cols)
    }

    func clearColorSource() {
        engine.document.colorSource = nil
        colorMapEngine.clear()
    }

    // MARK: Shape management

    private static var globalShapesDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UM/shapes", isDirectory: true)
    }

    private func loadGlobalShapes() {
        let dir = Self.globalShapesDirectoryURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ).filter({ $0.pathExtension == "json" })
        else { return }
        let dec = JSONDecoder()
        globalShapes = urls
            .compactMap { try? dec.decode(UMShape.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func importShape(from url: URL) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        let name  = url.deletingPathExtension().lastPathComponent
        let shape = UMShape(name: name, sourceFilename: url.lastPathComponent, geometryJSON: raw)
        engine.document.shapes.append(shape)
        rebuildShapePolygonMap()
    }

    func deleteShape(_ id: UUID) {
        engine.document.shapes.removeAll { $0.id == id }
        var updated = projectStyles
        for i in updated.indices { updated[i].shapeIDs.removeAll { $0 == id } }
        projectStyles = updated
        rebuildShapePolygonMap()
    }

    func toggleShape(_ shapeID: UUID, inStyle styleID: UUID) {
        var updated = projectStyles
        guard let i = updated.firstIndex(where: { $0.id == styleID }) else { return }
        if let j = updated[i].shapeIDs.firstIndex(of: shapeID) {
            updated[i].shapeIDs.remove(at: j)
        } else {
            updated[i].shapeIDs.append(shapeID)
        }
        projectStyles = updated
    }

    func promoteShapeToLibrary(_ id: UUID) {
        guard let shape = engine.document.shapes.first(where: { $0.id == id }) else { return }
        let dir = Self.globalShapesDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(shape) else { return }
        try? data.write(to: url, options: .atomic)
        if let idx = globalShapes.firstIndex(where: { $0.id == id }) {
            globalShapes[idx] = shape
        } else {
            globalShapes.append(shape)
            globalShapes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func importShapeFromLibrary(_ id: UUID) {
        guard let shape = globalShapes.first(where: { $0.id == id }) else { return }
        guard !engine.document.shapes.contains(where: { $0.id == id }) else { return }
        engine.document.shapes.append(shape)
        rebuildShapePolygonMap()
    }

    func removeShapeFromLibrary(_ id: UUID) {
        let url = Self.globalShapesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        globalShapes.removeAll { $0.id == id }
    }

    // MARK: Assign style to selection

    func assignStyleToSelection(_ styleID: UUID) {
        guard !selectedIndices.isEmpty else { return }
        engine.pushUndoSnapshot()
        for i in selectedIndices where i < engine.document.cells.count {
            engine.document.cells[i].styleID = styleID
        }
    }

    // MARK: Nudge

    func nudgeSelection(dx: Double, dy: Double, isRepeat: Bool = false) {
        guard !selectedIndices.isEmpty else { return }
        if !isRepeat { engine.pushUndoSnapshot() }
        for i in selectedIndices where i < engine.document.cells.count {
            engine.document.cells[i].positionOffset.dx += dx
            engine.document.cells[i].positionOffset.dy += dy
        }
    }

    private func nudgeStep(_ shift: Bool) -> Double { shift ? 10 : 1 }

    // MARK: Keyboard

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty { return event }

            let shift = event.modifierFlags.contains(.shift)
            let rep   = event.isARepeat
            switch event.keyCode {
            case 123: nudgeSelection(dx: -nudgeStep(shift), dy:  0, isRepeat: rep); return nil
            case 124: nudgeSelection(dx:  nudgeStep(shift), dy:  0, isRepeat: rep); return nil
            case 125: nudgeSelection(dx:  0, dy:  nudgeStep(shift), isRepeat: rep); return nil
            case 126: nudgeSelection(dx:  0, dy: -nudgeStep(shift), isRepeat: rep); return nil
            default: break
            }

            guard !shift else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "d": activeTool = .draw;   return nil
            case "e": activeTool = .erase;  return nil
            case "s": activeTool = .select; return nil
            case "a": activeTool = .sample; return nil
            case "f": activeTool = .fill;   return nil
            case "n": activeTool = .nudge;  return nil
            case " ": togglePlayback();     return nil
            default:  return event
            }
        }
    }

    // MARK: Render directories

    private func rendersBaseURL() -> URL {
        if let proj = currentFileURL {
            return proj.deletingLastPathComponent().appendingPathComponent("renders")
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("UM Projects/renders")
    }

    func stillsRenderDirectory() -> URL {
        let url = rendersBaseURL().appendingPathComponent("stills")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func animationsRenderDirectory() -> URL {
        let url = rendersBaseURL().appendingPathComponent("animations")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Export

    func exportPNG() {
        let config = engine.document.gridConfig
        let m      = Double(exportMultiplier)
        let exportW     = config.canvasWidth  * m
        let exportH     = config.canvasHeight * m
        let strokeScale = exportScaleDrawing ? m : 1.0

        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? "umproject"

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.png]
        panel.nameFieldStringValue = "\(baseName)_\(f.string(from: Date())).png"
        panel.directoryURL         = stillsRenderDirectory()

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let cgImage = umRenderComposited(
                    layerStates:      self.layerStates,
                    backgroundColor:  self.backgroundColor,
                    shapePolygonMap:  self.shapePolygonMap,
                    fallbackPolygons: self.shapePolygons,
                    colorMapEngine:   self.colorMapEngine,
                    backgroundDraw:   self.backgroundDraw,
                    stretchSprites:   self.stretchSpritesToCell,
                    frame:            self.engine.currentFrame,
                    exportW:          exportW,
                    exportH:          exportH,
                    strokeScale:      strokeScale,
                    accumulationBuffer: self.backgroundDraw ? nil : self.frameBuffer
                ) else { return }

                guard let dest = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.png.identifier as CFString, 1, nil
                ) else { return }
                CGImageDestinationAddImage(dest, cgImage, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }

    func exportVideo() {
        let config      = engine.document.gridConfig
        let m           = Double(exportMultiplier)
        let exportW     = config.canvasWidth  * m
        let exportH     = config.canvasHeight * m
        let strokeScale = exportScaleDrawing ? m : 1.0

        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? "umproject"

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.movie]
        panel.nameFieldStringValue = "\(baseName)_\(f.string(from: Date())).mov"
        panel.directoryURL         = animationsRenderDirectory()

        // Capture layer snapshots so export is consistent even if user edits mid-export
        let layers   = layerStates.map { $0.toUMLayer() }
        let bg       = backgroundColor
        let polyMap  = shapePolygonMap
        let polys    = shapePolygons
        let cmEngine = colorMapEngine
        let bgDraw   = backgroundDraw
        let stretch  = stretchSpritesToCell
        let fps      = exportFPS
        let frames   = exportFrameCount

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.isExporting    = true
            self.exportProgress = 0.0
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await UMVideoExporter.export(
                        layers:           layers,
                        backgroundColor:  bg,
                        shapePolygonMap:  polyMap,
                        fallbackPolygons: polys,
                        colorMapEngine:   cmEngine,
                        backgroundDraw:   bgDraw,
                        stretchSprites:   stretch,
                        frameCount:       frames,
                        fps:              fps,
                        exportW:          exportW,
                        exportH:          exportH,
                        strokeScale:      strokeScale,
                        to:               url,
                        progress:         { [weak self] p in self?.exportProgress = p }
                    )
                } catch { }
                self.isExporting = false
            }
        }
    }
}

// MARK: - Enums

enum TransformMode {
    case move
    case stamp
}

enum PaintTool: String, CaseIterable {
    case draw   = "Draw"
    case erase  = "Erase"
    case select = "Select"
    case sample = "Sample"
    case fill   = "Fill"
    case nudge  = "Nudge"

    var keyboardShortcut: String {
        switch self {
        case .draw:   return "d"
        case .erase:  return "e"
        case .select: return "s"
        case .sample: return "a"
        case .fill:   return "f"
        case .nudge:  return "n"
        }
    }
}
