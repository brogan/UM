import SwiftUI
import UMEngine
import AppKit
import UniformTypeIdentifiers

private enum CanvasPreset: String, CaseIterable {
    case hd      = "HD 1920×1080"
    case fourK   = "4K 3840×2160"
    case square  = "Square 1080×1080"
    case a4Port  = "A4 Portrait"
    case a4Land  = "A4 Landscape"
    case custom  = "Custom"

    var label: String { rawValue }

    var dimensions: (width: Double, height: Double)? {
        switch self {
        case .hd:      return (1920, 1080)
        case .fourK:   return (3840, 2160)
        case .square:  return (1080, 1080)
        case .a4Port:  return (2480, 3508)   // A4 at 300 dpi, portrait
        case .a4Land:  return (3508, 2480)   // A4 at 300 dpi, landscape
        case .custom:  return nil
        }
    }
}

private extension UMColor {
    var swiftUIColor: Color { Color(red: r, green: g, blue: b, opacity: a) }
    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor.black
        self.init(r: Double(ns.redComponent),
                  g: Double(ns.greenComponent),
                  b: Double(ns.blueComponent),
                  a: Double(ns.alphaComponent))
    }
}

struct QuickAdjustView: View {
    @Environment(AppController.self) private var controller

    @State private var projectCollapsed     = false
    @State private var canvasCollapsed      = false
    @State private var placeTimeCollapsed  = false
    @State private var scaleLocked         = true
    @State private var renderCollapsed     = false
    @State private var showFillPalette     = false
    @State private var showStrokePalette   = false
    @State private var motionCollapsed     = false
    @State private var pathCollapsed       = false
    @State private var advancedCollapsed   = true
    @State private var exportCollapsed     = false
    @State private var cameraCollapsed     = false
    @State private var selectedKeyframeID: UUID? = nil
    @State private var newKeyframeFrame: Int = 24

    var body: some View {
        VStack(spacing: 0) {
            styleNameHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    projectSection
                    canvasSection
                    cameraSection
                    exportSection
                    placeTimeSection
                    renderSection
                    motionSection
                    pathSection
                    advancedSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Style name header

    @ViewBuilder
    private var styleNameHeader: some View {
        HStack(spacing: 6) {
            if activeStyleIndex != nil {
                TextField(
                    "Style name",
                    text: Binding(
                        get: {
                            guard let j = activeStyleIndex else { return "" }
                            return controller.projectStyles[j].name
                        },
                        set: { newName in
                            guard let j = activeStyleIndex else { return }
                            controller.projectStyles[j].name = newName
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
            } else {
                Text("No style")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("\(controller.projectStyles.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Sections

    private var projectSection: some View {
        InspectorSection("PROJECT", isCollapsed: $projectCollapsed) {
            InspectorField("Canvas") {
                Picker("", selection: canvasPresetBinding) {
                    ForEach(CanvasPreset.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
            }
            InspectorField("Width") {
                FloatEntryField(value: canvasWidthBinding, width: 58, fractionDigits: 0)
                unitLabel("px")
            }
            InspectorField("Height") {
                FloatEntryField(value: canvasHeightBinding, width: 58, fractionDigits: 0)
                unitLabel("px")
            }
        }
    }

    private var canvasSection: some View {
        InspectorSection("CANVAS", isCollapsed: $canvasCollapsed) {
            InspectorField("Background") {
                ColorWell(color: canvasColorBinding(\.backgroundColor), supportsOpacity: false)
                    .frame(width: 40, height: 24)
            }
            InspectorField("Draw") {
                Toggle("Background draw", isOn: Binding(
                    get: { controller.backgroundDraw },
                    set: { controller.backgroundDraw = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            }
            InspectorField("Capture") {
                Slider(
                    value: captureIntervalBinding,
                    in: 0.5...8.0,
                    step: 0.5
                )
                .labelsHidden()
                Text(String(format: "%.1f s", controller.recordingIntervalSeconds))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
            }
            InspectorField("Grid") {
                Toggle("Show grid", isOn: Binding(
                    get: { controller.showGrid },
                    set: { controller.showGrid = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            }
            InspectorField("Grid color") {
                ColorWell(color: canvasColorBinding(\.gridColor), supportsOpacity: true)
                    .frame(width: 40, height: 24)
                    .disabled(!controller.showGrid)
            }
            InspectorField("Grid width") {
                FloatEntryField(
                    value: Binding(
                        get: { controller.gridLineWidth },
                        set: { controller.gridLineWidth = max(0.1, $0) }
                    ),
                    width: 50, fractionDigits: 1
                )
                .disabled(!controller.showGrid)
                unitLabel("px")
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 3)

            InspectorField("Color Map") {
                if controller.colorMapEngine.isLoading {
                    ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                    Text("Loading…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if controller.colorMapEngine.isLoaded,
                          let src = controller.engine.document.colorSource {
                    if controller.colorMapEngine.isVideo {
                        Image(systemName: "film")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text(src.fileName)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { controller.clearColorSource() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear color map")
                } else {
                    Button("Choose…") { chooseColorSource() }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if controller.colorMapEngine.isLoaded,
               controller.engine.document.colorSource != nil {

                InspectorField("Apply to") {
                    Picker("", selection: colorMapApplyBinding) {
                        ForEach(ColorApplyTarget.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 90)
                }

                InspectorField("Style α") {
                    Toggle("Preserve", isOn: colorMapAlphaBinding)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }

                if controller.colorMapEngine.isVideo {
                    InspectorField("Loop") {
                        Picker("", selection: colorMapLoopBinding) {
                            ForEach(VideoLoopMode.allCases, id: \.self) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 90)
                    }
                    Text("\(controller.colorMapEngine.extractedFrameCount) fr extracted")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                }

            }

            if controller.colorMapEngine.isLoaded || controller.hasColorMapLock {
                InspectorField("Lock") {
                    Button(action: { controller.lockColorMap() }) {
                        Label("Lock", systemImage: "lock.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .disabled(!controller.colorMapEngine.isLoaded)
                    .help(controller.selectedIndices.isEmpty
                          ? "Bake color map colors into all drawn cells"
                          : "Bake color map colors into selected cells")

                    Button(action: { controller.unlockColorMap() }) {
                        Label("Unlock", systemImage: "lock.open")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(controller.hasColorMapLock ? Color.accentColor : Color.secondary)
                    .disabled(!controller.hasColorMapLock)
                    .help(controller.selectedIndices.isEmpty
                          ? "Remove locked colors from all drawn cells"
                          : "Remove locked colors from selected cells")
                }

                if controller.hasColorMapLock {
                    Text("⚑ \(controller.selectedIndices.isEmpty ? "Layer" : "Selection") has locked colors")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func chooseColorSource() {
        let panel = NSOpenPanel()
        panel.title = "Choose Color Source"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.allowedContentTypes     = [.image, .movie]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            controller.loadColorSource(url: url)
        }
    }

    private var colorMapApplyBinding: Binding<ColorApplyTarget> {
        Binding(
            get: { controller.engine.document.colorSource?.applyTo ?? .fill },
            set: { controller.engine.document.colorSource?.applyTo = $0 }
        )
    }

    private var colorMapAlphaBinding: Binding<Bool> {
        Binding(
            get: { controller.engine.document.colorSource?.preserveStyleAlpha ?? true },
            set: { controller.engine.document.colorSource?.preserveStyleAlpha = $0 }
        )
    }

    private var colorMapLoopBinding: Binding<VideoLoopMode> {
        Binding(
            get: { controller.engine.document.colorSource?.videoLoopMode ?? .loop },
            set: { controller.engine.document.colorSource?.videoLoopMode = $0 }
        )
    }

    private func canvasColorBinding(_ kp: ReferenceWritableKeyPath<AppController, UMColor>) -> Binding<Color> {
        Binding(
            get: { controller[keyPath: kp].swiftUIColor },
            set: { controller[keyPath: kp] = UMColor($0) }
        )
    }

    private var captureIntervalBinding: Binding<Double> {
        Binding(
            get: { controller.recordingIntervalSeconds },
            set: { controller.recordingIntervalSeconds = $0 }
        )
    }

    // MARK: - Camera section

    private var cameraSection: some View {
        @Bindable var ctrl = controller
        return InspectorSection("CAMERA", isCollapsed: $cameraCollapsed) {
            InspectorField("Pan X") {
                Slider(value: Binding(
                    get: { ctrl.camera.pan.base.x },
                    set: { ctrl.camera.pan.base.x = $0 }
                ), in: -500...500)
                .frame(maxWidth: 110)
                Text(String(format: "%.0f", ctrl.camera.pan.base.x))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            InspectorField("Pan Y") {
                Slider(value: Binding(
                    get: { ctrl.camera.pan.base.y },
                    set: { ctrl.camera.pan.base.y = $0 }
                ), in: -500...500)
                .frame(maxWidth: 110)
                Text(String(format: "%.0f", ctrl.camera.pan.base.y))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            InspectorField("Zoom") {
                Slider(value: Binding(
                    get: { ctrl.camera.zoom.base },
                    set: { ctrl.camera.zoom.base = $0 }
                ), in: 0.1...4.0)
                .frame(maxWidth: 110)
                Text(String(format: "%.2f×", ctrl.camera.zoom.base))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            InspectorField("Rotation") {
                Slider(value: Binding(
                    get: { ctrl.camera.rotation.base },
                    set: { ctrl.camera.rotation.base = $0 }
                ), in: -180...180)
                .frame(maxWidth: 110)
                Text(String(format: "%.0f°", ctrl.camera.rotation.base))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            InspectorField("") {
                Button("Reset") {
                    ctrl.camera = .identity
                }
                .font(.system(size: 11))
                .disabled(ctrl.camera == .identity)
            }
        }
    }

    private var exportSection: some View {
        @Bindable var ctrl = controller
        return InspectorSection("EXPORT", isCollapsed: $exportCollapsed) {
            InspectorField("Multiplier") {
                Picker("", selection: $ctrl.exportMultiplier) {
                    Text("1×").tag(1)
                    Text("2×").tag(2)
                    Text("4×").tag(4)
                    Text("8×").tag(8)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            InspectorField("Scale drawing") {
                Toggle("", isOn: $ctrl.exportScaleDrawing)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Scale stroke widths with the multiplier")
            }
            InspectorField("Output") {
                let m = controller.exportMultiplier
                let w = Int(controller.engine.document.gridConfig.canvasWidth  * Double(m))
                let h = Int(controller.engine.document.gridConfig.canvasHeight * Double(m))
                Text("\(w) × \(h) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            InspectorField("FPS") {
                Picker("", selection: $ctrl.exportFPS) {
                    Text("24").tag(24)
                    Text("30").tag(30)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 80)
            }
            InspectorField("Frames") {
                FloatEntryField(value: Binding(
                    get: { Double(controller.exportFrameCount) },
                    set: { controller.exportFrameCount = max(1, Int($0)) }
                ), width: 52, fractionDigits: 0)
                Text(String(format: "%.1f s", controller.exportDurationSeconds))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var placeTimeSection: some View {
        InspectorSection("PLACE & TIME", isCollapsed: $placeTimeCollapsed) {
            let hasSelection = !controller.selectedIndices.isEmpty

            InspectorField("Style") {
                Picker("", selection: selectionStyleBinding) {
                    ForEach(controller.projectStyles) { style in
                        Text(style.name).tag(style.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
                .disabled(!hasSelection)
            }
            InspectorField("Path") {
                Picker("", selection: selectionPathBinding) {
                    Text("None").tag(nil as UUID?)
                    ForEach(controller.engine.document.paths) { path in
                        Text(path.name).tag(Optional(path.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
                .disabled(!hasSelection)
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 2)

            InspectorField("Offset X") {
                FloatEntryField(value: offsetDxBinding, width: 58, fractionDigits: 1)
                    .disabled(!hasSelection)
                unitLabel("px")
            }
            InspectorField("Offset Y") {
                FloatEntryField(value: offsetDyBinding, width: 58, fractionDigits: 1)
                    .disabled(!hasSelection)
                unitLabel("px")
            }
            InspectorField("Phase") {
                FloatEntryField(value: phaseBinding, width: 58, fractionDigits: 0)
                    .disabled(!hasSelection)
                unitLabel("fr")
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 2)

            if scaleLocked {
                InspectorField("Scale") {
                    ResettableSlider(value: scaleBothBinding, range: 0.1...3.0, defaultValue: 1.0)
                        .disabled(!hasSelection)
                    valueLabel(focusedCell?.scaleX ?? 1, digits: 2)
                    Button { scaleLocked = false } label: {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Proportional — click to unlock X/Y independently")
                }
            } else {
                InspectorField("Scale X") {
                    ResettableSlider(value: scaleXBinding, range: 0.1...3.0, defaultValue: 1.0)
                        .disabled(!hasSelection)
                    valueLabel(focusedCell?.scaleX ?? 1, digits: 2)
                    Button { scaleLocked = true } label: {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Independent — click to link X and Y")
                }
                InspectorField("Scale Y") {
                    ResettableSlider(value: scaleYBinding, range: 0.1...3.0, defaultValue: 1.0)
                        .disabled(!hasSelection)
                    valueLabel(focusedCell?.scaleY ?? 1, digits: 2)
                }
            }

            InspectorField("Rotation") {
                ResettableSlider(value: rotationBinding, range: -180...180, defaultValue: 0)
                    .disabled(!hasSelection)
                valueLabel(focusedCell?.rotation ?? 0, digits: 1)
                unitLabel("°")
            }

            if hasSelection {
                HStack(spacing: 8) {
                    Text("\(controller.selectedIndices.count) cell\(controller.selectedIndices.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Rescatter") {
                        controller.engine.pushUndoSnapshot()
                        controller.engine.rescatterSelection(controller.selectedIndices)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.top, 3)
                .padding(.bottom, 2)
            } else {
                Text("Select cells to edit placement")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 12)
                    .padding(.top, 3)
                    .padding(.bottom, 4)
            }
        }
    }

    private var renderSection: some View {
        InspectorSection("RENDER", isCollapsed: $renderCollapsed) {
            let disabled = activeStyleIndex == nil

            InspectorField("Fill") {
                ColorWell(color: colorBinding(\.fillColor), supportsOpacity: true)
                    .frame(width: 40, height: 24)
                    .disabled(disabled)
                Button {
                    showFillPalette.toggle()
                } label: {
                    Image(systemName: "swatchpalette")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(disabled || controller.projectColorPalettes.isEmpty ? Color.secondary.opacity(0.3) : Color.secondary)
                .disabled(disabled || controller.projectColorPalettes.isEmpty)
                .popover(isPresented: $showFillPalette, arrowEdge: .trailing) {
                    ColorPalettePickerView { color in
                        guard let i = activeStyleIndex else { return }
                        controller.projectStyles[i].fillColor = color
                    }
                    .environment(controller)
                }
            }
            InspectorField("Stroke") {
                ColorWell(color: colorBinding(\.strokeColor), supportsOpacity: true)
                    .frame(width: 40, height: 24)
                    .disabled(disabled)
                Button {
                    showStrokePalette.toggle()
                } label: {
                    Image(systemName: "swatchpalette")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(disabled || controller.projectColorPalettes.isEmpty ? Color.secondary.opacity(0.3) : Color.secondary)
                .disabled(disabled || controller.projectColorPalettes.isEmpty)
                .popover(isPresented: $showStrokePalette, arrowEdge: .trailing) {
                    ColorPalettePickerView { color in
                        guard let i = activeStyleIndex else { return }
                        controller.projectStyles[i].strokeColor = color
                    }
                    .environment(controller)
                }
            }
            InspectorField("Width") {
                FloatEntryField(value: styleBinding(\.strokeWidth, fallback: 1.5),
                                width: 50, fractionDigits: 1)
                    .disabled(disabled)
                unitLabel("px")
            }
            InspectorField("Mode") {
                Picker("", selection: styleBinding(\.renderMode, fallback: .filledStroked)) {
                    ForEach(UMRenderMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 130)
                .disabled(disabled)
            }
        }
    }

    // MARK: - Motion section

    @ViewBuilder
    private var motionSection: some View {
        if let ms = controller.activeMotionSet {
            InspectorSection("MOTION — \(ms.name)", isCollapsed: $motionCollapsed) {
                InspectorField("Preset") {
                    Picker("", selection: motionPresetBinding) {
                        ForEach(MotionPreset.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 130)
                }
                InspectorField("Speed") {
                    Slider(value: motionSpeedBinding, in: 0...2)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.2f×", ms.motionSpeed))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 38, alignment: .trailing)
                }
                InspectorField("Amount") {
                    Slider(value: motionAmountBinding, in: 0...1)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.2f", ms.motionAmount))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 38, alignment: .trailing)
                }
                InspectorField("Phase") {
                    Slider(value: motionPhaseBinding, in: 0...1)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.2f", ms.motionPhase))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 38, alignment: .trailing)
                }
                Divider().padding(.horizontal, 12).padding(.vertical, 3)
                InspectorField("Order/Chaos") {
                    Slider(value: motionOrderChaosBinding, in: 0...1)
                        .frame(maxWidth: 100)
                    Text(String(format: "%.2f", ms.orderChaos))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Path editor section

    private var pathSection: some View {
        InspectorSection("PATH EDITOR", isCollapsed: $pathCollapsed) {
            // Active path picker + create/delete controls
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { controller.activePathID },
                    set: { controller.activePathID = $0; selectedKeyframeID = nil }
                )) {
                    Text("—").tag(nil as UUID?)
                    ForEach(controller.engine.document.paths) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Button { controller.createPath(); selectedKeyframeID = nil } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New path")

                if controller.activePathID != nil {
                    Button {
                        if let id = controller.activePathID { controller.deletePath(id) }
                        selectedKeyframeID = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Delete path")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if let pi = activePathIndex {
                // Path name field
                InspectorField("Name") {
                    TextField("Name", text: Binding(
                        get: { pi < controller.engine.document.paths.count ? controller.engine.document.paths[pi].name : "" },
                        set: { if pi < controller.engine.document.paths.count { controller.engine.document.paths[pi].name = $0 } }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                }

                // Loop toggle + duration read-out
                HStack(spacing: 0) {
                    Toggle("Loop", isOn: Binding(
                        get: { pi < controller.engine.document.paths.count && controller.engine.document.paths[pi].loops },
                        set: { if pi < controller.engine.document.paths.count { controller.engine.document.paths[pi].loops = $0 } }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .padding(.leading, 12)
                    Spacer()
                    Text("\(controller.engine.document.paths[pi].duration) fr")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .padding(.trailing, 12)
                }
                .padding(.vertical, 4)

                Divider().padding(.horizontal, 12)

                // Keyframe list
                VStack(spacing: 0) {
                    ForEach(controller.engine.document.paths[pi].keyframes) { kf in
                        keyframeRow(kf, pathIndex: pi)
                    }
                }

                // Add keyframe row
                HStack(spacing: 6) {
                    Text("Add at")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Stepper("\(newKeyframeFrame) fr",
                            value: $newKeyframeFrame, in: 0...9999, step: 1)
                        .font(.system(size: 11))
                    Button {
                        controller.addKeyframe(frame: newKeyframeFrame,
                                               to: controller.engine.document.paths[pi].id)
                        // Select the newly added keyframe
                        selectedKeyframeID = controller.engine.document.paths[pi]
                            .keyframes.first(where: { $0.frame == newKeyframeFrame })?.id
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                // Keyframe property editor (shown when one is selected)
                if let ki = selectedKeyframeIndex {
                    Divider().padding(.horizontal, 12)
                    keyframeEditor(pathIndex: pi, keyframeIndex: ki)
                }
            } else {
                Text("Select or create a path above to edit its keyframes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: controller.activePathID) { selectedKeyframeID = nil }
    }

    @ViewBuilder
    private func keyframeRow(_ kf: PathKeyframe, pathIndex pi: Int) -> some View {
        let selected = kf.id == selectedKeyframeID
        HStack(spacing: 4) {
            Text("\(kf.frame)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(width: 32, alignment: .trailing)
            Text(String(format: "dx%.2f dy%.2f", kf.dx, kf.dy))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if abs(kf.rotation) > 0.01 {
                Text(String(format: "%.0f°", kf.rotation))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // Only allow delete if the path still has > 2 keyframes
            Button {
                let pathID = controller.engine.document.paths[pi].id
                controller.removeKeyframe(id: kf.id, from: pathID)
                if selectedKeyframeID == kf.id { selectedKeyframeID = nil }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(controller.engine.document.paths[pi].keyframes.count <= 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedKeyframeID = (selectedKeyframeID == kf.id) ? nil : kf.id
        }
    }

    @ViewBuilder
    private func keyframeEditor(pathIndex pi: Int, keyframeIndex ki: Int) -> some View {
        let kf = controller.engine.document.paths[pi].keyframes[ki]

        VStack(alignment: .leading, spacing: 0) {
            // Frame stepper
            InspectorField("Frame") {
                Stepper("\(kf.frame) fr",
                        value: Binding(
                            get: {
                                guard pi < controller.engine.document.paths.count,
                                      ki < controller.engine.document.paths[pi].keyframes.count else { return 0 }
                                return controller.engine.document.paths[pi].keyframes[ki].frame
                            },
                            set: { val in
                                guard pi < controller.engine.document.paths.count,
                                      ki < controller.engine.document.paths[pi].keyframes.count else { return }
                                controller.engine.document.paths[pi].keyframes[ki].frame = max(0, val)
                                controller.engine.document.paths[pi].keyframes.sort { $0.frame < $1.frame }
                            }
                        ),
                        in: 0...9999, step: 1)
                    .font(.system(size: 11))
            }

            InspectorField("Offset X") {
                ResettableSlider(
                    value: Binding(
                        get: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return 0 }
                            return controller.engine.document.paths[pi].keyframes[ki].dx
                        },
                        set: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return }
                            controller.engine.document.paths[pi].keyframes[ki].dx = $0
                        }
                    ),
                    range: -3...3,
                    defaultValue: 0
                )
                valueLabel(kf.dx, digits: 2)
                unitLabel("c")
            }
            InspectorField("Offset Y") {
                ResettableSlider(
                    value: Binding(
                        get: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return 0 }
                            return controller.engine.document.paths[pi].keyframes[ki].dy
                        },
                        set: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return }
                            controller.engine.document.paths[pi].keyframes[ki].dy = $0
                        }
                    ),
                    range: -3...3,
                    defaultValue: 0
                )
                valueLabel(kf.dy, digits: 2)
                unitLabel("c")
            }
            InspectorField("Rotation") {
                ResettableSlider(
                    value: Binding(
                        get: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return 0 }
                            return controller.engine.document.paths[pi].keyframes[ki].rotation
                        },
                        set: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return }
                            controller.engine.document.paths[pi].keyframes[ki].rotation = $0
                        }
                    ),
                    range: -360...360,
                    defaultValue: 0
                )
                valueLabel(kf.rotation, digits: 1)
                unitLabel("°")
            }
            InspectorField("Scale X") {
                ResettableSlider(
                    value: Binding(
                        get: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return 1 }
                            return controller.engine.document.paths[pi].keyframes[ki].scaleX
                        },
                        set: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return }
                            controller.engine.document.paths[pi].keyframes[ki].scaleX = max(0.01, $0)
                        }
                    ),
                    range: 0.1...3,
                    defaultValue: 1
                )
                valueLabel(kf.scaleX, digits: 2)
            }
            InspectorField("Scale Y") {
                ResettableSlider(
                    value: Binding(
                        get: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return 1 }
                            return controller.engine.document.paths[pi].keyframes[ki].scaleY
                        },
                        set: {
                            guard pi < controller.engine.document.paths.count,
                                  ki < controller.engine.document.paths[pi].keyframes.count else { return }
                            controller.engine.document.paths[pi].keyframes[ki].scaleY = max(0.01, $0)
                        }
                    ),
                    range: 0.1...3,
                    defaultValue: 1
                )
                valueLabel(kf.scaleY, digits: 2)
            }
            InspectorField("Easing") {
                Picker("", selection: Binding(
                    get: {
                        guard pi < controller.engine.document.paths.count,
                              ki < controller.engine.document.paths[pi].keyframes.count else { return PathEasing.easeInOut }
                        return controller.engine.document.paths[pi].keyframes[ki].easing
                    },
                    set: {
                        guard pi < controller.engine.document.paths.count,
                              ki < controller.engine.document.paths[pi].keyframes.count else { return }
                        controller.engine.document.paths[pi].keyframes[ki].easing = $0
                    }
                )) {
                    ForEach(PathEasing.allCases, id: \.self) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 120)
            }
        }
    }

    // MARK: - Path helper bindings/indices

    private var activePathIndex: Int? {
        guard let id = controller.activePathID else { return nil }
        return controller.engine.document.paths.firstIndex { $0.id == id }
    }

    private var selectedKeyframeIndex: Int? {
        guard let pi = activePathIndex, let kfID = selectedKeyframeID else { return nil }
        return controller.engine.document.paths[pi].keyframes.firstIndex { $0.id == kfID }
    }

    private var selectionPathBinding: Binding<UUID?> {
        Binding(
            get: { focusedCell?.pathID },
            set: { controller.assignPathToSelection($0) }
        )
    }

    // MARK: - Sequence section

    private var advancedSection: some View {
        InspectorSection("ADVANCED", isCollapsed: $advancedCollapsed) {
            Text("Renderer set, subdivision params\n— available in Phase 4")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Small view helpers

    private func valueLabel(_ v: Double, digits: Int) -> some View {
        Text(v.formatted(.number.precision(.fractionLength(digits))))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 32, alignment: .trailing)
    }

    private func unitLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
    }

    // MARK: - Motion bindings

    private var activeMotionIndex: Int? {
        guard let id = controller.activeMotionID else { return nil }
        return controller.projectMotionSets.firstIndex { $0.id == id }
    }

    private var motionPresetBinding: Binding<MotionPreset> {
        Binding(
            get: { controller.activeMotionSet?.motionPreset ?? .static },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionPreset = $0 } }
        )
    }

    private var motionSpeedBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.motionSpeed ?? 1 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionSpeed = $0 } }
        )
    }

    private var motionAmountBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.motionAmount ?? 0.5 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionAmount = $0 } }
        )
    }

    private var motionPhaseBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.motionPhase ?? 0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionPhase = $0 } }
        )
    }

    private var motionOrderChaosBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.orderChaos ?? 0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].orderChaos = $0 } }
        )
    }

    // MARK: - Bindings

    private var activeStyleIndex: Int? {
        guard let id = controller.activeStyleID else { return nil }
        return controller.projectStyles.firstIndex { $0.id == id }
    }

    private func colorBinding(_ kp: WritableKeyPath<CellStyle, UMColor>) -> Binding<Color> {
        Binding(
            get: {
                guard let i = activeStyleIndex else { return .accentColor }
                return controller.projectStyles[i][keyPath: kp].swiftUIColor
            },
            set: { color in
                guard let i = activeStyleIndex else { return }
                controller.projectStyles[i][keyPath: kp] = UMColor(color)
            }
        )
    }

    private func styleBinding<T>(_ kp: WritableKeyPath<CellStyle, T>, fallback: T) -> Binding<T> {
        Binding(
            get: {
                guard let i = activeStyleIndex else { return fallback }
                return controller.projectStyles[i][keyPath: kp]
            },
            set: { val in
                guard let i = activeStyleIndex else { return }
                controller.projectStyles[i][keyPath: kp] = val
            }
        )
    }

    private var focusedCell: UMGridCell? {
        guard let idx = controller.selectedIndices.first,
              idx < controller.engine.document.cells.count
        else { return nil }
        return controller.engine.document.cells[idx]
    }

    private var offsetDxBinding: Binding<Double> {
        Binding(
            get: { focusedCell?.positionOffset.dx ?? 0 },
            set: { val in
                for i in controller.selectedIndices
                    where i < controller.engine.document.cells.count {
                    controller.engine.document.cells[i].positionOffset.dx = val
                }
            }
        )
    }

    private var offsetDyBinding: Binding<Double> {
        Binding(
            get: { focusedCell?.positionOffset.dy ?? 0 },
            set: { val in
                for i in controller.selectedIndices
                    where i < controller.engine.document.cells.count {
                    controller.engine.document.cells[i].positionOffset.dy = val
                }
            }
        )
    }

    private var phaseBinding: Binding<Double> {
        Binding(
            get: { Double(focusedCell?.phaseOffset ?? 0) },
            set: { val in
                for i in controller.selectedIndices
                    where i < controller.engine.document.cells.count {
                    controller.engine.document.cells[i].phaseOffset = Int(val.rounded())
                }
            }
        )
    }

    private var scaleBothBinding: Binding<Double> {
        Binding(
            get: { focusedCell?.scaleX ?? 1 },
            set: { val in
                let v = max(0.01, val)
                for i in controller.selectedIndices
                    where i < controller.engine.document.cells.count {
                    controller.engine.document.cells[i].scaleX = v
                    controller.engine.document.cells[i].scaleY = v
                }
            }
        )
    }

    private var scaleXBinding: Binding<Double> {
        Binding(
            get: { focusedCell?.scaleX ?? 1 },
            set: { val in
                let v = max(0.01, val)
                for i in controller.selectedIndices
                    where i < controller.engine.document.cells.count {
                    controller.engine.document.cells[i].scaleX = v
                    if scaleLocked { controller.engine.document.cells[i].scaleY = v }
                }
            }
        )
    }

    private var scaleYBinding: Binding<Double> {
        Binding(
            get: { focusedCell?.scaleY ?? 1 },
            set: { val in
                let v = max(0.01, val)
                for i in controller.selectedIndices
                    where i < controller.engine.document.cells.count {
                    controller.engine.document.cells[i].scaleY = v
                    if scaleLocked { controller.engine.document.cells[i].scaleX = v }
                }
            }
        )
    }

    private var selectionStyleBinding: Binding<UUID> {
        Binding(
            get: { focusedCell?.styleID ?? controller.activeStyleID ?? UUID() },
            set: { controller.assignStyleToSelection($0) }
        )
    }

    private var rotationBinding: Binding<Double> {
        Binding(
            get: { focusedCell?.rotation ?? 0 },
            set: { val in
                for i in controller.selectedIndices
                    where i < controller.engine.document.cells.count {
                    controller.engine.document.cells[i].rotation = val
                }
            }
        )
    }

    private var canvasPresetBinding: Binding<CanvasPreset> {
        Binding(
            get: {
                let w = controller.engine.document.gridConfig.canvasWidth
                let h = controller.engine.document.gridConfig.canvasHeight
                return CanvasPreset.allCases.first {
                    $0.dimensions?.width == w && $0.dimensions?.height == h
                } ?? .custom
            },
            set: { preset in
                guard let dims = preset.dimensions else { return }
                controller.engine.document.gridConfig.canvasWidth  = dims.width
                controller.engine.document.gridConfig.canvasHeight = dims.height
            }
        )
    }

    private var canvasWidthBinding: Binding<Double> {
        Binding(
            get: { controller.engine.document.gridConfig.canvasWidth },
            set: { controller.engine.document.gridConfig.canvasWidth = max(1, $0) }
        )
    }

    private var canvasHeightBinding: Binding<Double> {
        Binding(
            get: { controller.engine.document.gridConfig.canvasHeight },
            set: { controller.engine.document.gridConfig.canvasHeight = max(1, $0) }
        )
    }

}
