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
    var selectedIndices:    Set<Int> = []
    var activeStyleID:      UUID?    = nil
    var activeMotionID:     UUID?    = nil
    var activeShapeID:      UUID?    = nil

    var currentFileURL:             URL?      = nil
    var globalLibrary:              UMLibrary = .empty
    var globalShapes:               [UMShape] = []
    var projectShapes:              [UMShape] = []
    var projectMotionSets:          [UMMotionSet] = []
    var projectResolutionPresets:   [UMResolutionPreset] = []
    var globalResolutionPresets:    [UMResolutionPreset] = []

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
        loadGlobalResolutionPresets()
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
        for shape in projectShapes {
            guard let data  = shape.geometryJSON.data(using: .utf8),
                  let geo   = try? EditableGeometryJSONLoader.decode(from: data),
                  let polys = try? geo.runtimePolygons()
            else { continue }
            map[shape.id] = polys
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
        layerStates       = [ls]
        engine            = ls.engine
        activeLayerIndex  = 0
        projectStyles             = doc.styles
        projectShapes             = []
        projectMotionSets         = []
        projectResolutionPresets  = []
        activeStyleID             = doc.styles.first?.id
        activeMotionID            = nil
        activeShapeID             = nil
        selectedIndices           = []
        currentFileURL            = nil
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
        panel.canChooseDirectories = true  // directory packages
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in self?.read(from: url) }
        }
    }

    // MARK: - Project config (directory format v3)

    struct UMResolutionPreset: Codable, Identifiable, Equatable {
        var id:   UUID
        var rows: Int
        var cols: Int
        var label: String { "\(rows)×\(cols)" }
        init(id: UUID = UUID(), rows: Int, cols: Int) { self.id = id; self.rows = rows; self.cols = cols }
    }

    private struct ProjectConfig: Codable {
        struct ShapeRecord: Codable {
            var id: UUID
            var name: String
            var sourceFilename: String
        }
        struct LayerRecord: Codable {
            var id: UUID
            var name: String
            var isVisible: Bool
            var opacity: Double
            var activeStyleID: UUID?
            var gridConfig: UMGridConfig
            var cells: [UMGridCell]
            var paths: [UMMotionPath]
            var timeline: [UMTimelineState]
            var colorSource: UMColorSource?
        }
        var version: Int
        var activeLayerIndex: Int
        var projectStyles: [CellStyle]
        var projectShapes: [ShapeRecord]
        var projectMotionSets: [UMMotionSet]
        var projectResolutionPresets: [UMResolutionPreset]
        var layers: [LayerRecord]

        enum CodingKeys: String, CodingKey {
            case version, activeLayerIndex, projectStyles, projectShapes
            case projectMotionSets, projectResolutionPresets, layers
        }

        init(version: Int, activeLayerIndex: Int, projectStyles: [CellStyle],
             projectShapes: [ShapeRecord], projectMotionSets: [UMMotionSet],
             projectResolutionPresets: [UMResolutionPreset], layers: [LayerRecord]) {
            self.version                  = version
            self.activeLayerIndex         = activeLayerIndex
            self.projectStyles            = projectStyles
            self.projectShapes            = projectShapes
            self.projectMotionSets        = projectMotionSets
            self.projectResolutionPresets = projectResolutionPresets
            self.layers                   = layers
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version              = try  c.decode(Int.self,             forKey: .version)
            activeLayerIndex     = try  c.decode(Int.self,             forKey: .activeLayerIndex)
            projectStyles        = try  c.decode([CellStyle].self,     forKey: .projectStyles)
            projectShapes        = try  c.decode([ShapeRecord].self,   forKey: .projectShapes)
            projectMotionSets        = (try? c.decodeIfPresent([UMMotionSet].self,        forKey: .projectMotionSets))        ?? []
            projectResolutionPresets = (try? c.decodeIfPresent([UMResolutionPreset].self, forKey: .projectResolutionPresets)) ?? []
            layers               = try  c.decode([LayerRecord].self,   forKey: .layers)
        }
    }

    // Decodes the motion-relevant fields that lived in CellStyle up to v2,
    // so migration can extract them into UMMotionSet objects.
    private struct LegacyCellStyle: Decodable {
        var id: UUID
        var name: String
        var motionPreset: MotionPreset
        var motionSpeed: Double
        var motionAmount: Double
        var motionPhase: Double
        var orderChaos: Double
        var framesPerStep: Int
        var shapeIDs: [UUID]

        private enum CodingKeys: String, CodingKey {
            case id, name, motionPreset, motionSpeed, motionAmount, motionPhase
            case orderChaos, framesPerStep, shapeIDs, shapeID
        }
        init(from decoder: Decoder) throws {
            let c         = try decoder.container(keyedBy: CodingKeys.self)
            id            = try c.decode(UUID.self,   forKey: .id)
            name          = try c.decode(String.self, forKey: .name)
            motionPreset  = (try? c.decodeIfPresent(MotionPreset.self, forKey: .motionPreset))  ?? .static
            motionSpeed   = (try? c.decodeIfPresent(Double.self,       forKey: .motionSpeed))   ?? 1.0
            motionAmount  = (try? c.decodeIfPresent(Double.self,       forKey: .motionAmount))  ?? 0.5
            motionPhase   = (try? c.decodeIfPresent(Double.self,       forKey: .motionPhase))   ?? 0.0
            orderChaos    = (try? c.decodeIfPresent(Double.self,       forKey: .orderChaos))    ?? 0.0
            framesPerStep = (try? c.decodeIfPresent(Int.self,          forKey: .framesPerStep)) ?? 4
            if let ids = try? c.decodeIfPresent([UUID].self, forKey: .shapeIDs) {
                shapeIDs = ids
            } else if let single = try? c.decodeIfPresent(UUID.self, forKey: .shapeID) {
                shapeIDs = [single]
            } else {
                shapeIDs = []
            }
        }
    }

    /// Derives projectMotionSets from legacy styles and patches cell motionID/shapeID.
    private static func migrateLegacyMotion(
        legacyStyles: [LegacyCellStyle],
        layerStates: inout [UMLayerState]
    ) -> [UMMotionSet] {
        // One UMMotionSet per old CellStyle that had non-static motion or shapes
        var motionSets: [UMMotionSet] = []
        var styleToMotionID: [UUID: UUID] = [:]
        var styleToShapeID:  [UUID: UUID] = [:]

        for ls in legacyStyles {
            let ms = UMMotionSet(
                name:         "\(ls.name) Motion",
                motionPreset: ls.motionPreset,
                motionSpeed:  ls.motionSpeed,
                motionAmount: ls.motionAmount,
                motionPhase:  ls.motionPhase,
                orderChaos:   ls.orderChaos,
                framesPerStep: ls.framesPerStep
            )
            motionSets.append(ms)
            styleToMotionID[ls.id] = ms.id
            styleToShapeID[ls.id]  = ls.shapeIDs.first
        }

        // Patch each cell in all layers
        for i in layerStates.indices {
            for j in layerStates[i].engine.document.cells.indices {
                let sid = layerStates[i].engine.document.cells[j].styleID
                layerStates[i].engine.document.cells[j].motionID = styleToMotionID[sid]
                layerStates[i].engine.document.cells[j].shapeID  = styleToShapeID[sid]
            }
        }
        return motionSets
    }

    private func write(to url: URL) {
        let fm = FileManager.default
        // If a legacy single-file exists at this path, remove it first.
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            try? fm.removeItem(at: url)
        }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            UMLogger.shared.log("ERROR write(to:) mkdir \(error)")
            return
        }

        // Write individual shape geometry files
        let shapesDir = url.appendingPathComponent("shapes")
        try? fm.createDirectory(at: shapesDir, withIntermediateDirectories: true)
        for shape in projectShapes {
            let dest = shapesDir.appendingPathComponent(shape.sourceFilename)
            try? shape.geometryJSON.write(to: dest, atomically: true, encoding: .utf8)
        }

        // Copy any color source files not yet inside the project (e.g. loaded before first save)
        let colorSourcesDir = url.appendingPathComponent("colorSources")
        try? fm.createDirectory(at: colorSourcesDir, withIntermediateDirectories: true)
        for li in layerStates.indices {
            guard var src = layerStates[li].engine.document.colorSource,
                  src.relativeFilePath == nil else { continue }
            let srcURL = URL(fileURLWithPath: src.filePath)
            guard fm.fileExists(atPath: srcURL.path) else { continue }
            let dest = uniqueURL(in: colorSourcesDir, for: srcURL.lastPathComponent)
            try? fm.copyItem(at: srcURL, to: dest)
            src.relativeFilePath = dest.lastPathComponent
            src.filePath         = dest.path
            layerStates[li].engine.document.colorSource = src
        }

        // Create empty render directories (mirrors Loom project layout)
        try? fm.createDirectory(at: url.appendingPathComponent("renders/animations"),
                                withIntermediateDirectories: true)
        try? fm.createDirectory(at: url.appendingPathComponent("renders/stills"),
                                withIntermediateDirectories: true)

        // Build and write config.json
        layerStates[activeLayerIndex].activeStyleID = activeStyleID
        let config = ProjectConfig(
            version: 3,
            activeLayerIndex: activeLayerIndex,
            projectStyles: projectStyles,
            projectShapes: projectShapes.map {
                ProjectConfig.ShapeRecord(id: $0.id, name: $0.name, sourceFilename: $0.sourceFilename)
            },
            projectMotionSets: projectMotionSets,
            projectResolutionPresets: projectResolutionPresets,
            layers: layerStates.map { ls in
                ProjectConfig.LayerRecord(
                    id:            ls.id,
                    name:          ls.name,
                    isVisible:     ls.isVisible,
                    opacity:       ls.opacity,
                    activeStyleID: ls.activeStyleID,
                    gridConfig:    ls.engine.document.gridConfig,
                    cells:         ls.engine.document.cells,
                    paths:         ls.engine.document.paths,
                    timeline:      ls.engine.document.timeline,
                    colorSource:   ls.engine.document.colorSource
                )
            }
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else {
            UMLogger.shared.log("ERROR write(to:) encode failed")
            return
        }
        do {
            try data.write(to: url.appendingPathComponent("config.json"), options: .atomic)
            UMLogger.shared.log("saved \(url.lastPathComponent) \(layerStates.count)L")
        } catch {
            UMLogger.shared.log("ERROR write(to:) \(error)")
        }
    }

    private func read(from url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            readPackage(at: url)
        } else {
            readLegacy(at: url)
        }
    }

    private func readPackage(at url: URL) {
        guard let data   = try? Data(contentsOf: url.appendingPathComponent("config.json")),
              let config = try? JSONDecoder().decode(ProjectConfig.self, from: data),
              !config.layers.isEmpty
        else {
            UMLogger.shared.log("ERROR readPackage decode failed \(url.lastPathComponent)")
            return
        }

        let shapesDir = url.appendingPathComponent("shapes")
        let loaded: [UMShape] = config.projectShapes.compactMap { ref in
            let fileURL = shapesDir.appendingPathComponent(ref.sourceFilename)
            guard let json = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
            return UMShape(id: ref.id, name: ref.name, sourceFilename: ref.sourceFilename, geometryJSON: json)
        }

        let styles = config.projectStyles.isEmpty ? [CellStyle(name: "Default")] : config.projectStyles
        layerStates = config.layers.map { record in
            let doc = UMGridDocument(
                gridConfig:  record.gridConfig,
                cells:       record.cells,
                styles:      styles,
                paths:       record.paths,
                shapes:      [],
                timeline:    record.timeline,
                colorSource: record.colorSource
            )
            let ls = UMLayerState(layer: UMLayer(id: record.id, name: record.name,
                                                 isVisible: record.isVisible,
                                                 opacity: record.opacity,
                                                 document: doc))
            ls.activeStyleID = record.activeStyleID ?? styles.first?.id
            return ls
        }

        let idx      = max(0, min(config.activeLayerIndex, layerStates.count - 1))
        activeLayerIndex  = idx
        engine            = layerStates[idx].engine
        projectStyles             = styles
        projectShapes             = loaded
        projectMotionSets         = config.projectMotionSets
        projectResolutionPresets  = config.projectResolutionPresets
        activeStyleID             = layerStates[idx].activeStyleID ?? styles.first?.id
        activeMotionID    = projectMotionSets.first?.id
        activeShapeID     = nil
        selectedIndices   = []
        currentFileURL    = url
        rebuildShapePolygonMap()

        // Resolve relative color source paths to absolute, patching in-memory state
        let colorSourcesDir = url.appendingPathComponent("colorSources")
        for li in layerStates.indices {
            guard var src = layerStates[li].engine.document.colorSource else { continue }
            if let rel = src.relativeFilePath {
                src.filePath = colorSourcesDir.appendingPathComponent(rel).path
                layerStates[li].engine.document.colorSource = src
            }
        }

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

    // Reads the legacy single-file format ([UMLayer] JSON array).
    // Migrates shapes and motion fields into project-level collections.
    private func readLegacy(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            UMLogger.shared.log("ERROR readLegacy read failed \(url.lastPathComponent)")
            return
        }
        // Try the v2 directory format's layer list first (never actually used single-file v2,
        // but handle it just in case), then fall back to old [UMLayer] array.
        let layers: [UMLayer]
        if let decoded = try? JSONDecoder().decode([UMLayer].self, from: data), !decoded.isEmpty {
            layers = decoded
        } else {
            UMLogger.shared.log("ERROR readLegacy decode failed \(url.lastPathComponent)")
            return
        }

        layerStates      = layers.map { UMLayerState(layer: $0) }
        activeLayerIndex = 0
        engine           = layerStates[0].engine
        projectStyles    = layerStates[0].engine.document.styles

        // Migrate shapes
        var seen = Set<UUID>()
        projectShapes = layerStates.flatMap { $0.engine.document.shapes }.filter { seen.insert($0.id).inserted }

        // Migrate motion: decode old CellStyle fields → UMMotionSet per style
        let legacyStyles = (try? JSONDecoder().decode([UMLayer].self, from: data))?
            .first?.document.styles.compactMap { style -> LegacyCellStyle? in
                guard let styleData = try? JSONEncoder().encode(style),
                      let legacy    = try? JSONDecoder().decode(LegacyCellStyle.self, from: styleData)
                else { return nil }
                return legacy
            } ?? []
        projectMotionSets = Self.migrateLegacyMotion(legacyStyles: legacyStyles, layerStates: &layerStates)

        activeStyleID    = layerStates[0].activeStyleID ?? projectStyles.first?.id
        activeMotionID   = projectMotionSets.first?.id
        activeShapeID    = nil
        selectedIndices  = []
        currentFileURL   = url
        rebuildShapePolygonMap()
        colorMapEngine.clear()
        if let src = layerStates[0].engine.document.colorSource {
            let rows = layerStates[0].engine.document.gridConfig.rows
            let cols = layerStates[0].engine.document.gridConfig.cols
            colorMapEngine.load(url: URL(fileURLWithPath: src.filePath), rows: rows, cols: cols)
        }
        UMLogger.shared.logState(prefix: "read(legacy) \(url.lastPathComponent)",
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

    // MARK: Motion set management

    var activeMotionSet: UMMotionSet? {
        guard let id = activeMotionID else { return nil }
        return projectMotionSets.first { $0.id == id }
    }

    func addMotionSet(name: String? = nil) {
        let ms = UMMotionSet(name: name ?? "Motion \(projectMotionSets.count + 1)")
        projectMotionSets.append(ms)
        activeMotionID = ms.id
    }

    func deleteMotionSet(_ id: UUID) {
        projectMotionSets.removeAll { $0.id == id }
        for ls in layerStates {
            for i in ls.engine.document.cells.indices where ls.engine.document.cells[i].motionID == id {
                ls.engine.document.cells[i].motionID = nil
            }
        }
        if activeMotionID == id { activeMotionID = projectMotionSets.first?.id }
    }

    func promoteMotionSetToLibrary(_ id: UUID) {
        guard let ms = projectMotionSets.first(where: { $0.id == id }) else { return }
        if let idx = globalLibrary.motionSets.firstIndex(where: { $0.id == id }) {
            globalLibrary.motionSets[idx] = ms
        } else {
            globalLibrary.motionSets.append(ms)
        }
        saveGlobalLibrary()
    }

    func importMotionSetFromLibrary(_ id: UUID) {
        guard let ms = globalLibrary.motionSets.first(where: { $0.id == id }) else { return }
        guard !projectMotionSets.contains(where: { $0.id == id }) else { return }
        projectMotionSets.append(ms)
        activeMotionID = ms.id
    }

    func removeMotionSetFromLibrary(_ id: UUID) {
        globalLibrary.motionSets.removeAll { $0.id == id }
        saveGlobalLibrary()
    }

    // MARK: Resolution preset management

    func addResolutionPreset(rows: Int, cols: Int, global: Bool = false) {
        let preset = UMResolutionPreset(rows: rows, cols: cols)
        if global {
            guard !globalResolutionPresets.contains(where: { $0.rows == rows && $0.cols == cols }) else { return }
            globalResolutionPresets.append(preset)
            saveGlobalResolutionPresets()
        } else {
            guard !projectResolutionPresets.contains(where: { $0.rows == rows && $0.cols == cols }) else { return }
            projectResolutionPresets.append(preset)
        }
    }

    func deleteResolutionPreset(_ id: UUID, global: Bool = false) {
        if global {
            globalResolutionPresets.removeAll { $0.id == id }
            saveGlobalResolutionPresets()
        } else {
            projectResolutionPresets.removeAll { $0.id == id }
        }
    }

    private static var globalResolutionPresetsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UM", isDirectory: true)
            .appendingPathComponent("resolutionPresets.json")
    }

    private func loadGlobalResolutionPresets() {
        guard let data    = try? Data(contentsOf: Self.globalResolutionPresetsURL),
              let presets = try? JSONDecoder().decode([UMResolutionPreset].self, from: data)
        else { return }
        globalResolutionPresets = presets
    }

    private func saveGlobalResolutionPresets() {
        let url = Self.globalResolutionPresetsURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(globalResolutionPresets) else { return }
        try? data.write(to: url, options: .atomic)
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
        var resolvedURL = url
        var relPath: String? = nil
        if let projectURL = currentFileURL {
            let colorSourcesDir = projectURL.appendingPathComponent("colorSources")
            try? FileManager.default.createDirectory(at: colorSourcesDir, withIntermediateDirectories: true)
            let dest = uniqueURL(in: colorSourcesDir, for: url.lastPathComponent)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                resolvedURL = dest
                relPath = dest.lastPathComponent
            }
        }
        engine.document.colorSource = UMColorSource(filePath: resolvedURL.path, relativeFilePath: relPath)
        let rows = engine.document.gridConfig.rows
        let cols = engine.document.gridConfig.cols
        colorMapEngine.load(url: resolvedURL, rows: rows, cols: cols)
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
        let name = url.deletingPathExtension().lastPathComponent
        var filename = url.lastPathComponent
        if let projectURL = currentFileURL {
            let shapesDir = projectURL.appendingPathComponent("shapes")
            try? FileManager.default.createDirectory(at: shapesDir, withIntermediateDirectories: true)
            let dest = uniqueURL(in: shapesDir, for: filename)
            try? FileManager.default.copyItem(at: url, to: dest)
            filename = dest.lastPathComponent
        }
        projectShapes.append(UMShape(name: name, sourceFilename: filename, geometryJSON: raw))
        rebuildShapePolygonMap()
    }

    func deleteShape(_ id: UUID) {
        if let projectURL = currentFileURL,
           let shape = projectShapes.first(where: { $0.id == id }) {
            let fileURL = projectURL.appendingPathComponent("shapes/\(shape.sourceFilename)")
            try? FileManager.default.removeItem(at: fileURL)
        }
        projectShapes.removeAll { $0.id == id }
        // Clear active selection if the deleted shape was active
        if activeShapeID == id { activeShapeID = nil }
        // Clear from any cells that referenced this shape
        for li in layerStates.indices {
            for ci in layerStates[li].engine.document.cells.indices
                where layerStates[li].engine.document.cells[ci].shapeID == id {
                layerStates[li].engine.document.cells[ci].shapeID = nil
            }
        }
        rebuildShapePolygonMap()
    }

    func promoteShapeToLibrary(_ id: UUID) {
        guard let shape = projectShapes.first(where: { $0.id == id }) else { return }
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
        guard !projectShapes.contains(where: { $0.id == id }) else { return }
        var imported = shape
        if let projectURL = currentFileURL {
            let shapesDir = projectURL.appendingPathComponent("shapes")
            try? FileManager.default.createDirectory(at: shapesDir, withIntermediateDirectories: true)
            let dest = uniqueURL(in: shapesDir, for: shape.sourceFilename)
            try? shape.geometryJSON.write(to: dest, atomically: true, encoding: .utf8)
            imported.sourceFilename = dest.lastPathComponent
        }
        projectShapes.append(imported)
        rebuildShapePolygonMap()
    }

    func removeShapeFromLibrary(_ id: UUID) {
        let url = Self.globalShapesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        globalShapes.removeAll { $0.id == id }
    }

    private func uniqueURL(in directory: URL, for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension
        var dest = directory.appendingPathComponent(filename)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = directory.appendingPathComponent(ext.isEmpty ? "\(base)_\(n)" : "\(base)_\(n).\(ext)")
            n += 1
        }
        return dest
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
            return proj.appendingPathComponent("renders")
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
                    layerStates:       self.layerStates,
                    backgroundColor:   self.backgroundColor,
                    shapePolygonMap:   self.shapePolygonMap,
                    fallbackPolygons:  self.shapePolygons,
                    projectMotionSets: self.projectMotionSets,
                    colorMapEngine:    self.colorMapEngine,
                    backgroundDraw:    self.backgroundDraw,
                    stretchSprites:    self.stretchSpritesToCell,
                    frame:             self.engine.currentFrame,
                    exportW:           exportW,
                    exportH:           exportH,
                    strokeScale:       strokeScale,
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
                        layers:            layers,
                        backgroundColor:   bg,
                        shapePolygonMap:   polyMap,
                        fallbackPolygons:  polys,
                        projectMotionSets: self.projectMotionSets,
                        colorMapEngine:    cmEngine,
                        backgroundDraw:    bgDraw,
                        stretchSprites:    stretch,
                        frameCount:        frames,
                        fps:               fps,
                        exportW:           exportW,
                        exportH:           exportH,
                        strokeScale:       strokeScale,
                        to:                url,
                        progress:          { [weak self] p in self?.exportProgress = p }
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
