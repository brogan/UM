import SwiftUI
import UMEngine
import LoomEngine
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
    @State private var cameraCollapsed      = false
    @State private var gridScrollCollapsed  = true
    @State private var kfInspectorCollapsed = false
    // controller.selectedPathKeyframeID is now controller.selectedPathKeyframeID (shared with canvas overlay)
    @State private var newKeyframeFrame: Int = 24
    @State private var spritesCollapsed      = false
    @State private var shapeCollapsed        = false
    @State private var layerDriversCollapsed = true
    @State private var distortionSeed: UInt64 = 42

    var body: some View {
        VStack(spacing: 0) {
            styleNameHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let activeLayerMode = controller.layerStates[controller.activeLayerIndex].layerMode
                    kfInspectorSection
                    projectSection
                    canvasSection
                    cameraSection
                    layerDriversSection
                    exportSection
                    if activeLayerMode == .sprite {
                        spritesSection
                        motionSection
                    } else {
                        gridScrollSection
                        placeTimeSection
                        renderSection
                        motionSection
                        shapeSection
                        pathSection
                        advancedSection
                        nothingActiveHint
                    }
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
            InspectorField("Bg Image") {
                if controller.backgroundCGImage != nil,
                   let name = controller.backgroundImagePath.map({ URL(fileURLWithPath: $0).lastPathComponent }) {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { controller.clearBackgroundImage() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
                    .help("Clear background image")
                } else {
                    Button("Choose…") { chooseBgImage() }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
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
            InspectorField("Phase map") {
                Toggle("Phase heatmap", isOn: Binding(
                    get: { controller.showPhaseHeatmap },
                    set: { controller.showPhaseHeatmap = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Colour each cell by its phase offset: blue = 0, red = max")
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
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
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

    private func chooseBgImage() {
        let panel = NSOpenPanel()
        panel.title                 = "Choose Background Image"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories  = false
        panel.allowedContentTypes   = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            controller.setBackgroundImage(url: url)
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

    // MARK: - Grid Scroll section

    @ViewBuilder
    private var gridScrollSection: some View {
        let ls = controller.layerStates[safe: controller.activeLayerIndex]
        InspectorSection("GRID SCROLL", isCollapsed: $gridScrollCollapsed) {
            // Edge mode
            InspectorField("Edge Mode") {
                Picker("", selection: Binding(
                    get: { ls?.gridScrollMode ?? .wrap },
                    set: { ls?.gridScrollMode = $0 }
                )) {
                    ForEach(GridScrollMode.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 100)
            }
            // Driver mode
            InspectorField("Mode") {
                Picker("", selection: Binding(
                    get: { ls?.gridScrollDriver.mode ?? .constant },
                    set: { ls?.gridScrollDriver.mode = $0 }
                )) {
                    ForEach(UMVectorDriverMode.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            // Mode-specific fields
            switch ls?.gridScrollDriver.mode ?? .constant {
            case .constant:
                InspectorField("Scroll X") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.base.x ?? 0 },
                        set: { ls?.gridScrollDriver.base.x = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                    Text("cells").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Scroll Y") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.base.y ?? 0 },
                        set: { ls?.gridScrollDriver.base.y = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                    Text("cells").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .oscillator:
                InspectorField("Amp X") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.oscillatorAmplitude.x ?? 0 },
                        set: { ls?.gridScrollDriver.oscillatorAmplitude.x = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
                InspectorField("Amp Y") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.oscillatorAmplitude.y ?? 0 },
                        set: { ls?.gridScrollDriver.oscillatorAmplitude.y = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
                InspectorField("Period") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.oscillatorPeriod ?? 2 },
                        set: { ls?.gridScrollDriver.oscillatorPeriod = max(0.1, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                    Text("s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Phase") {
                    Slider(value: Binding(
                        get: { ls?.gridScrollDriver.oscillatorPhase ?? 0 },
                        set: { ls?.gridScrollDriver.oscillatorPhase = $0 }
                    ), in: 0...1).frame(maxWidth: 100)
                }
                InspectorField("Offset X") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.oscillatorOffset.x ?? 0 },
                        set: { ls?.gridScrollDriver.oscillatorOffset.x = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
                InspectorField("Offset Y") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.oscillatorOffset.y ?? 0 },
                        set: { ls?.gridScrollDriver.oscillatorOffset.y = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
            case .jitter:
                InspectorField("Range X") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.jitterRange.x ?? 1 },
                        set: { ls?.gridScrollDriver.jitterRange.x = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
                InspectorField("Range Y") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.jitterRange.y ?? 1 },
                        set: { ls?.gridScrollDriver.jitterRange.y = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
                InspectorField("Duration") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.jitterDuration ?? 12 },
                        set: { ls?.gridScrollDriver.jitterDuration = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                    Text("fr").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .noise:
                InspectorField("Amp X") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.noiseAmplitude.x ?? 1 },
                        set: { ls?.gridScrollDriver.noiseAmplitude.x = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
                InspectorField("Amp Y") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.noiseAmplitude.y ?? 1 },
                        set: { ls?.gridScrollDriver.noiseAmplitude.y = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                }
                InspectorField("Freq") {
                    TextField("", value: Binding(
                        get: { ls?.gridScrollDriver.noiseFrequency ?? 0.5 },
                        set: { ls?.gridScrollDriver.noiseFrequency = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 64)
                    Text("cyc/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .keyframe:
                InspectorField("") {
                    Text("Set keyframes in timeline")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            // Reset button
            InspectorField("") {
                Button("Reset") {
                    ls?.gridScrollDriver = .zero
                    ls?.gridScrollMode   = .wrap
                }
                .font(.system(size: 11))
            }
        }
    }

    // MARK: - Camera section

    private var cameraSection: some View {
        @Bindable var ctrl = controller
        return InspectorSection("CAMERA", isCollapsed: $cameraCollapsed) {

            // ── PAN ──────────────────────────────────────────────
            Text("PAN")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
            InspectorField("Mode") {
                Picker("", selection: $ctrl.camera.pan.mode) {
                    ForEach(UMVectorDriverMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            switch ctrl.camera.pan.mode {
            case .constant:
                InspectorField("Pan X") {
                    Slider(value: $ctrl.camera.pan.base.x, in: -500...500).frame(maxWidth: 110)
                    Text(String(format: "%.0f", ctrl.camera.pan.base.x))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                InspectorField("Pan Y") {
                    Slider(value: $ctrl.camera.pan.base.y, in: -500...500).frame(maxWidth: 110)
                    Text(String(format: "%.0f", ctrl.camera.pan.base.y))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            case .oscillator:
                InspectorField("Amp X") {
                    TextField("", value: $ctrl.camera.pan.oscillatorAmplitude.x,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amp Y") {
                    TextField("", value: $ctrl.camera.pan.oscillatorAmplitude.y,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Period") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.pan.oscillatorPeriod },
                        set: { ctrl.camera.pan.oscillatorPeriod = max(0.1, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Phase") {
                    Slider(value: $ctrl.camera.pan.oscillatorPhase, in: 0...1).frame(maxWidth: 90)
                }
                InspectorField("Offset X") {
                    TextField("", value: $ctrl.camera.pan.oscillatorOffset.x,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Offset Y") {
                    TextField("", value: $ctrl.camera.pan.oscillatorOffset.y,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .jitter:
                InspectorField("Range X") {
                    TextField("", value: $ctrl.camera.pan.jitterRange.x,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Range Y") {
                    TextField("", value: $ctrl.camera.pan.jitterRange.y,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Duration") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.pan.jitterDuration },
                        set: { ctrl.camera.pan.jitterDuration = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("fr").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .noise:
                InspectorField("Amp X") {
                    TextField("", value: $ctrl.camera.pan.noiseAmplitude.x,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amp Y") {
                    TextField("", value: $ctrl.camera.pan.noiseAmplitude.y,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Frequency") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.pan.noiseFrequency },
                        set: { ctrl.camera.pan.noiseFrequency = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("cyc/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .keyframe:
                Text("Use the timeline Pan lane for keyframes.")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.vertical, 3)
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 3)

            // ── ZOOM ─────────────────────────────────────────────
            Text("ZOOM")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
                .padding(.horizontal, 12).padding(.bottom, 2)
            InspectorField("Mode") {
                Picker("", selection: $ctrl.camera.zoom.mode) {
                    ForEach(UMDoubleDriverMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            switch ctrl.camera.zoom.mode {
            case .constant:
                InspectorField("Zoom") {
                    Slider(value: $ctrl.camera.zoom.base, in: 0.1...4.0).frame(maxWidth: 110)
                    Text(String(format: "%.2f×", ctrl.camera.zoom.base))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            case .oscillator:
                InspectorField("Centre") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.zoom.base },
                        set: { ctrl.camera.zoom.base = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("×").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amplitude") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.zoom.oscillatorAmplitude },
                        set: { ctrl.camera.zoom.oscillatorAmplitude = max(0, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("×").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Period") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.zoom.oscillatorPeriod },
                        set: { ctrl.camera.zoom.oscillatorPeriod = max(0.1, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Phase") {
                    Slider(value: $ctrl.camera.zoom.oscillatorPhase, in: 0...1).frame(maxWidth: 90)
                }
            case .jitter:
                InspectorField("Range") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.zoom.jitterRange },
                        set: { ctrl.camera.zoom.jitterRange = max(0, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("×").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Duration") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.zoom.jitterDuration },
                        set: { ctrl.camera.zoom.jitterDuration = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("fr").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .noise:
                InspectorField("Amplitude") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.zoom.noiseAmplitude },
                        set: { ctrl.camera.zoom.noiseAmplitude = max(0, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("×").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Frequency") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.zoom.noiseFrequency },
                        set: { ctrl.camera.zoom.noiseFrequency = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("cyc/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .keyframe:
                Text("Use the timeline Zoom lane for keyframes.")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.vertical, 3)
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 3)

            // ── ROTATION ─────────────────────────────────────────
            Text("ROTATION")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
                .padding(.horizontal, 12).padding(.bottom, 2)
            InspectorField("Mode") {
                Picker("", selection: $ctrl.camera.rotation.mode) {
                    ForEach(UMDoubleDriverMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            switch ctrl.camera.rotation.mode {
            case .constant:
                InspectorField("Rotation") {
                    Slider(value: $ctrl.camera.rotation.base, in: -180...180).frame(maxWidth: 110)
                    Text(String(format: "%.0f°", ctrl.camera.rotation.base))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            case .oscillator:
                InspectorField("Centre") {
                    TextField("", value: $ctrl.camera.rotation.base,
                              format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("°").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amplitude") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.rotation.oscillatorAmplitude },
                        set: { ctrl.camera.rotation.oscillatorAmplitude = max(0, $0) }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("°").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Period") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.rotation.oscillatorPeriod },
                        set: { ctrl.camera.rotation.oscillatorPeriod = max(0.1, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Phase") {
                    Slider(value: $ctrl.camera.rotation.oscillatorPhase, in: 0...1).frame(maxWidth: 90)
                }
            case .jitter:
                InspectorField("Range") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.rotation.jitterRange },
                        set: { ctrl.camera.rotation.jitterRange = max(0, $0) }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("°").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Duration") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.rotation.jitterDuration },
                        set: { ctrl.camera.rotation.jitterDuration = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("fr").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .noise:
                InspectorField("Amplitude") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.rotation.noiseAmplitude },
                        set: { ctrl.camera.rotation.noiseAmplitude = max(0, $0) }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("°").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Frequency") {
                    TextField("", value: Binding(
                        get: { ctrl.camera.rotation.noiseFrequency },
                        set: { ctrl.camera.rotation.noiseFrequency = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("cyc/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .keyframe:
                Text("Use the timeline Rotation lane for keyframes.")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.vertical, 3)
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 3)

            InspectorField("") {
                Button("Reset Camera") {
                    ctrl.camera = .identity
                }
                .font(.system(size: 11))
                .disabled(ctrl.camera == .identity)
            }
        }
    }

    // MARK: - Keyframe inspector

    @ViewBuilder
    private var kfInspectorSection: some View {
        @Bindable var ctrl = controller
        if ctrl.selectedTimelineKF != nil || ctrl.selectedCameraKF != nil || ctrl.selectedSpriteKF != nil {
            InspectorSection("KEYFRAME", isCollapsed: $kfInspectorCollapsed) {
                if let sel = ctrl.selectedTimelineKF {
                    kfLayerFields(sel: sel)
                } else if let sel = ctrl.selectedCameraKF {
                    kfCameraFields(sel: sel)
                } else if let sel = ctrl.selectedSpriteKF {
                    kfSpriteFields(sel: sel)
                }
            }
        }
    }

    @ViewBuilder
    private func kfLayerFields(sel: UMTimelineKFSelection) -> some View {
        @Bindable var ctrl = controller
        let ls = ctrl.layerStates[safe: sel.layerIndex]
        InspectorField("Lane") { Text(sel.lane.label).font(.system(size: 11)).foregroundStyle(.secondary) }
        InspectorField("Frame") {
            TextField("", value: Binding(
                get: { layerKFFrame(ls: ls, sel: sel) },
                set: { newF in moveLayerKF(sel: sel, toFrame: max(0, newF)) }
            ), format: .number)
            .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 54)
        }
        switch sel.lane {
        case .opacity:
            InspectorField("Value") {
                Slider(value: Binding(
                    get: { ls?.opacityDriver.keyframes[safe: sel.keyframeIdx]?.value ?? 0 },
                    set: { v in ls?.opacityDriver.keyframes[safe: sel.keyframeIdx]?.value = v }
                ), in: 0...1).frame(maxWidth: 100)
                Text("\(Int(((ls?.opacityDriver.keyframes[safe: sel.keyframeIdx]?.value ?? 0) * 100).rounded()))%")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            }
        case .offset:
            InspectorField("Offset X") {
                TextField("", value: Binding(
                    get: { ls?.layerOffset.keyframes[safe: sel.keyframeIdx]?.value.x ?? 0 },
                    set: { v in ls?.layerOffset.keyframes[safe: sel.keyframeIdx]?.value.x = v }
                ), format: .number).textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
            }
            InspectorField("Offset Y") {
                TextField("", value: Binding(
                    get: { ls?.layerOffset.keyframes[safe: sel.keyframeIdx]?.value.y ?? 0 },
                    set: { v in ls?.layerOffset.keyframes[safe: sel.keyframeIdx]?.value.y = v }
                ), format: .number).textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
            }
        case .gridScroll:
            InspectorField("Scroll X") {
                TextField("", value: Binding(
                    get: { ls?.gridScrollDriver.keyframes[safe: sel.keyframeIdx]?.value.x ?? 0 },
                    set: { v in ls?.gridScrollDriver.keyframes[safe: sel.keyframeIdx]?.value.x = v }
                ), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
            }
            InspectorField("Scroll Y") {
                TextField("", value: Binding(
                    get: { ls?.gridScrollDriver.keyframes[safe: sel.keyframeIdx]?.value.y ?? 0 },
                    set: { v in ls?.gridScrollDriver.keyframes[safe: sel.keyframeIdx]?.value.y = v }
                ), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
            }
        }
        easingField(
            get: { layerKFEasing(ls: ls, sel: sel) },
            set: { e in setLayerKFEasing(ls: ls, sel: sel, easing: e) }
        )
    }

    private func layerKFFrame(ls: UMLayerState?, sel: UMTimelineKFSelection) -> Int {
        switch sel.lane {
        case .opacity:    return ls?.opacityDriver.keyframes[safe: sel.keyframeIdx]?.frame ?? 0
        case .offset:     return ls?.layerOffset.keyframes[safe: sel.keyframeIdx]?.frame ?? 0
        case .gridScroll: return ls?.gridScrollDriver.keyframes[safe: sel.keyframeIdx]?.frame ?? 0
        }
    }

    private func layerKFEasing(ls: UMLayerState?, sel: UMTimelineKFSelection) -> PathEasing {
        switch sel.lane {
        case .opacity:    return ls?.opacityDriver.keyframes[safe: sel.keyframeIdx]?.easing ?? .easeInOut
        case .offset:     return ls?.layerOffset.keyframes[safe: sel.keyframeIdx]?.easing ?? .easeInOut
        case .gridScroll: return ls?.gridScrollDriver.keyframes[safe: sel.keyframeIdx]?.easing ?? .easeInOut
        }
    }

    private func setLayerKFEasing(ls: UMLayerState?, sel: UMTimelineKFSelection, easing: PathEasing) {
        switch sel.lane {
        case .opacity:    ls?.opacityDriver.keyframes[safe: sel.keyframeIdx]?.easing = easing
        case .offset:     ls?.layerOffset.keyframes[safe: sel.keyframeIdx]?.easing = easing
        case .gridScroll: ls?.gridScrollDriver.keyframes[safe: sel.keyframeIdx]?.easing = easing
        }
    }

    @ViewBuilder
    private func kfCameraFields(sel: UMCameraKFSelection) -> some View {
        @Bindable var ctrl = controller
        InspectorField("Lane") { Text(sel.lane.label).font(.system(size: 11)).foregroundStyle(.secondary) }
        InspectorField("Frame") {
            TextField("", value: Binding(
                get: { camerKFFrame(sel: sel) },
                set: { newF in moveCameraKF(sel: sel, toFrame: max(0, newF)) }
            ), format: .number)
            .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 54)
        }
        switch sel.lane {
        case .pan:
            InspectorField("Pan X") {
                TextField("", value: Binding(
                    get: { ctrl.camera.pan.keyframes[safe: sel.keyframeIdx]?.value.x ?? 0 },
                    set: { v in ctrl.camera.pan.keyframes[safe: sel.keyframeIdx]?.value.x = v }
                ), format: .number).textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
            }
            InspectorField("Pan Y") {
                TextField("", value: Binding(
                    get: { ctrl.camera.pan.keyframes[safe: sel.keyframeIdx]?.value.y ?? 0 },
                    set: { v in ctrl.camera.pan.keyframes[safe: sel.keyframeIdx]?.value.y = v }
                ), format: .number).textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
            }
        case .zoom:
            InspectorField("Zoom") {
                Slider(value: Binding(
                    get: { ctrl.camera.zoom.keyframes[safe: sel.keyframeIdx]?.value ?? 1 },
                    set: { v in ctrl.camera.zoom.keyframes[safe: sel.keyframeIdx]?.value = v }
                ), in: 0.1...4.0).frame(maxWidth: 100)
                Text(String(format: "%.2f×", ctrl.camera.zoom.keyframes[safe: sel.keyframeIdx]?.value ?? 1))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
        case .rotation:
            InspectorField("Rotation") {
                Slider(value: Binding(
                    get: { ctrl.camera.rotation.keyframes[safe: sel.keyframeIdx]?.value ?? 0 },
                    set: { v in ctrl.camera.rotation.keyframes[safe: sel.keyframeIdx]?.value = v }
                ), in: -180...180).frame(maxWidth: 100)
                Text(String(format: "%.0f°", ctrl.camera.rotation.keyframes[safe: sel.keyframeIdx]?.value ?? 0))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
        }
        easingField(
            get: { cameraKFEasing(sel: sel) },
            set: { e in setCameraKFEasing(sel: sel, easing: e) }
        )
    }

    private func easingField(get: @escaping () -> PathEasing, set: @escaping (PathEasing) -> Void) -> some View {
        InspectorField("Easing") {
            Picker("", selection: Binding(get: get, set: set)) {
                ForEach(PathEasing.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
        }
    }

    private func moveLayerKF(sel: UMTimelineKFSelection, toFrame newFrame: Int) {
        guard let ls = controller.layerStates[safe: sel.layerIndex] else { return }
        switch sel.lane {
        case .opacity:
            guard sel.keyframeIdx < ls.opacityDriver.keyframes.count else { return }
            ls.opacityDriver.keyframes[sel.keyframeIdx].frame = newFrame
            ls.opacityDriver.keyframes.sort { $0.frame < $1.frame }
            if let idx = ls.opacityDriver.keyframes.firstIndex(where: { $0.frame == newFrame }) {
                controller.selectedTimelineKF = UMTimelineKFSelection(layerIndex: sel.layerIndex, lane: sel.lane, keyframeIdx: idx)
            }
        case .offset:
            guard sel.keyframeIdx < ls.layerOffset.keyframes.count else { return }
            ls.layerOffset.keyframes[sel.keyframeIdx].frame = newFrame
            ls.layerOffset.keyframes.sort { $0.frame < $1.frame }
            if let idx = ls.layerOffset.keyframes.firstIndex(where: { $0.frame == newFrame }) {
                controller.selectedTimelineKF = UMTimelineKFSelection(layerIndex: sel.layerIndex, lane: sel.lane, keyframeIdx: idx)
            }
        case .gridScroll:
            guard sel.keyframeIdx < ls.gridScrollDriver.keyframes.count else { return }
            ls.gridScrollDriver.keyframes[sel.keyframeIdx].frame = newFrame
            ls.gridScrollDriver.keyframes.sort { $0.frame < $1.frame }
            if let idx = ls.gridScrollDriver.keyframes.firstIndex(where: { $0.frame == newFrame }) {
                controller.selectedTimelineKF = UMTimelineKFSelection(layerIndex: sel.layerIndex, lane: sel.lane, keyframeIdx: idx)
            }
        }
    }

    private func camerKFFrame(sel: UMCameraKFSelection) -> Int {
        switch sel.lane {
        case .pan:      return controller.camera.pan.keyframes[safe: sel.keyframeIdx]?.frame ?? 0
        case .zoom:     return controller.camera.zoom.keyframes[safe: sel.keyframeIdx]?.frame ?? 0
        case .rotation: return controller.camera.rotation.keyframes[safe: sel.keyframeIdx]?.frame ?? 0
        }
    }

    private func moveCameraKF(sel: UMCameraKFSelection, toFrame newFrame: Int) {
        switch sel.lane {
        case .pan:
            guard sel.keyframeIdx < controller.camera.pan.keyframes.count else { return }
            controller.camera.pan.keyframes[sel.keyframeIdx].frame = newFrame
            controller.camera.pan.keyframes.sort { $0.frame < $1.frame }
            if let idx = controller.camera.pan.keyframes.firstIndex(where: { $0.frame == newFrame }) {
                controller.selectedCameraKF = UMCameraKFSelection(lane: sel.lane, keyframeIdx: idx)
            }
        case .zoom:
            guard sel.keyframeIdx < controller.camera.zoom.keyframes.count else { return }
            controller.camera.zoom.keyframes[sel.keyframeIdx].frame = newFrame
            controller.camera.zoom.keyframes.sort { $0.frame < $1.frame }
            if let idx = controller.camera.zoom.keyframes.firstIndex(where: { $0.frame == newFrame }) {
                controller.selectedCameraKF = UMCameraKFSelection(lane: sel.lane, keyframeIdx: idx)
            }
        case .rotation:
            guard sel.keyframeIdx < controller.camera.rotation.keyframes.count else { return }
            controller.camera.rotation.keyframes[sel.keyframeIdx].frame = newFrame
            controller.camera.rotation.keyframes.sort { $0.frame < $1.frame }
            if let idx = controller.camera.rotation.keyframes.firstIndex(where: { $0.frame == newFrame }) {
                controller.selectedCameraKF = UMCameraKFSelection(lane: sel.lane, keyframeIdx: idx)
            }
        }
    }

    private func cameraKFEasing(sel: UMCameraKFSelection) -> PathEasing {
        switch sel.lane {
        case .pan:      return controller.camera.pan.keyframes[safe: sel.keyframeIdx]?.easing      ?? .easeInOut
        case .zoom:     return controller.camera.zoom.keyframes[safe: sel.keyframeIdx]?.easing     ?? .easeInOut
        case .rotation: return controller.camera.rotation.keyframes[safe: sel.keyframeIdx]?.easing ?? .easeInOut
        }
    }

    private func setCameraKFEasing(sel: UMCameraKFSelection, easing: PathEasing) {
        switch sel.lane {
        case .pan:
            controller.camera.pan.keyframes[safe: sel.keyframeIdx]?.easing = easing
        case .zoom:
            controller.camera.zoom.keyframes[safe: sel.keyframeIdx]?.easing = easing
        case .rotation:
            controller.camera.rotation.keyframes[safe: sel.keyframeIdx]?.easing = easing
        }
    }

    @ViewBuilder
    private func kfSpriteFields(sel: UMSpriteKFSelection) -> some View {
        let ls = controller.layerStates[safe: sel.layerIndex]
        let spriteIdx = ls?.sprites.firstIndex(where: { $0.id == sel.spriteID })
        let spriteName = ls?.sprites.first(where: { $0.id == sel.spriteID })?.name ?? "Sprite"
        InspectorField("Sprite") { Text(spriteName).font(.system(size: 11)).foregroundStyle(.secondary) }
        InspectorField("Frame") {
            TextField("", value: Binding(
                get: { ls?.sprites[safe: spriteIdx ?? -1]?.positionDriver.keyframes[safe: sel.keyframeIdx]?.frame ?? 0 },
                set: { newF in moveSpriteKF(sel: sel, toFrame: max(0, newF)) }
            ), format: .number)
            .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 54)
        }
        InspectorField("Pos X") {
            TextField("", value: Binding(
                get: { ls?.sprites[safe: spriteIdx ?? -1]?.positionDriver.keyframes[safe: sel.keyframeIdx]?.value.x ?? 0 },
                set: { v in
                    if let ls, let si = spriteIdx {
                        ls.sprites[safe: si]?.positionDriver.keyframes[safe: sel.keyframeIdx]?.value.x = v
                    }
                }
            ), format: .number).textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
        }
        InspectorField("Pos Y") {
            TextField("", value: Binding(
                get: { ls?.sprites[safe: spriteIdx ?? -1]?.positionDriver.keyframes[safe: sel.keyframeIdx]?.value.y ?? 0 },
                set: { v in
                    if let ls, let si = spriteIdx {
                        ls.sprites[safe: si]?.positionDriver.keyframes[safe: sel.keyframeIdx]?.value.y = v
                    }
                }
            ), format: .number).textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
        }
        easingField(
            get: { ls?.sprites[safe: spriteIdx ?? -1]?.positionDriver.keyframes[safe: sel.keyframeIdx]?.easing ?? .easeInOut },
            set: { e in
                if let ls, let si = spriteIdx {
                    ls.sprites[safe: si]?.positionDriver.keyframes[safe: sel.keyframeIdx]?.easing = e
                }
            }
        )
    }

    private func moveSpriteKF(sel: UMSpriteKFSelection, toFrame newFrame: Int) {
        guard let ls = controller.layerStates[safe: sel.layerIndex],
              let si = ls.sprites.firstIndex(where: { $0.id == sel.spriteID }),
              sel.keyframeIdx < ls.sprites[si].positionDriver.keyframes.count else { return }
        ls.sprites[si].positionDriver.keyframes[sel.keyframeIdx].frame = newFrame
        ls.sprites[si].positionDriver.keyframes.sort { $0.frame < $1.frame }
        if let ki = ls.sprites[si].positionDriver.keyframes.firstIndex(where: { $0.frame == newFrame }) {
            controller.selectedSpriteKF = UMSpriteKFSelection(layerIndex: sel.layerIndex, spriteID: sel.spriteID, keyframeIdx: ki)
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
            InspectorField("From / To") {
                FloatEntryField(value: Binding(
                    get: { Double(controller.startFrame) },
                    set: { controller.startFrame = max(0, Int($0)) }
                ), width: 48, fractionDigits: 0)
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                FloatEntryField(value: Binding(
                    get: { Double(controller.endFrame) },
                    set: { controller.endFrame = max(controller.startFrame + 1, Int($0)) }
                ), width: 48, fractionDigits: 0)
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
            InspectorField("Motion") {
                Picker("", selection: selectionMotionBinding) {
                    Text("—").tag(nil as UUID?)
                    ForEach(controller.projectMotionSets) { ms in
                        Text(ms.name).tag(Optional(ms.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
                .disabled(!hasSelection)
            }
            InspectorField("Shape") {
                Picker("", selection: selectionShapeBinding) {
                    Text("—").tag(nil as UUID?)
                    ForEach(controller.projectShapes) { sq in
                        Text(sq.name).tag(Optional(sq.id))
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
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
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
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
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
        let renderTitle = activeStyleIndex.map { "STYLE — \(controller.projectStyles[$0].name)" } ?? "RENDER"
        return InspectorSection(renderTitle, isCollapsed: $renderCollapsed) {
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
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
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
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
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
        if let ms = effectiveMotionSet {
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

                // Axis mix — show only the axes the current preset actually uses
                let showXY  = ms.motionPreset == .wave || ms.motionPreset == .wander || ms.motionPreset == .jitter
                let showRot = ms.motionPreset == .spin || ms.motionPreset == .jitter
                let showSc  = ms.motionPreset == .pulse
                if showXY || showRot || showSc {
                    Divider().padding(.horizontal, 12).padding(.vertical, 3)
                    Text("Axis mix")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    if showXY {
                        InspectorField("X") {
                            Slider(value: axisXBinding, in: 0...1)
                                .frame(maxWidth: 100)
                            Text(String(format: "%.2f", ms.axisX))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 38, alignment: .trailing)
                        }
                        InspectorField("Y") {
                            Slider(value: axisYBinding, in: 0...1)
                                .frame(maxWidth: 100)
                            Text(String(format: "%.2f", ms.axisY))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    if showRot {
                        InspectorField("Rotation") {
                            Slider(value: axisRotationBinding, in: 0...1)
                                .frame(maxWidth: 100)
                            Text(String(format: "%.2f", ms.axisRotation))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    if showSc {
                        InspectorField("Scale") {
                            Slider(value: axisScaleBinding, in: 0...1)
                                .frame(maxWidth: 100)
                            Text(String(format: "%.2f", ms.axisScale))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }

                Divider().padding(.horizontal, 12).padding(.vertical, 3)
                InspectorField("Sequence") {
                    Picker("", selection: sequenceModeBinding) {
                        ForEach(SequenceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 110)
                }
                if ms.sequenceMode != .off {
                    InspectorField("Step") {
                        Stepper(value: framesPerStepBinding, in: 1...480) {
                            Text("\(ms.framesPerStep) fr")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(ms.shapeIDs.enumerated()), id: \.offset) { idx, _ in
                            HStack(spacing: 4) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                                Picker("", selection: sequenceShapeBinding(at: idx)) {
                                    Text("—").tag(nil as UUID?)
                                    ForEach(controller.projectShapes) { sq in
                                        Text(sq.name).tag(Optional(sq.id))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                Button {
                                    if let i = activeMotionIndex {
                                        controller.projectMotionSets[i].shapeIDs.remove(at: idx)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .frame(minWidth: 22, minHeight: 22)
                                .contentShape(Rectangle())
                            }
                        }
                        Button {
                            if let i = activeMotionIndex {
                                let firstID = controller.projectShapes.first?.id ?? UUID()
                                controller.projectMotionSets[i].shapeIDs.append(firstID)
                            }
                        } label: {
                            Label("Add Shape", systemImage: "plus")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(controller.projectShapes.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
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
                    set: { controller.activePathID = $0; controller.selectedPathKeyframeID = nil }
                )) {
                    Text("—").tag(nil as UUID?)
                    ForEach(controller.engine.document.paths) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Button { controller.createPath(); controller.selectedPathKeyframeID = nil } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
                .help("New path")

                if controller.activePathID != nil {
                    Button {
                        if let id = controller.activePathID { controller.deletePath(id) }
                        controller.selectedPathKeyframeID = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
                    .foregroundStyle(.red)
                    .help("Delete path")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if let path = activePath {
                // Path name field
                InspectorField("Name") {
                    TextField("Name", text: Binding(
                        get: { path.name },
                        set: {
                            guard let id = controller.activePathID,
                                  let i  = controller.engine.document.paths.firstIndex(where: { $0.id == id })
                            else { return }
                            controller.engine.document.paths[i].name = $0
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                }

                // Loop toggle + duration read-out
                HStack(spacing: 0) {
                    Toggle("Loop", isOn: Binding(
                        get: { path.loops },
                        set: {
                            guard let id = controller.activePathID,
                                  let i  = controller.engine.document.paths.firstIndex(where: { $0.id == id })
                            else { return }
                            controller.engine.document.paths[i].loops = $0
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .padding(.leading, 12)
                    Spacer()
                    Text("\(path.duration) fr")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .padding(.trailing, 12)
                }
                .padding(.vertical, 4)

                Divider().padding(.horizontal, 12)

                // Keyframe list
                VStack(spacing: 0) {
                    ForEach(path.keyframes) { kf in
                        keyframeRow(kf)
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
                        guard let activeID = controller.activePathID else { return }
                        controller.addKeyframe(frame: newKeyframeFrame, to: activeID)
                        controller.selectedPathKeyframeID = controller.engine.document.paths
                            .first(where: { $0.id == activeID })?
                            .keyframes.first(where: { $0.frame == newKeyframeFrame })?.id
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                // Keyframe property editor (shown when one is selected)
                if let kf = activeKeyframe {
                    Divider().padding(.horizontal, 12)
                    keyframeEditor(keyframe: kf)
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
        .onChange(of: controller.activePathID) { controller.selectedPathKeyframeID = nil }
    }

    @ViewBuilder
    private func keyframeRow(_ kf: PathKeyframe) -> some View {
        let selected = kf.id == controller.selectedPathKeyframeID
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
                guard let pathID = controller.activePathID else { return }
                controller.removeKeyframe(id: kf.id, from: pathID)
                if controller.selectedPathKeyframeID == kf.id { controller.selectedPathKeyframeID = nil }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 22, minHeight: 22)
            .contentShape(Rectangle())
            .disabled((activePath?.keyframes.count ?? 0) <= 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.selectedPathKeyframeID = (controller.selectedPathKeyframeID == kf.id) ? nil : kf.id
        }
    }

    @ViewBuilder
    private func keyframeEditor(keyframe kf: PathKeyframe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorField("Frame") {
                Stepper("\(activeKeyframe?.frame ?? kf.frame) fr",
                        value: Binding(
                            get: { self.activeKeyframe?.frame ?? kf.frame },
                            set: { val in
                                guard let pathID = self.controller.activePathID,
                                      let kfID   = self.controller.selectedPathKeyframeID,
                                      let pi = self.controller.engine.document.paths.firstIndex(where: { $0.id == pathID }),
                                      let ki = self.controller.engine.document.paths[pi].keyframes.firstIndex(where: { $0.id == kfID })
                                else { return }
                                self.controller.engine.document.paths[pi].keyframes[ki].frame = max(0, val)
                                self.controller.engine.document.paths[pi].keyframes.sort { $0.frame < $1.frame }
                            }
                        ),
                        in: 0...9999, step: 1)
                    .font(.system(size: 11))
            }
            InspectorField("Offset X") {
                ResettableSlider(value: kfBinding(\.dx, default: 0), range: -3...3, defaultValue: 0)
                valueLabel(activeKeyframe?.dx ?? kf.dx, digits: 2)
                unitLabel("c")
            }
            InspectorField("Offset Y") {
                ResettableSlider(value: kfBinding(\.dy, default: 0), range: -3...3, defaultValue: 0)
                valueLabel(activeKeyframe?.dy ?? kf.dy, digits: 2)
                unitLabel("c")
            }
            InspectorField("Rotation") {
                ResettableSlider(value: kfBinding(\.rotation, default: 0), range: -360...360, defaultValue: 0)
                valueLabel(activeKeyframe?.rotation ?? kf.rotation, digits: 1)
                unitLabel("°")
            }
            InspectorField("Scale X") {
                ResettableSlider(
                    value: Binding(
                        get: { self.activeKeyframe?.scaleX ?? kf.scaleX },
                        set: {
                            guard let pathID = self.controller.activePathID,
                                  let kfID   = self.controller.selectedPathKeyframeID,
                                  let pi = self.controller.engine.document.paths.firstIndex(where: { $0.id == pathID }),
                                  let ki = self.controller.engine.document.paths[pi].keyframes.firstIndex(where: { $0.id == kfID })
                            else { return }
                            self.controller.engine.document.paths[pi].keyframes[ki].scaleX = max(0.01, $0)
                        }
                    ),
                    range: 0.1...3, defaultValue: 1)
                valueLabel(activeKeyframe?.scaleX ?? kf.scaleX, digits: 2)
            }
            InspectorField("Scale Y") {
                ResettableSlider(
                    value: Binding(
                        get: { self.activeKeyframe?.scaleY ?? kf.scaleY },
                        set: {
                            guard let pathID = self.controller.activePathID,
                                  let kfID   = self.controller.selectedPathKeyframeID,
                                  let pi = self.controller.engine.document.paths.firstIndex(where: { $0.id == pathID }),
                                  let ki = self.controller.engine.document.paths[pi].keyframes.firstIndex(where: { $0.id == kfID })
                            else { return }
                            self.controller.engine.document.paths[pi].keyframes[ki].scaleY = max(0.01, $0)
                        }
                    ),
                    range: 0.1...3, defaultValue: 1)
                valueLabel(activeKeyframe?.scaleY ?? kf.scaleY, digits: 2)
            }
            InspectorField("Easing") {
                Picker("", selection: kfBinding(\.easing, default: .easeInOut)) {
                    ForEach(PathEasing.allCases, id: \.self) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 120)
                Text("(used when no handles)")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            Divider().padding(.horizontal, 12).padding(.top, 4)

            HStack(spacing: 6) {
                Toggle("Smooth", isOn: kfBinding(\.smooth, default: false))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .padding(.leading, 12)
                Spacer()
                Text("Mirror in↔out")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.trailing, 12)
            }
            .padding(.vertical, 2)

            InspectorField("Out X") {
                ResettableSlider(value: tangentBinding(\.outTangentX, mirror: \.inTangentX), range: -5...5, defaultValue: 0)
                valueLabel(activeKeyframe?.outTangentX ?? 0, digits: 2)
                unitLabel("c")
            }
            InspectorField("Out Y") {
                ResettableSlider(value: tangentBinding(\.outTangentY, mirror: \.inTangentY), range: -5...5, defaultValue: 0)
                valueLabel(activeKeyframe?.outTangentY ?? 0, digits: 2)
                unitLabel("c")
            }
            InspectorField("In X") {
                ResettableSlider(value: tangentBinding(\.inTangentX, mirror: \.outTangentX), range: -5...5, defaultValue: 0)
                valueLabel(activeKeyframe?.inTangentX ?? 0, digits: 2)
                unitLabel("c")
            }
            InspectorField("In Y") {
                ResettableSlider(value: tangentBinding(\.inTangentY, mirror: \.outTangentY), range: -5...5, defaultValue: 0)
                valueLabel(activeKeyframe?.inTangentY ?? 0, digits: 2)
                unitLabel("c")
            }
        }
    }

    // MARK: - Path helper properties

    private var activePath: UMMotionPath? {
        guard let id = controller.activePathID else { return nil }
        return controller.engine.document.paths.first { $0.id == id }
    }

    private var activeKeyframe: PathKeyframe? {
        guard let kfID = controller.selectedPathKeyframeID else { return nil }
        return activePath?.keyframes.first { $0.id == kfID }
    }

    /// Binding for a tangent component that mirrors the opposite tangent when `smooth == true`.
    private func tangentBinding(_ kp: WritableKeyPath<PathKeyframe, Double>,
                                mirror mKp: WritableKeyPath<PathKeyframe, Double>) -> Binding<Double> {
        Binding(
            get: { self.activeKeyframe?[keyPath: kp] ?? 0 },
            set: { val in
                guard let pathID = self.controller.activePathID,
                      let kfID   = self.controller.selectedPathKeyframeID,
                      let pi = self.controller.engine.document.paths.firstIndex(where: { $0.id == pathID }),
                      let ki = self.controller.engine.document.paths[pi].keyframes.firstIndex(where: { $0.id == kfID })
                else { return }
                self.controller.engine.document.paths[pi].keyframes[ki][keyPath: kp] = val
                if self.controller.engine.document.paths[pi].keyframes[ki].smooth {
                    self.controller.engine.document.paths[pi].keyframes[ki][keyPath: mKp] = -val
                }
            }
        )
    }

    /// Generic keyframe field binding. Finds path and keyframe by stable ID at write time
    /// so a stale integer index can never cause an out-of-range crash.
    private func kfBinding<V>(_ kp: WritableKeyPath<PathKeyframe, V>, default def: V) -> Binding<V> {
        Binding(
            get: { self.activeKeyframe?[keyPath: kp] ?? def },
            set: { val in
                guard let pathID = self.controller.activePathID,
                      let kfID   = self.controller.selectedPathKeyframeID,
                      let pi = self.controller.engine.document.paths.firstIndex(where: { $0.id == pathID }),
                      let ki = self.controller.engine.document.paths[pi].keyframes.firstIndex(where: { $0.id == kfID })
                else { return }
                self.controller.engine.document.paths[pi].keyframes[ki][keyPath: kp] = val
            }
        )
    }

    private var selectionPathBinding: Binding<UUID?> {
        Binding(
            get: { focusedCell?.pathID },
            set: { controller.assignPathToSelection($0) }
        )
    }

    // MARK: - Sprite layer section

    private var spritesSection: some View {
        let ls = controller.layerStates[controller.activeLayerIndex]
        return InspectorSection("SPRITES", isCollapsed: $spritesCollapsed) {
            // Sprite list
            if ls.sprites.isEmpty {
                Text("Click canvas to place sprites")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(ls.sprites) { sprite in
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)
                        Text(sprite.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(controller.activeSpriteID == sprite.id
                                             ? Color.accentColor : Color.primary)
                        Spacer()
                        Button {
                            controller.removeSprite(id: sprite.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { controller.selectSpriteFromCanvas(sprite.id) }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                }
            }

            Divider().padding(.vertical, 2)

            // Add sprite button
            Button("+ Place at Centre") {
                controller.addSprite(at: CGPoint(x: 0.5, y: 0.5))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Per-sprite inspector
            if let sid = controller.activeSpriteID,
               let idx = ls.sprites.firstIndex(where: { $0.id == sid }) {
                Divider().padding(.vertical, 2)
                spriteInspector(sprite: Binding(
                    get: { ls.sprites[idx] },
                    set: { ls.sprites[idx] = $0 }
                ))
            }
        }
    }

    @ViewBuilder
    private func spriteInspector(sprite: Binding<UMSprite>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Name
            InspectorField("Name") {
                TextField("", text: Binding(get: { sprite.wrappedValue.name }, set: { sprite.wrappedValue.name = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            // Position
            InspectorField("Position X") {
                FloatEntryField(value: Binding(
                    get: { sprite.wrappedValue.x * 100 },
                    set: { sprite.wrappedValue.x = $0 / 100.0 }
                ), width: 52, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            InspectorField("Position Y") {
                FloatEntryField(value: Binding(
                    get: { sprite.wrappedValue.y * 100 },
                    set: { sprite.wrappedValue.y = $0 / 100.0 }
                ), width: 52, fractionDigits: 1)
                Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            // Rotation
            InspectorField("Rotation") {
                FloatEntryField(value: Binding(
                    get: { sprite.wrappedValue.rotation },
                    set: { sprite.wrappedValue.rotation = $0 }
                ), width: 52, fractionDigits: 1)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            // Scale
            InspectorField("Scale X") {
                FloatEntryField(value: Binding(
                    get: { sprite.wrappedValue.scaleX },
                    set: { sprite.wrappedValue.scaleX = max(0.01, $0) }
                ), width: 52, fractionDigits: 2)
            }
            InspectorField("Scale Y") {
                FloatEntryField(value: Binding(
                    get: { sprite.wrappedValue.scaleY },
                    set: { sprite.wrappedValue.scaleY = max(0.01, $0) }
                ), width: 52, fractionDigits: 2)
            }
            // Style picker
            InspectorField("Style") {
                Picker("", selection: Binding(
                    get: { sprite.wrappedValue.styleID },
                    set: { sprite.wrappedValue.styleID = $0 }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(controller.projectStyles) { st in
                        Text(st.name).tag(Optional(st.id))
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
            }
            // Shape picker
            InspectorField("Shape") {
                Picker("", selection: Binding(
                    get: { sprite.wrappedValue.shapeID },
                    set: { sprite.wrappedValue.shapeID = $0 }
                )) {
                    Text("Default").tag(UUID?.none)
                    ForEach(controller.projectShapes) { sh in
                        Text(sh.name).tag(Optional(sh.id))
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
            }
            // Motion picker
            InspectorField("Motion") {
                Picker("", selection: Binding(
                    get: { sprite.wrappedValue.motionID },
                    set: { sprite.wrappedValue.motionID = $0 }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(controller.projectMotionSets) { ms in
                        Text(ms.name).tag(Optional(ms.id))
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
            }
            // Phase offset
            InspectorField("Phase") {
                FloatEntryField(value: Binding(
                    get: { Double(sprite.wrappedValue.phaseOffset) },
                    set: { sprite.wrappedValue.phaseOffset = Int($0) }
                ), width: 52, fractionDigits: 0)
                Text("frames").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            // MARK: Position driver
            Divider().padding(.vertical, 4)
            Text("POSITION DRIVER")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            InspectorField("Mode") {
                Picker("", selection: Binding(
                    get: { sprite.wrappedValue.positionDriver.mode },
                    set: { sprite.wrappedValue.positionDriver.mode = $0 }
                )) {
                    ForEach(UMVectorDriverMode.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            switch sprite.wrappedValue.positionDriver.mode {
            case .constant:
                InspectorField("Offset X") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.base.x },
                        set: { sprite.wrappedValue.positionDriver.base.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Offset Y") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.base.y },
                        set: { sprite.wrappedValue.positionDriver.base.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .oscillator:
                InspectorField("Amp X") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.oscillatorAmplitude.x },
                        set: { sprite.wrappedValue.positionDriver.oscillatorAmplitude.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amp Y") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.oscillatorAmplitude.y },
                        set: { sprite.wrappedValue.positionDriver.oscillatorAmplitude.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Period") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.oscillatorPeriod },
                        set: { sprite.wrappedValue.positionDriver.oscillatorPeriod = max(0.1, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Phase") {
                    Slider(value: Binding(
                        get: { sprite.wrappedValue.positionDriver.oscillatorPhase },
                        set: { sprite.wrappedValue.positionDriver.oscillatorPhase = $0 }
                    ), in: 0...1).frame(maxWidth: 90)
                }
            case .jitter:
                InspectorField("Range X") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.jitterRange.x },
                        set: { sprite.wrappedValue.positionDriver.jitterRange.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Range Y") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.jitterRange.y },
                        set: { sprite.wrappedValue.positionDriver.jitterRange.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Duration") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.jitterDuration },
                        set: { sprite.wrappedValue.positionDriver.jitterDuration = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("fr").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .noise:
                InspectorField("Amp X") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.noiseAmplitude.x },
                        set: { sprite.wrappedValue.positionDriver.noiseAmplitude.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amp Y") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.noiseAmplitude.y },
                        set: { sprite.wrappedValue.positionDriver.noiseAmplitude.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Frequency") {
                    TextField("", value: Binding(
                        get: { sprite.wrappedValue.positionDriver.noiseFrequency },
                        set: { sprite.wrappedValue.positionDriver.noiseFrequency = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("cyc/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .keyframe:
                Text("Use the timeline to set position keyframes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            // MARK: Polygon overrides
            let polygons   = (sprite.wrappedValue.shapeID.flatMap { controller.shapePolygonMap[$0] } ?? controller.shapePolygons)
                .filter(\.visible)
            let polygonIDs = sprite.wrappedValue.shapeID.flatMap { controller.shapePolygonIDMap[$0] } ?? []
            if !polygons.isEmpty {
                Divider().padding(.vertical, 4)
                Text("POLYGON OVERRIDES")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
                ForEach(Array(polygons.indices), id: \.self) { polyIdx in
                    let polyKey = polygonIDs[safe: polyIdx]?.uuidString ?? ""
                    HStack(spacing: 6) {
                        Text("#\(polyIdx)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .leading)
                        Text("F")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let fillOvr = sprite.wrappedValue.polygonOverrides[polyKey]?.fill {
                            ColorWell(color: Binding(
                                get: { fillOvr.swiftUIColor },
                                set: { newC in
                                    var ovr = sprite.wrappedValue.polygonOverrides[polyKey] ?? UMPolygonOverride()
                                    ovr.fill = UMColor(newC)
                                    sprite.wrappedValue.polygonOverrides[polyKey] = ovr
                                }
                            ), supportsOpacity: true)
                            .frame(width: 28, height: 18)
                            Button {
                                var ovr = sprite.wrappedValue.polygonOverrides[polyKey]
                                ovr?.fill = nil
                                if ovr?.stroke == nil { sprite.wrappedValue.polygonOverrides.removeValue(forKey: polyKey) }
                                else { sprite.wrappedValue.polygonOverrides[polyKey] = ovr }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(.secondary)
                            }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                        } else {
                            Button {
                                var ovr = sprite.wrappedValue.polygonOverrides[polyKey] ?? UMPolygonOverride()
                                ovr.fill = UMColor(r: 1, g: 1, b: 1, a: 1)
                                sprite.wrappedValue.polygonOverrides[polyKey] = ovr
                            } label: {
                                Text("set").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                            }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                        }
                        Spacer()
                        Text("S")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let strokeOvr = sprite.wrappedValue.polygonOverrides[polyKey]?.stroke {
                            ColorWell(color: Binding(
                                get: { strokeOvr.swiftUIColor },
                                set: { newC in
                                    var ovr = sprite.wrappedValue.polygonOverrides[polyKey] ?? UMPolygonOverride()
                                    ovr.stroke = UMColor(newC)
                                    sprite.wrappedValue.polygonOverrides[polyKey] = ovr
                                }
                            ), supportsOpacity: true)
                            .frame(width: 28, height: 18)
                            Button {
                                var ovr = sprite.wrappedValue.polygonOverrides[polyKey]
                                ovr?.stroke = nil
                                if ovr?.fill == nil { sprite.wrappedValue.polygonOverrides.removeValue(forKey: polyKey) }
                                else { sprite.wrappedValue.polygonOverrides[polyKey] = ovr }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(.secondary)
                            }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                        } else {
                            Button {
                                var ovr = sprite.wrappedValue.polygonOverrides[polyKey] ?? UMPolygonOverride()
                                ovr.stroke = UMColor(r: 0, g: 0, b: 0, a: 1)
                                sprite.wrappedValue.polygonOverrides[polyKey] = ovr
                            } label: {
                                Text("set").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                            }.buttonStyle(.plain).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Nothing active hint

    @ViewBuilder
    private var nothingActiveHint: some View {
        let hasKF     = controller.selectedTimelineKF != nil || controller.selectedCameraKF != nil || controller.selectedSpriteKF != nil
        let hasMotion = effectiveMotionSet != nil
        let hasCells  = !controller.selectedIndices.isEmpty
        let hasShape  = controller.activeShapeID != nil
        if !hasKF && !hasMotion && !hasCells && !hasShape {
            VStack(spacing: 4) {
                Text("Nothing active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("Select cells, or click a STYLE,\nMOTION, or SHAPE in the palette.")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Shape section

    @ViewBuilder
    private var shapeSection: some View {
        if let shapeID = controller.activeShapeID,
           let shape = controller.projectShapes.first(where: { $0.id == shapeID }) {
            let allPolys = controller.shapePolygonMap[shapeID] ?? controller.shapePolygons
            let visCount = allPolys.filter(\.visible).count
            let ls = controller.layerStates[controller.activeLayerIndex]
            let cellCount = ls.engine.document.cells.filter { $0.shapeID == shapeID }.count
            InspectorSection("SHAPE — \(shape.name)", isCollapsed: $shapeCollapsed) {
                InspectorField("Polygons") {
                    Text("\(visCount) visible / \(allPolys.count) total")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                InspectorField("Cells") {
                    Text(cellCount == 0 ? "none in active layer"
                         : "\(cellCount) in active layer")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Layer drivers section

    @ViewBuilder
    private var layerDriversSection: some View {
        let ls = controller.layerStates[safe: controller.activeLayerIndex]
        InspectorSection("LAYER DRIVERS", isCollapsed: $layerDriversCollapsed) {

            // ── Blend mode ───────────────────────────────────────
            InspectorField("Blend") {
                Picker("", selection: Binding(
                    get: { ls?.blendMode ?? .normal },
                    set: { ls?.blendMode = $0 }
                )) {
                    ForEach(UMBlendMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 3)

            // ── Grid distortion ───────────────────────────────────
            Text("DISTORTION")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
            InspectorField("Mode") {
                let distortionModeBinding = Binding<String>(
                    get: {
                        guard let d = ls?.gridDistortion else { return "none" }
                        switch d {
                        case .none:        return "none"
                        case .perspective: return "perspective"
                        case .barrel:      return "barrel"
                        case .fractured:   return "fractured"
                        }
                    },
                    set: { mode in
                        switch mode {
                        case "perspective": ls?.gridDistortion = .perspective(vertical: 0.5, horizontal: 0, convergence: 0)
                        case "barrel":      ls?.gridDistortion = .barrel(amount: 0.5)
                        case "fractured":   ls?.gridDistortion = .fractured(amount: 0.3, seed: distortionSeed)
                        default:            ls?.gridDistortion = .none
                        }
                    }
                )
                Picker("", selection: distortionModeBinding) {
                    Text("None").tag("none")
                    Text("Perspective").tag("perspective")
                    Text("Barrel / Cone").tag("barrel")
                    Text("Fractured").tag("fractured")
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            switch ls?.gridDistortion ?? .none {
            case .none:
                EmptyView()
            case .perspective(let v, let h, let conv):
                InspectorField("Vertical") {
                    Slider(value: Binding(
                        get: { v },
                        set: { ls?.gridDistortion = .perspective(vertical: $0, horizontal: h, convergence: conv) }
                    ), in: -1...1).frame(maxWidth: 90)
                    valueLabel(v, digits: 2)
                }
                InspectorField("Horizontal") {
                    Slider(value: Binding(
                        get: { h },
                        set: { ls?.gridDistortion = .perspective(vertical: v, horizontal: $0, convergence: conv) }
                    ), in: -1...1).frame(maxWidth: 90)
                    valueLabel(h, digits: 2)
                }
                InspectorField("Converge") {
                    Slider(value: Binding(
                        get: { conv },
                        set: { ls?.gridDistortion = .perspective(vertical: v, horizontal: h, convergence: $0) }
                    ), in: 0...1).frame(maxWidth: 90)
                    valueLabel(conv, digits: 2)
                }
                Text(conv < 0.05
                     ? "+ = top rows smaller / left cols smaller"
                     : "Rows narrow proportionally; auto-zoom fills canvas")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.bottom, 3)
            case .barrel(let amount):
                InspectorField("Amount") {
                    Slider(value: Binding(
                        get: { amount },
                        set: { ls?.gridDistortion = .barrel(amount: $0) }
                    ), in: -1...1).frame(maxWidth: 90)
                    valueLabel(amount, digits: 2)
                }
                Text(amount >= 0 ? "Centre cells drawn larger (spherical)" : "Centre cells drawn smaller (cone)")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.bottom, 3)
            case .fractured(let amount, let seed):
                InspectorField("Amount") {
                    Slider(value: Binding(
                        get: { amount },
                        set: { ls?.gridDistortion = .fractured(amount: $0, seed: seed) }
                    ), in: 0...1).frame(maxWidth: 90)
                    valueLabel(amount, digits: 2)
                }
                InspectorField("Seed") {
                    TextField("", value: Binding(
                        get: { Int(seed) },
                        set: { v in
                            let s = UInt64(max(0, v))
                            distortionSeed = s
                            ls?.gridDistortion = .fractured(amount: amount, seed: s)
                        }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Button("↺") {
                        let s = UInt64.random(in: 1...UInt64.max)
                        distortionSeed = s
                        ls?.gridDistortion = .fractured(amount: amount, seed: s)
                    }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 3)

            // ── Opacity ──────────────────────────────────────────
            Text("OPACITY")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
            InspectorField("Mode") {
                Picker("", selection: Binding(
                    get: { ls?.opacityDriver.mode ?? .constant },
                    set: { ls?.opacityDriver.mode = $0 }
                )) {
                    ForEach(UMDoubleDriverMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            switch ls?.opacityDriver.mode ?? .constant {
            case .constant:
                Text("Adjust opacity via the layer row slider.")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.vertical, 3)
            case .oscillator:
                InspectorField("Centre") {
                    TextField("", value: Binding(
                        get: { ls?.opacityDriver.base ?? 1 },
                        set: { ls?.opacityDriver.base = max(0, min(1, $0)) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 56)
                }
                InspectorField("Amplitude") {
                    TextField("", value: Binding(
                        get: { ls?.opacityDriver.oscillatorAmplitude ?? 0.5 },
                        set: { ls?.opacityDriver.oscillatorAmplitude = max(0, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 56)
                }
                InspectorField("Period") {
                    TextField("", value: Binding(
                        get: { ls?.opacityDriver.oscillatorPeriod ?? 2 },
                        set: { ls?.opacityDriver.oscillatorPeriod = max(0.1, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 56)
                    Text("s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Phase") {
                    Slider(value: Binding(
                        get: { ls?.opacityDriver.oscillatorPhase ?? 0 },
                        set: { ls?.opacityDriver.oscillatorPhase = $0 }
                    ), in: 0...1).frame(maxWidth: 90)
                }
            case .jitter:
                InspectorField("Range") {
                    TextField("", value: Binding(
                        get: { ls?.opacityDriver.jitterRange ?? 0.5 },
                        set: { ls?.opacityDriver.jitterRange = max(0, min(1, $0)) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 56)
                }
                InspectorField("Duration") {
                    TextField("", value: Binding(
                        get: { ls?.opacityDriver.jitterDuration ?? 12 },
                        set: { ls?.opacityDriver.jitterDuration = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 56)
                    Text("fr").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .noise:
                InspectorField("Amplitude") {
                    TextField("", value: Binding(
                        get: { ls?.opacityDriver.noiseAmplitude ?? 0.5 },
                        set: { ls?.opacityDriver.noiseAmplitude = max(0, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 56)
                }
                InspectorField("Frequency") {
                    TextField("", value: Binding(
                        get: { ls?.opacityDriver.noiseFrequency ?? 1 },
                        set: { ls?.opacityDriver.noiseFrequency = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 56)
                    Text("cyc/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .keyframe:
                Text("Use the timeline Opacity lane for keyframes.")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.vertical, 3)
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 3)

            // ── Layer offset ──────────────────────────────────────
            Text("OFFSET")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
                .padding(.horizontal, 12).padding(.bottom, 2)
            InspectorField("Mode") {
                Picker("", selection: Binding(
                    get: { ls?.layerOffset.mode ?? .constant },
                    set: { ls?.layerOffset.mode = $0 }
                )) {
                    ForEach(UMVectorDriverMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 110)
            }
            switch ls?.layerOffset.mode ?? .constant {
            case .constant:
                InspectorField("Offset X") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.base.x ?? 0 },
                        set: { ls?.layerOffset.base.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Offset Y") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.base.y ?? 0 },
                        set: { ls?.layerOffset.base.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .oscillator:
                InspectorField("Amp X") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.oscillatorAmplitude.x ?? 0 },
                        set: { ls?.layerOffset.oscillatorAmplitude.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amp Y") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.oscillatorAmplitude.y ?? 0 },
                        set: { ls?.layerOffset.oscillatorAmplitude.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Period") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.oscillatorPeriod ?? 2 },
                        set: { ls?.layerOffset.oscillatorPeriod = max(0.1, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Phase") {
                    Slider(value: Binding(
                        get: { ls?.layerOffset.oscillatorPhase ?? 0 },
                        set: { ls?.layerOffset.oscillatorPhase = $0 }
                    ), in: 0...1).frame(maxWidth: 90)
                }
            case .jitter:
                InspectorField("Range X") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.jitterRange.x ?? 10 },
                        set: { ls?.layerOffset.jitterRange.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Range Y") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.jitterRange.y ?? 10 },
                        set: { ls?.layerOffset.jitterRange.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Duration") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.jitterDuration ?? 12 },
                        set: { ls?.layerOffset.jitterDuration = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("fr").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .noise:
                InspectorField("Amp X") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.noiseAmplitude.x ?? 50 },
                        set: { ls?.layerOffset.noiseAmplitude.x = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Amp Y") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.noiseAmplitude.y ?? 50 },
                        set: { ls?.layerOffset.noiseAmplitude.y = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                InspectorField("Frequency") {
                    TextField("", value: Binding(
                        get: { ls?.layerOffset.noiseFrequency ?? 1 },
                        set: { ls?.layerOffset.noiseFrequency = max(0.01, $0) }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder).font(.system(size: 11, design: .monospaced)).frame(width: 60)
                    Text("cyc/s").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            case .keyframe:
                Text("Use the timeline Offset lane for keyframes.")
                    .font(.system(size: 10)).foregroundStyle(.quaternary)
                    .padding(.horizontal, 12).padding(.vertical, 3)
            }
        }
    }

    // MARK: - Advanced section

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

    // In sprite mode, derive motion context from the selected sprite's motionID;
    // otherwise fall back to the palette activeMotionID.
    private var effectiveMotionID: UUID? {
        if controller.layerStates[safe: controller.activeLayerIndex]?.layerMode == .sprite,
           let spriteID = controller.activeSpriteID,
           let ls = controller.layerStates[safe: controller.activeLayerIndex],
           let sprite = ls.sprites.first(where: { $0.id == spriteID }),
           let mid = sprite.motionID {
            return mid
        }
        return controller.activeMotionID
    }

    private var effectiveMotionSet: UMMotionSet? {
        guard let id = effectiveMotionID else { return nil }
        return controller.projectMotionSets.first { $0.id == id }
    }

    private var activeMotionIndex: Int? {
        guard let id = effectiveMotionID else { return nil }
        return controller.projectMotionSets.firstIndex { $0.id == id }
    }

    private var motionPresetBinding: Binding<MotionPreset> {
        Binding(
            get: { effectiveMotionSet?.motionPreset ?? .static },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionPreset = $0 } }
        )
    }

    private var motionSpeedBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.motionSpeed ?? 1 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionSpeed = $0 } }
        )
    }

    private var motionAmountBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.motionAmount ?? 0.5 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionAmount = $0 } }
        )
    }

    private var motionPhaseBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.motionPhase ?? 0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].motionPhase = $0 } }
        )
    }

    private var motionOrderChaosBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.orderChaos ?? 0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].orderChaos = $0 } }
        )
    }

    private var axisXBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.axisX ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisX = $0 } }
        )
    }

    private var axisYBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.axisY ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisY = $0 } }
        )
    }

    private var axisRotationBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.axisRotation ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisRotation = $0 } }
        )
    }

    private var axisScaleBinding: Binding<Double> {
        Binding(
            get: { effectiveMotionSet?.axisScale ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisScale = $0 } }
        )
    }

    private var sequenceModeBinding: Binding<SequenceMode> {
        Binding(
            get: { effectiveMotionSet?.sequenceMode ?? .off },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].sequenceMode = $0 } }
        )
    }

    private var framesPerStepBinding: Binding<Int> {
        Binding(
            get: { effectiveMotionSet?.framesPerStep ?? 4 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].framesPerStep = max(1, $0) } }
        )
    }

    private func sequenceShapeBinding(at idx: Int) -> Binding<UUID?> {
        Binding(
            get: {
                guard let ms = self.effectiveMotionSet, idx < ms.shapeIDs.count else { return nil }
                return ms.shapeIDs[idx]
            },
            set: { newID in
                guard let i = self.activeMotionIndex,
                      let id = newID,
                      idx < self.controller.projectMotionSets[i].shapeIDs.count
                else { return }
                self.controller.projectMotionSets[i].shapeIDs[idx] = id
            }
        )
    }

    private var selectionMotionBinding: Binding<UUID?> {
        Binding(
            get: { focusedCell?.motionID },
            set: { controller.assignMotionToSelection($0) }
        )
    }

    private var selectionShapeBinding: Binding<UUID?> {
        Binding(
            get: { focusedCell?.shapeID },
            set: { controller.assignShapeToSelection($0) }
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
                controller.setProjectCanvasSize(width: dims.width, height: dims.height)
            }
        )
    }

    private var canvasWidthBinding: Binding<Double> {
        Binding(
            get: { controller.engine.document.gridConfig.canvasWidth },
            set: {
                controller.setProjectCanvasSize(
                    width: $0,
                    height: controller.engine.document.gridConfig.canvasHeight)
            }
        )
    }

    private var canvasHeightBinding: Binding<Double> {
        Binding(
            get: { controller.engine.document.gridConfig.canvasHeight },
            set: {
                controller.setProjectCanvasSize(
                    width: controller.engine.document.gridConfig.canvasWidth,
                    height: $0)
            }
        )
    }

}
