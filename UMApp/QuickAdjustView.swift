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
    @State private var cameraCollapsed      = false
    @State private var gridScrollCollapsed  = true
    @State private var kfInspectorCollapsed = false
    @State private var selectedKeyframeID: UUID? = nil
    @State private var newKeyframeFrame: Int = 24

    var body: some View {
        VStack(spacing: 0) {
            styleNameHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    kfInspectorSection
                    projectSection
                    canvasSection
                    cameraSection
                    gridScrollSection
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

    // MARK: - Keyframe inspector

    @ViewBuilder
    private var kfInspectorSection: some View {
        @Bindable var ctrl = controller
        if ctrl.selectedTimelineKF != nil || ctrl.selectedCameraKF != nil {
            InspectorSection("KEYFRAME", isCollapsed: $kfInspectorCollapsed) {
                if let sel = ctrl.selectedTimelineKF {
                    kfLayerFields(sel: sel)
                } else if let sel = ctrl.selectedCameraKF {
                    kfCameraFields(sel: sel)
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
                        selectedKeyframeID = controller.engine.document.paths
                            .first(where: { $0.id == activeID })?
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
        .onChange(of: controller.activePathID) { selectedKeyframeID = nil }
    }

    @ViewBuilder
    private func keyframeRow(_ kf: PathKeyframe) -> some View {
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
                guard let pathID = controller.activePathID else { return }
                controller.removeKeyframe(id: kf.id, from: pathID)
                if selectedKeyframeID == kf.id { selectedKeyframeID = nil }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled((activePath?.keyframes.count ?? 0) <= 2)
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
    private func keyframeEditor(keyframe kf: PathKeyframe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorField("Frame") {
                Stepper("\(activeKeyframe?.frame ?? kf.frame) fr",
                        value: Binding(
                            get: { self.activeKeyframe?.frame ?? kf.frame },
                            set: { val in
                                guard let pathID = self.controller.activePathID,
                                      let kfID   = self.selectedKeyframeID,
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
                                  let kfID   = self.selectedKeyframeID,
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
                                  let kfID   = self.selectedKeyframeID,
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
            }
        }
    }

    // MARK: - Path helper properties

    private var activePath: UMMotionPath? {
        guard let id = controller.activePathID else { return nil }
        return controller.engine.document.paths.first { $0.id == id }
    }

    private var activeKeyframe: PathKeyframe? {
        guard let kfID = selectedKeyframeID else { return nil }
        return activePath?.keyframes.first { $0.id == kfID }
    }

    /// Generic keyframe field binding. Finds path and keyframe by stable ID at write time
    /// so a stale integer index can never cause an out-of-range crash.
    private func kfBinding<V>(_ kp: WritableKeyPath<PathKeyframe, V>, default def: V) -> Binding<V> {
        Binding(
            get: { self.activeKeyframe?[keyPath: kp] ?? def },
            set: { val in
                guard let pathID = self.controller.activePathID,
                      let kfID   = self.selectedKeyframeID,
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

    private var axisXBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.axisX ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisX = $0 } }
        )
    }

    private var axisYBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.axisY ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisY = $0 } }
        )
    }

    private var axisRotationBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.axisRotation ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisRotation = $0 } }
        )
    }

    private var axisScaleBinding: Binding<Double> {
        Binding(
            get: { controller.activeMotionSet?.axisScale ?? 1.0 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].axisScale = $0 } }
        )
    }

    private var sequenceModeBinding: Binding<SequenceMode> {
        Binding(
            get: { controller.activeMotionSet?.sequenceMode ?? .off },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].sequenceMode = $0 } }
        )
    }

    private var framesPerStepBinding: Binding<Int> {
        Binding(
            get: { controller.activeMotionSet?.framesPerStep ?? 4 },
            set: { if let i = activeMotionIndex { controller.projectMotionSets[i].framesPerStep = max(1, $0) } }
        )
    }

    private func sequenceShapeBinding(at idx: Int) -> Binding<UUID?> {
        Binding(
            get: {
                guard let ms = controller.activeMotionSet, idx < ms.shapeIDs.count else { return nil }
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
