import SwiftUI
import Observation
import AppKit
import UMEngine
import LoomEngine

@Observable
@MainActor
final class AppController {
    var engine: UMGridEngine
    var shapePolygons: [Polygon2D] = []

    // UI state
    var activeTool: PaintTool        = .draw
    var transformMode: TransformMode = .move
    var stampPhaseOffset: Int        = 0
    var stretchSpritesToCell: Bool   = true
    var showGrid: Bool               = false
    var gridColor: UMColor           = UMColor(r: 0.5, g: 0.5, b: 0.5, a: 1)
    var gridLineWidth: Double        = 0.5
    var backgroundColor: UMColor     = UMColor(r: 1, g: 1, b: 1, a: 1)
    var isPlaying: Bool              = false
    var selectedIndices: Set<Int> = []
    var activeStyleID: UUID?     = nil

    var currentFileURL: URL? = nil
    var globalLibrary: UMLibrary = .empty
    var globalShapes:  [UMShape] = []

    private var playbackTask: Task<Void, Never>?
    private nonisolated(unsafe) var keyMonitor: Any?

    init() {
        let doc = UMGridDocument.makeTestGrid()
        engine = UMGridEngine(document: doc)
        activeStyleID = doc.styles.first?.id
        loadShapePolygons()
        ensureProjectsDirectory()
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

    var backgroundDraw: Bool = true {
        didSet { if backgroundDraw { frameBuffer = nil } }
    }
    private(set) var frameBuffer: CGImage? = nil

    // MARK: - Recording & timeline

    var isRecording: Bool = false
    var recordingInterval: Int = 48   // frames between auto-captures (2 s at 24 fps)
    var timelinePosition: Int = -1    // -1 = live mode; 0+ = viewing a timeline state
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
                                    styles: engine.document.styles,
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
        engine.document.styles     = state.styles
        selectedIndices = []   // stale indices from a different resolution grid
        timelinePosition = index
        stateFrameCount  = 0
        if let id = activeStyleID, !engine.document.styles.contains(where: { $0.id == id }) {
            activeStyleID = engine.document.styles.first?.id
        }
    }

    func stepTimeline(forward: Bool) {
        let count = engine.document.timeline.count
        guard count > 0 else { return }
        let base    = timelinePosition < 0 ? (forward ? 0 : count - 1)
                                           : (forward ? timelinePosition + 1 : timelinePosition - 1)
        let next    = (base + count) % count
        navigateToState(next)
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
        engine.seek(toFrame: 0)
        if !engine.document.timeline.isEmpty {
            navigateToState(0)
        } else {
            timelinePosition = -1
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            // If a timeline exists and we're in live mode, begin at state 0
            if !engine.document.timeline.isEmpty && timelinePosition < 0 {
                navigateToState(0)
            }
            if timelinePosition >= 0 { stateFrameCount = 0 }
            playbackTask = Task { @MainActor [weak self] in
                while let self, !Task.isCancelled, self.isPlaying {
                    self.engine.advance()

                    // Auto-capture during recording
                    if self.isRecording && self.engine.currentFrame % self.recordingInterval == 0 {
                        self.captureState()
                    }

                    // Advance through timeline states when in timeline mode (not recording)
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
                            self.engine.document.styles     = tl[next].styles
                            self.selectedIndices = []
                        }
                    }

                    try? await Task.sleep(nanoseconds: 41_666_667) // 24 fps
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

    // Active style (currently selected in the Style Palette for painting)
    var activeStyle: CellStyle? {
        guard let id = activeStyleID else { return nil }
        return engine.document.styles.first { $0.id == id }
    }

    // MARK: - Projects directory

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
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Document title

    var documentTitle: String {
        guard let url = currentFileURL else { return "UM — Untitled" }
        return "UM — \(url.deletingPathExtension().lastPathComponent)"
    }

    // MARK: - Save / Load

    func newDocument() {
        let doc = UMGridDocument.makeTestGrid()
        engine        = UMGridEngine(document: doc)
        activeStyleID = doc.styles.first?.id
        selectedIndices = []
        currentFileURL  = nil
    }

    func saveDocument() {
        if let url = currentFileURL { write(to: url) } else { saveDocumentAs() }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.title = "Save UM Project"
        panel.directoryURL = currentFileURL?.deletingLastPathComponent()
                             ?? projectsDirectory
        panel.nameFieldStringValue = currentFileURL?
            .deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.allowedFileTypes = ["umproj"]   // TODO: replace with UTType once Info.plist is wired
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
            Task { @MainActor [weak self] in
                self?.read(from: url)
            }
        }
    }

    private func write(to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(engine.document) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func read(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let doc  = try? JSONDecoder().decode(UMGridDocument.self, from: data)
        else { return }
        engine          = UMGridEngine(document: doc)
        activeStyleID   = doc.styles.first?.id
        selectedIndices = []
        currentFileURL  = url
        colorMapEngine.clear()
        if let src = doc.colorSource {
            let rows = doc.gridConfig.rows
            let cols = doc.gridConfig.cols
            colorMapEngine.load(url: URL(fileURLWithPath: src.filePath), rows: rows, cols: cols)
        }
    }

    // MARK: - Global library

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
        guard let style = engine.document.styles.first(where: { $0.id == styleID }) else { return }
        let variant = style.applying(transform)
        engine.document.styles.append(variant)
        activeStyleID = variant.id
    }

    func deleteStyle(_ styleID: UUID) {
        guard engine.document.styles.count > 1 else { return }
        engine.pushUndoSnapshot()
        let fallbackID = engine.document.styles.first { $0.id != styleID }?.id ?? UUID()
        for i in engine.document.cells.indices where engine.document.cells[i].styleID == styleID {
            engine.document.cells[i].styleID = fallbackID
        }
        engine.document.styles.removeAll { $0.id == styleID }
        if activeStyleID == styleID { activeStyleID = engine.document.styles.first?.id }
    }

    // MARK: Style library operations

    func promoteStyleToLibrary(_ styleID: UUID) {
        guard let style = engine.document.styles.first(where: { $0.id == styleID }) else { return }
        if let idx = globalLibrary.styles.firstIndex(where: { $0.id == styleID }) {
            globalLibrary.styles[idx] = style   // update existing entry
        } else {
            globalLibrary.styles.append(style)
        }
        saveGlobalLibrary()
    }

    func importStyleFromLibrary(_ libraryStyleID: UUID) {
        guard let style = globalLibrary.styles.first(where: { $0.id == libraryStyleID }) else { return }
        guard !engine.document.styles.contains(where: { $0.id == libraryStyleID }) else { return }
        engine.document.styles.append(style)
        activeStyleID = style.id
    }

    func removeStyleFromLibrary(_ libraryStyleID: UUID) {
        globalLibrary.styles.removeAll { $0.id == libraryStyleID }
        saveGlobalLibrary()
    }

    // MARK: - Path management

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
        else { return }                     // always keep at least 2 keyframes
        engine.document.paths[pi].removeKeyframe(id: kfID)
    }

    // MARK: Path library operations

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

    // MARK: - Color map

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

    // MARK: - Shape management

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
    }

    func deleteShape(_ id: UUID) {
        engine.document.shapes.removeAll { $0.id == id }
        for i in engine.document.styles.indices where engine.document.styles[i].shapeID == id {
            engine.document.styles[i].shapeID = nil
        }
    }

    func assignShape(_ shapeID: UUID?, toStyle styleID: UUID) {
        guard let i = engine.document.styles.firstIndex(where: { $0.id == styleID }) else { return }
        engine.document.styles[i].shapeID = shapeID
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
    }

    func removeShapeFromLibrary(_ id: UUID) {
        let url = Self.globalShapesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        globalShapes.removeAll { $0.id == id }
    }

    // MARK: - Keyboard

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Never steal events from text inputs
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            // Ignore events that carry Command / Option / Control (let menus handle those)
            if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty { return event }

            let shift = event.modifierFlags.contains(.shift)

            let rep = event.isARepeat
            switch event.keyCode {
            // Arrow-key nudge — works in any tool when cells are selected
            case 123: nudgeSelection(dx: -nudgeStep(shift), dy:  0, isRepeat: rep); return nil  // ←
            case 124: nudgeSelection(dx:  nudgeStep(shift), dy:  0, isRepeat: rep); return nil  // →
            case 125: nudgeSelection(dx:  0, dy:  nudgeStep(shift), isRepeat: rep); return nil  // ↓
            case 126: nudgeSelection(dx:  0, dy: -nudgeStep(shift), isRepeat: rep); return nil  // ↑
            default: break
            }

            // Single-character shortcuts (ignore if Shift is held to avoid conflicts)
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

    func assignStyleToSelection(_ styleID: UUID) {
        guard !selectedIndices.isEmpty else { return }
        engine.pushUndoSnapshot()
        for i in selectedIndices where i < engine.document.cells.count {
            engine.document.cells[i].styleID = styleID
        }
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
}

enum TransformMode {
    case move   // cells relocate to the transformed position (replaces)
    case stamp  // original cells stay; transformed copy is painted on top
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
