import SwiftUI
import Observation
import AppKit
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import WebKit
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
    var parallaxFactor: Double
    var layerOffset: UMVectorDriver
    var opacityDriver: UMDoubleDriver
    var gridScrollDriver: UMVectorDriver
    var gridScrollMode: GridScrollMode
    var engine: UMGridEngine
    var activeStyleID: UUID?
    var layerMode: LayerMode
    var sprites: [UMSprite]
    var blendMode: UMBlendMode
    var gridDistortion: UMGridDistortion

    init(layer: UMLayer) {
        self.id               = layer.id
        self.name             = layer.name
        self.isVisible        = layer.isVisible
        self.opacity          = layer.opacity
        self.parallaxFactor   = layer.parallaxFactor
        self.layerOffset      = layer.layerOffset
        self.gridScrollDriver = layer.gridScrollDriver
        self.gridScrollMode   = layer.gridScrollMode
        self.engine           = UMGridEngine(document: layer.document)
        self.activeStyleID    = layer.document.styles.first?.id
        self.layerMode        = layer.layerMode
        self.sprites          = layer.sprites
        self.blendMode        = layer.blendMode
        self.gridDistortion   = layer.gridDistortion
        // Keep opacityDriver.base in sync with opacity for constant mode so the
        // layer-row slider and the driver evaluator always agree.
        var driver = layer.opacityDriver
        if driver.mode == .constant { driver.base = layer.opacity }
        self.opacityDriver = driver
    }

    func toUMLayer() -> UMLayer {
        UMLayer(id: id, name: name, isVisible: isVisible, opacity: opacity,
                parallaxFactor: parallaxFactor, layerOffset: layerOffset,
                opacityDriver: opacityDriver,
                gridScrollDriver: gridScrollDriver, gridScrollMode: gridScrollMode,
                document: engine.document,
                layerMode: layerMode, sprites: sprites,
                blendMode: blendMode,
                gridDistortion: gridDistortion)
    }
}

// MARK: - App controller

@Observable
@MainActor
final class AppController {

    private let defaultNewSpriteScale = 2.0

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
        activePathID    = nil   // nil before engine swap so stale Binding gets never fire
        let layer = layerStates[index]
        engine          = layer.engine
        activeStyleID   = layer.activeStyleID
        activeSpriteID  = nil
        selectedIndices = []
        colorMapEngine  = layerColorMapEngines[layer.id] ?? {
            let e = UMColorMapEngine(); layerColorMapEngines[layer.id] = e; return e
        }()
    }

    func addLayer(name: String? = nil) {
        let config = engine.document.gridConfig
        var doc    = UMGridDocument.makeDefault(rows: config.rows, cols: config.cols)
        doc.gridConfig.canvasWidth  = config.canvasWidth
        doc.gridConfig.canvasHeight = config.canvasHeight
        doc.gridConfig.cellWidth    = config.cellWidth
        doc.gridConfig.cellHeight   = config.cellHeight
        doc.styles = projectStyles
        let label  = name ?? "Layer \(layerStates.count + 1)"
        let ls     = UMLayerState(layer: UMLayer(name: label, document: doc))
        UMLogger.shared.log("addLayer '\(label)' \(projectStyles.count) styles, total layers→\(layerStates.count + 1)")
        layerColorMapEngines[ls.id] = UMColorMapEngine()
        layerStates.append(ls)
        selectLayer(layerStates.count - 1)
        rebuildShapePolygonMap()
    }

    func setProjectCanvasSize(width: Double, height: Double) {
        let w = max(1, width)
        let h = max(1, height)
        for ls in layerStates {
            ls.engine.document.gridConfig.canvasWidth = w
            ls.engine.document.gridConfig.canvasHeight = h
        }
    }

    func removeLayer(at index: Int) {
        guard layerStates.count > 1, index >= 0, index < layerStates.count else { return }
        let canvasW = engine.document.gridConfig.canvasWidth
        let canvasH = engine.document.gridConfig.canvasHeight
        let removedID = layerStates[index].id
        layerStates.remove(at: index)
        layerColorMapEngines.removeValue(forKey: removedID)
        let newIndex = min(activeLayerIndex, layerStates.count - 1)
        activeLayerIndex = newIndex
        activePathID     = nil
        engine          = layerStates[newIndex].engine
        activeStyleID   = layerStates[newIndex].activeStyleID
        activeSpriteID  = nil
        selectedIndices = []
        colorMapEngine  = layerColorMapEngines[layerStates[newIndex].id] ?? UMColorMapEngine()
        setProjectCanvasSize(width: canvasW, height: canvasH)
        rebuildShapePolygonMap()
    }

    func duplicateLayer(at index: Int) {
        guard index >= 0, index < layerStates.count else { return }
        let src = layerStates[index]
        let ls  = UMLayerState(layer: UMLayer(name: src.name + " Copy",
                                              isVisible: src.isVisible,
                                              opacity: src.opacity,
                                              parallaxFactor: src.parallaxFactor,
                                              layerOffset: src.layerOffset,
                                              opacityDriver: src.opacityDriver,
                                              gridScrollDriver: src.gridScrollDriver,
                                              gridScrollMode: src.gridScrollMode,
                                              document: src.engine.document,
                                              layerMode: src.layerMode,
                                              sprites: src.sprites))
        // Give the duplicate its own engine; reload the same color source if present.
        let dupEngine = UMColorMapEngine()
        if let cs = src.engine.document.colorSource {
            let rows = src.engine.document.gridConfig.rows
            let cols = src.engine.document.gridConfig.cols
            dupEngine.load(url: URL(fileURLWithPath: cs.filePath), rows: rows, cols: cols)
        }
        layerColorMapEngines[ls.id] = dupEngine
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

    // MARK: Sprite layer

    func addSpriteLayer(name: String? = nil) {
        let config = engine.document.gridConfig
        var doc    = UMGridDocument.makeDefault(rows: config.rows, cols: config.cols)
        // Carry canvas dimensions from the active layer so the sprite layer
        // does not reset to the 1080×1080 default.
        doc.gridConfig.canvasWidth  = config.canvasWidth
        doc.gridConfig.canvasHeight = config.canvasHeight
        doc.gridConfig.cellWidth    = config.cellWidth
        doc.gridConfig.cellHeight   = config.cellHeight
        doc.styles = projectStyles
        let label  = name ?? "Sprites \(layerStates.count + 1)"
        let ls     = UMLayerState(layer: UMLayer(name: label, document: doc, layerMode: .sprite))
        UMLogger.shared.log("addSpriteLayer '\(label)' total layers→\(layerStates.count + 1)")
        layerColorMapEngines[ls.id] = UMColorMapEngine()
        layerStates.append(ls)
        selectLayer(layerStates.count - 1)
    }

    func addSprite(at point: CGPoint) {
        guard activeLayerIndex < layerStates.count else { return }
        let ls     = layerStates[activeLayerIndex]
        guard ls.layerMode == .sprite else { return }
        let count  = ls.sprites.count + 1
        var sprite = UMSprite(
            name:     "Sprite \(count)",
            x:        Double(point.x),
            y:        Double(point.y),
            scaleX:   defaultNewSpriteScale,
            scaleY:   defaultNewSpriteScale,
            styleID:  activeStyleID,
            shapeID:  activeShapeID,
            motionID: activeMotionID
        )
        sprite.animatedGeometryID = activeAnimatedGeometryID
        ls.sprites.append(sprite)
        activeSpriteID = sprite.id
    }

    func removeSprite(id: UUID) {
        guard activeLayerIndex < layerStates.count else { return }
        let ls = layerStates[activeLayerIndex]
        ls.sprites.removeAll { $0.id == id }
        if activeSpriteID == id { activeSpriteID = nil }
    }

    func moveSprite(id: UUID, to point: CGPoint) {
        guard activeLayerIndex < layerStates.count else { return }
        let ls = layerStates[activeLayerIndex]
        guard let i = ls.sprites.firstIndex(where: { $0.id == id }) else { return }
        ls.sprites[i].x = Double(point.x)
        ls.sprites[i].y = Double(point.y)
    }

    /// Records (or overwrites) a position keyframe on a sprite's positionDriver at the given
    /// frame. canvasX/Y are in display-canvas pixels; the stored offset is relative to the
    /// sprite's base position so that sprite.x/y stays fixed as the animation reference.
    func setSpritePositionKeyframe(id: UUID, frame: Int,
                                   canvasX: Double, canvasY: Double,
                                   gridW: Double, gridH: Double,
                                   motionDX: Double = 0, motionDY: Double = 0) {
        guard activeLayerIndex < layerStates.count else { return }
        let ls = layerStates[activeLayerIndex]
        guard let si = ls.sprites.firstIndex(where: { $0.id == id }) else { return }
        let sprite = ls.sprites[si]
        let offset = UMVec2(x: canvasX - sprite.x * gridW - motionDX,
                            y: canvasY - sprite.y * gridH - motionDY)
        var d = sprite.positionDriver
        d.mode = .keyframe
        d.loopMode = .once
        d.keyframes.removeAll { $0.frame == frame }
        d.keyframes.append(UMVectorKeyframe(frame: frame, value: offset))
        d.keyframes.sort { $0.frame < $1.frame }
        ls.sprites[si].positionDriver = d
    }

    private func normalizeSpritePositionDrivers() {
        for ls in layerStates where ls.layerMode == .sprite {
            for i in ls.sprites.indices where ls.sprites[i].positionDriver.mode == .keyframe {
                ls.sprites[i].positionDriver.loopMode = .once
            }
        }
    }

    func updateSprite(id: UUID, _ body: (inout UMSprite) -> Void) {
        guard activeLayerIndex < layerStates.count else { return }
        let ls = layerStates[activeLayerIndex]
        guard let i = ls.sprites.firstIndex(where: { $0.id == id }) else { return }
        body(&ls.sprites[i])
    }

    // MARK: Polygons

    var shapePolygons: [Polygon2D] = []        // bundled default
    var shapePolygonMap: [UUID: [Polygon2D]] = [:]
    var shapePolygonIDMap: [UUID: [UUID]] = [:]  // shape ID → ordered polygon UUIDs (EditableClosedPolygon.id)

    // MARK: Global UI state

    var activeTool: PaintTool        = .draw
    var transformMode: TransformMode = .move
    var stampPhaseOffset: Int        = 0
    var stretchSpritesToCell: Bool   = true
    var showGrid: Bool               = false
    var showPhaseHeatmap: Bool       = false
    var gridColor: UMColor           = UMColor(r: 0.5, g: 0.5, b: 0.5, a: 1)
    var gridLineWidth: Double        = 0.5
    var backgroundColor: UMColor     = UMColor(r: 1, g: 1, b: 1, a: 1)
    var backgroundCGImage: CGImage?  = nil
    var backgroundImagePath: String? = nil
    var isPlaying: Bool              = false
    var selectedIndices:    Set<Int> = []
    var gridClipboard:      [ClipboardCell] = []
    var isAnchorMode:       Bool = false   // waiting for click to set paste target
    var pasteAnchorRow:     Int? = nil
    var pasteAnchorCol:     Int? = nil

    var activeStyleID:             UUID?    = nil
    var activeMotionID:            UUID?    = nil
    var activeShapeID:             UUID?    = nil
    var activeAnimatedGeometryID:  UUID?    = nil
    var activeSpriteID:            UUID?    = nil

    var currentFileURL:             URL?      = nil
    var globalLibrary:              UMLibrary = .empty
    var globalShapes:               [UMShape] = []
    var projectShapes:              [UMShape] = []
    var hiddenShapeIDs:             Set<UUID> = []
    var projectMotionSets:          [UMMotionSet] = []
    var projectColorPalettes:       [UMColorPalette] = []
    var activeColorPaletteID:       UUID? = nil
    var projectResolutionPresets:   [UMResolutionPreset] = []
    var globalResolutionPresets:    [UMResolutionPreset] = []
    var projectAnimatedGeometries:  [UMAnimatedGeometry] = []

    // MARK: Camera
    var camera: UMCamera = .identity

    // MARK: Canvas view state
    var canvasZoom: Double = 1.0
    var canvasPan:  CGSize = .zero
    var canvasIsHovered: Bool = false

    // MARK: Timeline panel state
    var isTimelineCollapsed: Bool  = true
    var showScrubBar: Bool         = false
    var isLooping: Bool            = false
    var timelineResizePreviewH: CGFloat? = nil
    var startFrame: Int            = 0
    var endFrame: Int              = 240
    var selectedTimelineKF: UMTimelineKFSelection? = nil
    var selectedCameraKF:   UMCameraKFSelection?   = nil
    var selectedSpriteKF:   UMSpriteKFSelection?   = nil
    var timelineMarkers:    [UMTimelineMarker]     = []
    var kfClipboard:        UMKFClipboard?         = nil

    var maxScrubFrames: Int { endFrame > 0 ? endFrame : 240 }

    func selectSpriteFromCanvas(_ id: UUID?) {
        activeSpriteID = id
        selectedTimelineKF = nil
        selectedCameraKF = nil
        selectedSpriteKF = nil
        selectedIndices = []
    }

    func seekToFrame(_ f: Int) {
        let clamped = max(0, min(maxScrubFrames, f))
        for ls in layerStates { ls.engine.seek(toFrame: clamped) }
    }

    private var playbackTask: Task<Void, Never>?
    private nonisolated(unsafe) var keyMonitor: Any?

    // MARK: Init

    init() {
        let doc = UMGridDocument.makeDefault()
        let ls  = UMLayerState(layer: UMLayer(name: "Layer 1", document: doc))
        layerStates      = [ls]
        engine           = ls.engine
        activeLayerIndex = 0
        projectStyles    = doc.styles
        activeStyleID    = doc.styles.first?.id
        layerColorMapEngines[ls.id] = colorMapEngine   // register the initial engine
        loadShapePolygons()
        rebuildShapePolygonMap()
        ensureProjectsDirectory()
        UMLogger.shared.logState(prefix: "init", layers: 1,
                                  styles: doc.styles.count, cells: doc.cells.count)
        loadGlobalLibrary()
        loadGlobalShapes()
        loadGlobalResolutionPresets()
        seedDefaultShape()
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
        var map:   [UUID: [Polygon2D]] = [:]
        var idMap: [UUID: [UUID]]      = [:]
        for shape in projectShapes {
            guard let data  = shape.geometryJSON.data(using: .utf8),
                  let geo   = try? EditableGeometryJSONLoader.decode(from: data),
                  let polys = try? geo.runtimePolygons()
            else { continue }
            map[shape.id] = polys
            // Collect EditableClosedPolygon.id values in the same visible order as runtimePolygons()
            var ids: [UUID] = []
            for layer in geo.layers where layer.isVisible {
                ids += layer.polygons.filter(\.isVisible).map(\.id)
                ids += layer.openCurves.filter(\.isVisible).map(\.id)
                ids += layer.points.filter(\.isVisible).map(\.id)
            }
            idMap[shape.id] = ids
        }
        shapePolygonMap   = map
        shapePolygonIDMap = idMap
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
    var isExporting: Bool        = false
    var exportProgress: Double   = 0.0

    var exportFrameCount: Int { max(1, endFrame - startFrame) }
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

                    // Loop playback: wrap from endFrame back to startFrame
                    if self.isLooping && self.engine.currentFrame >= self.endFrame {
                        self.seekToFrame(self.startFrame)
                    }

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

    func setBackgroundImage(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image  = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        backgroundCGImage  = image
        backgroundImagePath = url.path
    }

    func clearBackgroundImage() {
        backgroundCGImage   = nil
        backgroundImagePath = nil
    }

    func newDocument() {
        UMLogger.shared.log("newDocument")
        let doc = UMGridDocument.makeDefault()
        let ls  = UMLayerState(layer: UMLayer(name: "Layer 1", document: doc))
        layerStates       = [ls]
        engine            = ls.engine
        activeLayerIndex  = 0
        projectStyles             = doc.styles
        projectShapes             = []
        projectMotionSets         = []
        projectColorPalettes      = []
        activeColorPaletteID      = nil
        projectResolutionPresets  = []
        projectAnimatedGeometries = []
        hiddenShapeIDs            = []
        activeStyleID             = doc.styles.first?.id
        activeMotionID            = nil
        layerColorMapEngines.removeAll()
        let freshEngine           = UMColorMapEngine()
        layerColorMapEngines[ls.id] = freshEngine
        colorMapEngine            = freshEngine
        activeShapeID             = nil
        activeSpriteID            = nil
        selectedIndices           = []
        currentFileURL            = nil
        camera            = .identity
        backgroundColor     = UMColor(r: 1, g: 1, b: 1, a: 1)
        backgroundDraw      = true
        backgroundCGImage   = nil
        backgroundImagePath = nil
        rebuildShapePolygonMap()
        seedDefaultShape()
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
            // Added in v4; optional for backward compat
            var parallaxFactor:   Double?
            var layerOffset:      UMVectorDriver?
            var opacityDriver:    UMDoubleDriver?
            // Added in v6; optional for backward compat
            var gridScrollDriver: UMVectorDriver?
            var gridScrollMode:   GridScrollMode?
            // Added in v8; optional for backward compat
            var layerMode:        LayerMode?
            var sprites:          [UMSprite]?
        }
        var version: Int
        var activeLayerIndex: Int
        var projectStyles: [CellStyle]
        var projectShapes: [ShapeRecord]
        var projectMotionSets: [UMMotionSet]
        var projectColorPalettes: [UMColorPalette]
        var projectResolutionPresets: [UMResolutionPreset]
        var projectAnimatedGeometries: [UMAnimatedGeometry]?   // Added in v10; nil → []
        var hiddenShapeIDs: [UUID]?                            // Added in v11; nil → []
        var layers: [LayerRecord]
        var camera: UMCamera?             // Added in v4; nil → .identity
        var timelineMarkers: [UMTimelineMarker]?  // Added in v5; nil → []
        var backgroundImageRelPath: String?       // Added in v7; nil → no background image
        var backgroundColor: UMColor?             // Added in v9; nil → white
        var backgroundDraw: Bool?                 // Added in v9; nil → true

        enum CodingKeys: String, CodingKey {
            case version, activeLayerIndex, projectStyles, projectShapes
            case projectMotionSets, projectColorPalettes, projectResolutionPresets
            case projectAnimatedGeometries, hiddenShapeIDs, layers
            case camera, timelineMarkers, backgroundImageRelPath, backgroundColor, backgroundDraw
        }

        init(version: Int, activeLayerIndex: Int, projectStyles: [CellStyle],
             projectShapes: [ShapeRecord], projectMotionSets: [UMMotionSet],
             projectColorPalettes: [UMColorPalette],
             projectResolutionPresets: [UMResolutionPreset],
             projectAnimatedGeometries: [UMAnimatedGeometry],
             hiddenShapeIDs: [UUID],
             layers: [LayerRecord], camera: UMCamera?,
             timelineMarkers: [UMTimelineMarker]?,
             backgroundImageRelPath: String?,
             backgroundColor: UMColor?,
             backgroundDraw: Bool?) {
            self.version                    = version
            self.activeLayerIndex           = activeLayerIndex
            self.projectStyles              = projectStyles
            self.projectShapes              = projectShapes
            self.projectMotionSets          = projectMotionSets
            self.projectColorPalettes       = projectColorPalettes
            self.projectResolutionPresets   = projectResolutionPresets
            self.projectAnimatedGeometries  = projectAnimatedGeometries.isEmpty ? nil : projectAnimatedGeometries
            self.hiddenShapeIDs             = hiddenShapeIDs.isEmpty ? nil : hiddenShapeIDs
            self.layers                     = layers
            self.camera                     = camera
            self.timelineMarkers            = timelineMarkers
            self.backgroundImageRelPath     = backgroundImageRelPath
            self.backgroundColor            = backgroundColor
            self.backgroundDraw             = backgroundDraw
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version                     = try  c.decode(Int.self,             forKey: .version)
            activeLayerIndex            = try  c.decode(Int.self,             forKey: .activeLayerIndex)
            projectStyles               = try  c.decode([CellStyle].self,     forKey: .projectStyles)
            projectShapes               = try  c.decode([ShapeRecord].self,   forKey: .projectShapes)
            projectMotionSets           = (try? c.decodeIfPresent([UMMotionSet].self,               forKey: .projectMotionSets))          ?? []
            projectColorPalettes        = (try? c.decodeIfPresent([UMColorPalette].self,            forKey: .projectColorPalettes))       ?? []
            projectResolutionPresets    = (try? c.decodeIfPresent([UMResolutionPreset].self,        forKey: .projectResolutionPresets))   ?? []
            projectAnimatedGeometries   = try? c.decodeIfPresent([UMAnimatedGeometry].self,         forKey: .projectAnimatedGeometries)
            hiddenShapeIDs              = try? c.decodeIfPresent([UUID].self,                       forKey: .hiddenShapeIDs)
            layers                      = try  c.decode([LayerRecord].self,   forKey: .layers)
            camera                      = try? c.decodeIfPresent(UMCamera.self,               forKey: .camera)
            timelineMarkers             = try? c.decodeIfPresent([UMTimelineMarker].self,     forKey: .timelineMarkers)
            backgroundImageRelPath      = try? c.decodeIfPresent(String.self,                forKey: .backgroundImageRelPath)
            backgroundColor             = try? c.decodeIfPresent(UMColor.self,               forKey: .backgroundColor)
            backgroundDraw              = try? c.decodeIfPresent(Bool.self,                  forKey: .backgroundDraw)
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

        // Copy background image into project package
        var bgImageRelPath: String? = nil
        if let bgPath = backgroundImagePath {
            let srcURL = URL(fileURLWithPath: bgPath)
            if fm.fileExists(atPath: srcURL.path) {
                let bgDir = url.appendingPathComponent("backgroundImage")
                try? fm.createDirectory(at: bgDir, withIntermediateDirectories: true)
                let dest  = bgDir.appendingPathComponent(srcURL.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: srcURL, to: dest) }
                bgImageRelPath    = "backgroundImage/\(srcURL.lastPathComponent)"
                backgroundImagePath = dest.path
            }
        }

        // Create empty render directories (mirrors Loom project layout)
        try? fm.createDirectory(at: url.appendingPathComponent("renders/animations"),
                                withIntermediateDirectories: true)
        try? fm.createDirectory(at: url.appendingPathComponent("renders/stills"),
                                withIntermediateDirectories: true)

        // Build and write config.json
        layerStates[activeLayerIndex].activeStyleID = activeStyleID
        let config = ProjectConfig(
            version: 11,
            activeLayerIndex: activeLayerIndex,
            projectStyles: projectStyles,
            projectShapes: projectShapes.map {
                ProjectConfig.ShapeRecord(id: $0.id, name: $0.name, sourceFilename: $0.sourceFilename)
            },
            projectMotionSets: projectMotionSets,
            projectColorPalettes: projectColorPalettes,
            projectResolutionPresets: projectResolutionPresets,
            projectAnimatedGeometries: projectAnimatedGeometries,
            hiddenShapeIDs: Array(hiddenShapeIDs),
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
                    colorSource:   ls.engine.document.colorSource,
                    parallaxFactor:   ls.parallaxFactor,
                    layerOffset:      ls.layerOffset,
                    opacityDriver:    ls.opacityDriver,
                    gridScrollDriver: ls.gridScrollDriver,
                    gridScrollMode:   ls.gridScrollMode,
                    layerMode:        ls.layerMode == .sprite ? ls.layerMode : nil,
                    sprites:          ls.sprites.isEmpty ? nil : ls.sprites
                )
            },
            camera: camera,
            timelineMarkers: timelineMarkers.isEmpty ? nil : timelineMarkers,
            backgroundImageRelPath: bgImageRelPath,
            backgroundColor: backgroundColor,
            backgroundDraw: backgroundDraw
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
            let layer = UMLayer(
                id:            record.id,
                name:          record.name,
                isVisible:     record.isVisible,
                opacity:       record.opacity,
                parallaxFactor:   record.parallaxFactor  ?? 1.0,
                layerOffset:      record.layerOffset     ?? .zero,
                opacityDriver:    record.opacityDriver   ?? UMDoubleDriver(mode: .constant, base: record.opacity),
                gridScrollDriver: record.gridScrollDriver ?? .zero,
                gridScrollMode:   record.gridScrollMode   ?? .wrap,
                document:         doc,
                layerMode:        record.layerMode        ?? .grid,
                sprites:          record.sprites          ?? []
            )
            let ls = UMLayerState(layer: layer)
            ls.activeStyleID = record.activeStyleID ?? styles.first?.id
            return ls
        }
        normalizeSpritePositionDrivers()

        let idx      = max(0, min(config.activeLayerIndex, layerStates.count - 1))
        activeLayerIndex  = idx
        engine            = layerStates[idx].engine
        camera            = config.camera ?? .identity
        timelineMarkers   = config.timelineMarkers ?? []
        backgroundColor   = config.backgroundColor ?? UMColor(r: 1, g: 1, b: 1, a: 1)
        backgroundDraw    = config.backgroundDraw ?? true
        projectStyles             = styles
        projectShapes             = loaded
        projectMotionSets         = config.projectMotionSets
        projectColorPalettes      = config.projectColorPalettes
        activeColorPaletteID      = config.projectColorPalettes.first?.id
        projectResolutionPresets  = config.projectResolutionPresets
        projectAnimatedGeometries = config.projectAnimatedGeometries ?? []
        hiddenShapeIDs            = Set(config.hiddenShapeIDs ?? [])
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

        // Load background image
        if let rel = config.backgroundImageRelPath {
            let imageURL = url.appendingPathComponent(rel)
            if let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                backgroundCGImage   = img
                backgroundImagePath = imageURL.path
            } else {
                backgroundCGImage   = nil
                backgroundImagePath = nil
            }
        } else {
            backgroundCGImage   = nil
            backgroundImagePath = nil
        }

        layerColorMapEngines.removeAll()
        for li in layerStates.indices {
            let ls  = layerStates[li]
            let cme = UMColorMapEngine()
            layerColorMapEngines[ls.id] = cme
            if let src = ls.engine.document.colorSource {
                let rows = ls.engine.document.gridConfig.rows
                let cols = ls.engine.document.gridConfig.cols
                cme.load(url: URL(fileURLWithPath: src.filePath), rows: rows, cols: cols)
            }
        }
        colorMapEngine = layerColorMapEngines[layerStates[idx].id] ?? UMColorMapEngine()
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
        camera           = .identity
        projectStyles    = layerStates[0].engine.document.styles
        backgroundColor  = UMColor(r: 1, g: 1, b: 1, a: 1)
        backgroundDraw   = true

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
        normalizeSpritePositionDrivers()

        activeStyleID    = layerStates[0].activeStyleID ?? projectStyles.first?.id
        activeMotionID   = projectMotionSets.first?.id
        activeShapeID    = nil
        selectedIndices  = []
        currentFileURL   = url
        rebuildShapePolygonMap()
        layerColorMapEngines.removeAll()
        for li in layerStates.indices {
            let ls  = layerStates[li]
            let cme = UMColorMapEngine()
            layerColorMapEngines[ls.id] = cme
            if let src = ls.engine.document.colorSource {
                let rows = ls.engine.document.gridConfig.rows
                let cols = ls.engine.document.gridConfig.cols
                cme.load(url: URL(fileURLWithPath: src.filePath), rows: rows, cols: cols)
            }
        }
        colorMapEngine = layerColorMapEngines[layerStates[0].id] ?? UMColorMapEngine()
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

    // MARK: Color palette management

    func generateColorPalette(name: String, rows: Int, cols: Int) {
        let colors = colorMapEngine.buildPaletteColors(rows: rows, cols: cols)
        guard !colors.isEmpty else { return }
        let desc    = "\(colorMapEngine.displayName) \(rows)×\(cols)"
        let palette = UMColorPalette(name: name, colors: colors, sourceDescription: desc)
        projectColorPalettes.append(palette)
        activeColorPaletteID = palette.id
    }

    func deleteColorPalette(_ id: UUID) {
        projectColorPalettes.removeAll { $0.id == id }
        if activeColorPaletteID == id { activeColorPaletteID = projectColorPalettes.first?.id }
    }

    func promoteColorPaletteToLibrary(_ id: UUID) {
        guard let p = projectColorPalettes.first(where: { $0.id == id }) else { return }
        if let idx = globalLibrary.colorPalettes.firstIndex(where: { $0.id == id }) {
            globalLibrary.colorPalettes[idx] = p
        } else {
            globalLibrary.colorPalettes.append(p)
        }
        saveGlobalLibrary()
    }

    func importColorPaletteFromLibrary(_ id: UUID) {
        guard let p = globalLibrary.colorPalettes.first(where: { $0.id == id }) else { return }
        guard !projectColorPalettes.contains(where: { $0.id == id }) else { return }
        projectColorPalettes.append(p)
        activeColorPaletteID = p.id
    }

    func removeColorPaletteFromLibrary(_ id: UUID) {
        globalLibrary.colorPalettes.removeAll { $0.id == id }
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

    var activePathID: UUID?              = nil
    var showPathOverlay: Bool            = true
    var selectedPathKeyframeID: UUID?    = nil

    // Per-layer colour map engines keyed by layer UUID.
    // colorMapEngine always refers to the active layer's engine and is what the UI binds to.
    var layerColorMapEngines: [UUID: UMColorMapEngine] = [:]
    var colorMapEngine: UMColorMapEngine = UMColorMapEngine()

    func colorMapEngine(forLayerID id: UUID) -> UMColorMapEngine? { layerColorMapEngines[id] }

    var activePath: UMMotionPath? {
        guard let id = activePathID else { return nil }
        return engine.document.paths.first { $0.id == id }
    }

    func createPath() {
        let p = UMMotionPath(name: "Path \(engine.document.paths.count + 1)")
        engine.document.paths.append(p)
        activePathID             = p.id
        selectedPathKeyframeID   = nil
    }

    func deletePath(_ id: UUID) {
        engine.document.paths.removeAll { $0.id == id }
        for i in engine.document.cells.indices where engine.document.cells[i].pathID == id {
            engine.document.cells[i].pathID = nil
        }
        if activePathID == id {
            activePathID           = engine.document.paths.first?.id
            selectedPathKeyframeID = nil
        }
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

    // MARK: Color Map Lock / Unlock

    /// True if any drawn cell on the active layer has a baked color lock.
    var hasColorMapLock: Bool {
        engine.document.cells.contains { $0.isDrawn && ($0.lockedFillColor != nil || $0.lockedStrokeColor != nil) }
    }

    /// Bake the current color map into each drawn cell so the color travels
    /// with the cell through transforms. Scoped to selection when non-empty.
    func lockColorMap() {
        guard colorMapEngine.isLoaded,
              let src  = engine.document.colorSource,
              let grid = colorMapEngine.currentGrid(animationFrame: 0, loopMode: .loop) else { return }
        let cols    = engine.document.gridConfig.cols
        let indices = selectedIndices.isEmpty ? nil : selectedIndices
        for i in engine.document.cells.indices {
            var cell = engine.document.cells[i]
            guard cell.isDrawn else { continue }
            guard indices == nil || indices!.contains(cell.gridIndex) else { continue }
            let r = cell.gridIndex / cols
            let c = cell.gridIndex % cols
            guard r < grid.count, c < grid[r].count else { continue }
            let sampled = grid[r][c]
            let style   = projectStyles.first(where: { $0.id == cell.styleID })
            let a       = src.preserveStyleAlpha ? (style?.fillColor.a ?? 1.0) : sampled.a
            let mapped  = UMColor(r: sampled.r, g: sampled.g, b: sampled.b, a: a)
            switch src.applyTo {
            case .fill:          cell.lockedFillColor   = mapped; cell.lockedStrokeColor = nil
            case .stroke:        cell.lockedStrokeColor = mapped; cell.lockedFillColor   = nil
            case .fillAndStroke: cell.lockedFillColor   = mapped; cell.lockedStrokeColor = mapped
            }
            engine.document.cells[i] = cell
        }
        UMLogger.shared.log("lockColorMap \(indices == nil ? "all" : "\(indices!.count) selected") cells")
    }

    /// Remove baked color locks from drawn cells. Scoped to selection when non-empty.
    func unlockColorMap() {
        let indices = selectedIndices.isEmpty ? nil : selectedIndices
        for i in engine.document.cells.indices {
            guard engine.document.cells[i].isDrawn else { continue }
            guard indices == nil || indices!.contains(engine.document.cells[i].gridIndex) else { continue }
            engine.document.cells[i].lockedFillColor   = nil
            engine.document.cells[i].lockedStrokeColor = nil
        }
        UMLogger.shared.log("unlockColorMap \(indices == nil ? "all" : "\(indices!.count) selected") cells")
    }

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

    /// Imports each visible, non-empty layer of a multi-layer Loom geometry file as an
    /// individual UMShape, then auto-creates a UMAnimatedGeometry (Sprite Set) containing
    /// all resulting shapes in layer order.  Layers with no polygons are skipped.
    func importShapeLayers(from url: URL) {
        guard let data   = try? Data(contentsOf: url),
              let geoDoc = try? EditableGeometryJSONLoader.decode(from: data)
        else { return }

        let docName = url.deletingPathExtension().lastPathComponent
        let candidateLayers = geoDoc.layers.filter { $0.isVisible && !$0.polygons.isEmpty }
        guard !candidateLayers.isEmpty else { return }

        let shapesDir: URL? = currentFileURL.map {
            let dir = $0.appendingPathComponent("shapes")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        var created: [UMShape] = []
        for layer in candidateLayers {
            // Build a self-contained single-layer document.
            // weldGroups reference cross-layer points so we clear them; runtimePolygons()
            // doesn't use them and this keeps the file clean.
            var singleDoc = geoDoc
            singleDoc.layers = [layer]
            singleDoc.weldGroups = []

            guard let encoded = try? EditableGeometryJSONLoader.encode(singleDoc),
                  let json    = String(data: encoded, encoding: .utf8)
            else { continue }

            let layerName = layer.name.isEmpty ? "Layer" : layer.name
            let baseFilename = "\(docName)_\(layerName).json"
            let savedFilename: String
            if let dir = shapesDir {
                let dest = uniqueURL(in: dir, for: baseFilename)
                try? json.write(to: dest, atomically: true, encoding: .utf8)
                savedFilename = dest.lastPathComponent
            } else {
                savedFilename = baseFilename
            }

            let shape = UMShape(name: layerName, sourceFilename: savedFilename, geometryJSON: json)
            projectShapes.append(shape)
            created.append(shape)
        }

        guard !created.isEmpty else { return }
        rebuildShapePolygonMap()

        // Auto-create a Sprite Set with all imported shapes in layer order.
        var geo = UMAnimatedGeometry(name: docName)
        geo.states = created.map { UMAnimatedGeometryState(shapeID: $0.id, holdFrames: 2) }
        projectAnimatedGeometries.append(geo)

        UMLogger.shared.log("importShapeLayers: \(created.count) shapes + Sprite Set from \(docName)")
    }

    func toggleShapeHidden(_ id: UUID) {
        if hiddenShapeIDs.contains(id) {
            hiddenShapeIDs.remove(id)
        } else {
            hiddenShapeIDs.insert(id)
        }
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

    private func seedDefaultShape() {
        guard let sq = globalShapes.first(where: { $0.name.lowercased() == "square" }) else { return }
        if !projectShapes.contains(where: { $0.id == sq.id }) {
            projectShapes.append(sq)
            rebuildShapePolygonMap()
        }
        activeShapeID = sq.id
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

    // MARK: Animated geometry management

    @discardableResult
    func addAnimatedGeometry(name: String? = nil) -> UMAnimatedGeometry {
        let geo = UMAnimatedGeometry(name: name ?? "Sprite Set \(projectAnimatedGeometries.count + 1)")
        projectAnimatedGeometries.append(geo)
        return geo
    }

    func duplicateAnimatedGeometry(id: UUID) {
        guard let original = projectAnimatedGeometries.first(where: { $0.id == id }),
              let idx      = projectAnimatedGeometries.firstIndex(where: { $0.id == id }) else { return }
        var copy      = original
        copy.id       = UUID()
        copy.name     = "Copy of \(original.name)"
        projectAnimatedGeometries.insert(copy, at: idx + 1)
    }

    func removeAnimatedGeometry(id: UUID) {
        projectAnimatedGeometries.removeAll { $0.id == id }
        for ls in layerStates {
            for i in ls.sprites.indices where ls.sprites[i].animatedGeometryID == id {
                ls.sprites[i].animatedGeometryID = nil
            }
        }
    }

    func updateAnimatedGeometry(_ geo: UMAnimatedGeometry) {
        guard let i = projectAnimatedGeometries.firstIndex(where: { $0.id == geo.id }) else { return }
        projectAnimatedGeometries[i] = geo
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

    func assignMotionToSelection(_ motionID: UUID?) {
        guard !selectedIndices.isEmpty else { return }
        engine.pushUndoSnapshot()
        for i in selectedIndices where i < engine.document.cells.count {
            engine.document.cells[i].motionID = motionID
        }
    }

    func assignShapeToSelection(_ shapeID: UUID?) {
        guard !selectedIndices.isEmpty else { return }
        engine.pushUndoSnapshot()
        for i in selectedIndices where i < engine.document.cells.count {
            engine.document.cells[i].shapeID = shapeID
        }
    }

    func assignAnimGeoToSelection(_ geoID: UUID?) {
        guard !selectedIndices.isEmpty else { return }
        engine.pushUndoSnapshot()
        for i in selectedIndices where i < engine.document.cells.count {
            engine.document.cells[i].animatedGeometryID = geoID
        }
    }

    // MARK: Nudge

    struct ClipboardCell: Sendable {
        var relRow: Int
        var relCol: Int
        var cell:   UMGridCell
    }

    func copySelection() {
        let cells  = engine.document.cells
        let config = engine.document.gridConfig
        let drawn  = selectedIndices.filter { $0 < cells.count && cells[$0].isDrawn }
        guard !drawn.isEmpty else { return }
        let minRow = drawn.map { $0 / config.cols }.min()!
        let minCol = drawn.map { $0 % config.cols }.min()!
        gridClipboard = drawn.map { idx in
            ClipboardCell(relRow: idx / config.cols - minRow,
                          relCol: idx % config.cols - minCol,
                          cell:   cells[idx])
        }
        pasteAnchorRow = nil
        pasteAnchorCol = nil
        isAnchorMode   = true
    }

    func cutSelection() {
        copySelection()
        guard !gridClipboard.isEmpty else { return }
        engine.pushUndoSnapshot()
        for item in gridClipboard {
            let idx = item.cell.gridIndex
            if idx < engine.document.cells.count {
                engine.document.cells[idx].isDrawn = false
            }
        }
        selectedIndices = []
    }

    func pasteClipboard(atRow: Int, atCol: Int) {
        guard !gridClipboard.isEmpty else { return }
        let config = engine.document.gridConfig
        let targets: [(src: ClipboardCell, dstIdx: Int)] = gridClipboard.map { item in
            let r = atRow + item.relRow
            let c = atCol + item.relCol
            return (item, r * config.cols + c)
        }
        guard targets.allSatisfy({ t in
            let r = atRow + t.src.relRow
            let c = atCol + t.src.relCol
            return r >= 0 && r < config.rows && c >= 0 && c < config.cols
                && t.dstIdx < engine.document.cells.count
        }) else { return }
        engine.pushUndoSnapshot()
        var newSelected: Set<Int> = []
        for t in targets {
            var pasted = t.src.cell
            pasted.id        = UUID()
            pasted.gridIndex = t.dstIdx
            engine.document.cells[t.dstIdx] = pasted
            newSelected.insert(t.dstIdx)
        }
        selectedIndices = newSelected
        pasteAnchorRow = nil
        pasteAnchorCol = nil
    }

    func moveSelectionByGrid(dRow: Int, dCol: Int, isRepeat: Bool = false) {
        guard !selectedIndices.isEmpty else { return }
        let cells  = engine.document.cells
        let config = engine.document.gridConfig
        let drawn  = selectedIndices.filter { $0 < cells.count && cells[$0].isDrawn }
        guard !drawn.isEmpty else { return }
        let moves: [(from: Int, to: Int)] = drawn.compactMap { idx in
            let r = idx / config.cols + dRow
            let c = idx % config.cols + dCol
            guard r >= 0, r < config.rows, c >= 0, c < config.cols else { return nil }
            return (idx, r * config.cols + c)
        }
        guard moves.count == drawn.count else { return }   // any OOB → no-op
        if !isRepeat { engine.pushUndoSnapshot() }
        let snapshots = moves.map { (from: $0.from, to: $0.to, cell: cells[$0.from]) }
        let dstSet    = Set(moves.map(\.to))
        for snap in snapshots where !dstSet.contains(snap.from) {
            engine.document.cells[snap.from].isDrawn = false
        }
        var newSelected: Set<Int> = []
        for snap in snapshots {
            var moved       = snap.cell
            moved.gridIndex = snap.to
            engine.document.cells[snap.to] = moved
            newSelected.insert(snap.to)
        }
        selectedIndices = newSelected
    }

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
            if Self.firstResponderIsInWebView() { return event }

            let cmd   = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            let rep   = event.isARepeat

            // Cmd shortcuts (no option/control)
            if cmd && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c": copySelection(); return nil
                case "x": cutSelection(); return nil
                case "v":
                    if !gridClipboard.isEmpty,
                       let r = pasteAnchorRow, let c = pasteAnchorCol {
                        pasteClipboard(atRow: r, atCol: c)
                    }
                    return nil
                default: break
                }
                return event  // pass other Cmd shortcuts through
            }

            if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty { return event }

            // Arrow keys: grid move in select mode, pixel nudge otherwise
            switch event.keyCode {
            case 123:
                if activeTool == .select && !selectedIndices.isEmpty {
                    moveSelectionByGrid(dRow: 0, dCol: -1, isRepeat: rep)
                } else {
                    nudgeSelection(dx: -nudgeStep(shift), dy: 0, isRepeat: rep)
                }
                return nil
            case 124:
                if activeTool == .select && !selectedIndices.isEmpty {
                    moveSelectionByGrid(dRow: 0, dCol: 1, isRepeat: rep)
                } else {
                    nudgeSelection(dx: nudgeStep(shift), dy: 0, isRepeat: rep)
                }
                return nil
            case 125:
                if activeTool == .select && !selectedIndices.isEmpty {
                    moveSelectionByGrid(dRow: 1, dCol: 0, isRepeat: rep)
                } else {
                    nudgeSelection(dx: 0, dy: nudgeStep(shift), isRepeat: rep)
                }
                return nil
            case 126:
                if activeTool == .select && !selectedIndices.isEmpty {
                    moveSelectionByGrid(dRow: -1, dCol: 0, isRepeat: rep)
                } else {
                    nudgeSelection(dx: 0, dy: -nudgeStep(shift), isRepeat: rep)
                }
                return nil
            default: break
            }

            // Escape cancels anchor mode / clears paste anchor
            if event.keyCode == 53 {
                if isAnchorMode { isAnchorMode = false; return nil }
                if pasteAnchorRow != nil { pasteAnchorRow = nil; pasteAnchorCol = nil; return nil }
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

    private static func firstResponderIsInWebView() -> Bool {
        var view = NSApp.keyWindow?.firstResponder as? NSView
        while let v = view {
            if v is WKWebView { return true }
            view = v.superview
        }
        return false
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
                    layerStates:               self.layerStates,
                    backgroundColor:           self.backgroundColor,
                    backgroundImage:           self.backgroundCGImage,
                    shapePolygonMap:           self.shapePolygonMap,
                    shapePolygonIDMap:         self.shapePolygonIDMap,
                    fallbackPolygons:          self.shapePolygons,
                    projectMotionSets:         self.projectMotionSets,
                    projectAnimatedGeometries: self.projectAnimatedGeometries,
                    colorMapEngines:           self.layerColorMapEngines,
                    backgroundDraw:            self.backgroundDraw,
                    stretchSprites:            self.stretchSpritesToCell,
                    frame:                     self.engine.currentFrame,
                    exportW:                   exportW,
                    exportH:                   exportH,
                    strokeScale:               strokeScale,
                    accumulationBuffer:        self.backgroundDraw ? nil : self.frameBuffer,
                    camera:                    self.camera
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
        let layers     = layerStates.map { $0.toUMLayer() }
        let bg         = backgroundColor
        let polyMap    = shapePolygonMap
        let polyIDMap  = shapePolygonIDMap
        let polys      = shapePolygons
        let cmEngines  = layerColorMapEngines
        let bgDraw     = backgroundDraw
        let stretch    = stretchSpritesToCell
        let fps        = exportFPS
        let frames     = exportFrameCount
        let start      = startFrame
        let camSnap    = camera

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.isExporting    = true
            self.exportProgress = 0.0
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await UMVideoExporter.export(
                        layers:                    layers,
                        backgroundColor:           bg,
                        backgroundImage:           self.backgroundCGImage,
                        shapePolygonMap:           polyMap,
                        shapePolygonIDMap:         polyIDMap,
                        fallbackPolygons:          polys,
                        projectMotionSets:         self.projectMotionSets,
                        projectAnimatedGeometries: self.projectAnimatedGeometries,
                        colorMapEngines:           cmEngines,
                        backgroundDraw:            bgDraw,
                        stretchSprites:            stretch,
                        startFrame:                start,
                        frameCount:                frames,
                        fps:                       fps,
                        exportW:                   exportW,
                        exportH:                   exportH,
                        strokeScale:               strokeScale,
                        camera:                    camSnap,
                        to:                        url,
                        progress:                  { [weak self] p in self?.exportProgress = p }
                    )
                } catch { }
                self.isExporting = false
            }
        }
    }

    func exportCutVideo() {
        let timeline = engine.document.timeline
        guard !timeline.isEmpty else { return }

        let config      = engine.document.gridConfig
        let m           = Double(exportMultiplier)
        let exportW     = config.canvasWidth  * m
        let exportH     = config.canvasHeight * m
        let strokeScale = exportScaleDrawing ? m : 1.0

        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? "umproject"

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.movie]
        panel.nameFieldStringValue = "\(baseName)_cuts_\(f.string(from: Date())).mov"
        panel.directoryURL         = animationsRenderDirectory()

        // Snapshot all data before the async panel response
        let activeIdx   = activeLayerIndex
        let allLayers   = layerStates.map { $0.toUMLayer() }
        let baseLayer   = allLayers[activeIdx]
        let otherLayers = Array(allLayers.enumerated()
                                    .filter { $0.offset != activeIdx }
                                    .map { $0.element })
        let bg          = backgroundColor
        let polyMap     = shapePolygonMap
        let polyIDMap   = shapePolygonIDMap
        let polys       = shapePolygons
        let cmEngines   = layerColorMapEngines
        let bgDraw      = backgroundDraw
        let stretch     = stretchSpritesToCell
        let fps         = exportFPS
        let camSnap     = camera
        let tlSnap      = timeline

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.isExporting    = true
            self.exportProgress = 0.0
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await UMVideoExporter.exportCuts(
                        baseLayer:                 baseLayer,
                        otherLayers:               otherLayers,
                        timeline:                  tlSnap,
                        backgroundColor:           bg,
                        backgroundImage:           self.backgroundCGImage,
                        shapePolygonMap:           polyMap,
                        shapePolygonIDMap:         polyIDMap,
                        fallbackPolygons:          polys,
                        projectMotionSets:         self.projectMotionSets,
                        projectAnimatedGeometries: self.projectAnimatedGeometries,
                        colorMapEngines:           cmEngines,
                        backgroundDraw:            bgDraw,
                        stretchSprites:            stretch,
                        fps:                       fps,
                        exportW:                   exportW,
                        exportH:                   exportH,
                        strokeScale:               strokeScale,
                        camera:                    camSnap,
                        to:                        url,
                        progress:                  { [weak self] p in self?.exportProgress = p }
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
