import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UMEngine
import LoomEngine

private let umExportColorSpace: CGColorSpace =
    CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

private func umExportVideoColorProperties() -> [String: Any] {
    [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ]
}

private func umExportPixelBufferColorAttributes() -> [String: Any] {
    [
        kCVImageBufferCGColorSpaceKey as String: umExportColorSpace,
        kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_709_2,
        kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_ITU_R_709_2,
        kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
    ]
}

private func umExportVideoSettings(width: Int, height: Int) -> [String: Any] {
    [
        AVVideoCodecKey: AVVideoCodecType.proRes4444.rawValue,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: umExportVideoColorProperties(),
    ]
}

private let umExportPreviewMatchSaturation = 1.06
private let umExportPreviewMatchBrightness = -0.04

private struct UMExportFrameCapture: View {
    let existingBuffer: CGImage?
    let backgroundColor: UMColor
    let backgroundImage: CGImage?
    let layers: [UMLayer]
    let shapePolygonMap: [UUID: [Polygon2D]]
    let shapePolygonIDMap: [UUID: [UUID]]
    let fallbackPolygons: [Polygon2D]
    let projectMotionSets: [UMMotionSet]
    let colorMapEngines: [UUID: UMColorMapEngine]
    let stretchSprites: Bool
    let frame: Int
    let gridW: Double
    let gridH: Double
    let strokeScale: Double
    let camera: UMCamera

    var body: some View {
        Canvas { ctx, size in
            let destRect = CGRect(origin: .zero, size: size)
            if let existingBuffer {
                let img = ctx.resolve(Image(decorative: existingBuffer, scale: 1))
                ctx.draw(img, in: destRect)
            } else {
                let bg = backgroundColor
                ctx.fill(Path(destRect),
                         with: .color(Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)))
                if let backgroundImage {
                    let img = ctx.resolve(Image(decorative: backgroundImage, scale: 1))
                    ctx.draw(img, in: destRect)
                }
            }

            let cameraFrame = camera.evaluate(frame: frame)
            let motionMap = Dictionary(uniqueKeysWithValues: projectMotionSets.map { ($0.id, $0) })

            for layer in layers where layer.isVisible {
                let opacity = DriverEvaluator.evaluate(layer.opacityDriver, frame: frame)
                let layerOff = DriverEvaluator.evaluate(layer.layerOffset, frame: frame)
                let layerXF = umLayerTransform(cameraFrame: cameraFrame,
                                               parallaxFactor: layer.parallaxFactor,
                                               layerOffset: layerOff,
                                               canvasW: gridW, canvasH: gridH)
                var layerCompositeCtx = ctx
                layerCompositeCtx.blendMode = layer.blendMode.swiftUIBlendMode
                layerCompositeCtx.drawLayer { layerCtx in
                    layerCtx.opacity = opacity
                    if !layerXF.isIdentity { layerCtx.concatenate(layerXF) }

                    if layer.layerMode == .sprite {
                        drawSprites(in: &layerCtx, layer: layer, motionMap: motionMap)
                    } else {
                        drawGrid(in: &layerCtx, layer: layer, motionMap: motionMap)
                    }
                }
            }
        }
        .frame(width: gridW, height: gridH)
    }

    private func drawSprites(in ctx: inout GraphicsContext,
                             layer: UMLayer,
                             motionMap: [UUID: UMMotionSet]) {
        let styleMap = Dictionary(uniqueKeysWithValues: layer.document.styles.map { ($0.id, $0) })
        let spriteRef = min(gridW, gridH) / 8.0
        for (idx, sprite) in layer.sprites.enumerated() {
            let style = sprite.styleID.flatMap { styleMap[$0] }
            let motionSet = sprite.motionID.flatMap { motionMap[$0] }
            let motion = computeMotion(motionSet: motionSet, style: style, path: nil,
                                       frame: frame,
                                       phaseOffset: sprite.phaseOffset,
                                       cellIndex: idx,
                                       cellW: spriteRef * sprite.scaleX,
                                       cellH: spriteRef * sprite.scaleY)
            let driverPos = DriverEvaluator.evaluate(sprite.positionDriver, frame: frame, spriteIndex: idx)
            let mx = sprite.x * gridW + motion.dx + driverPos.x
            let my = sprite.y * gridH + motion.dy + driverPos.y
            let rot = sprite.rotation + motion.rotation
            let effectiveShapeID = resolveSequenceShapeID(motionSet: motionSet,
                                                          cellShapeID: sprite.shapeID,
                                                          frame: frame,
                                                          phaseOffset: sprite.phaseOffset)
            let polygons = resolvePolygons(shapeID: effectiveShapeID,
                                           shapeMap: shapePolygonMap,
                                           fallback: fallbackPolygons)
            let polygonIDs = resolvePolygonIDs(shapeID: effectiveShapeID, idMap: shapePolygonIDMap)
            let zoomX = (spriteRef / 2) * sprite.scaleX * motion.scaleX
            let zoomY = (spriteRef / 2) * sprite.scaleY * motion.scaleY
            let fillC = style?.fillColor ?? .defaultFill
            let strokeC = style?.strokeColor ?? .defaultStroke
            let strokeW = (style?.strokeWidth ?? 1.5) * strokeScale
            let mode = style?.renderMode ?? .filledStroked

            if polygons.isEmpty {
                let rect = CGRect(x: mx - zoomX, y: my - zoomY, width: zoomX * 2, height: zoomY * 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                         with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
            } else {
                for (i, polygon) in polygons.filter(\.visible).enumerated() {
                    let ovr = sprite.polygonOverrides[polygonIDs[safe: i]?.uuidString ?? ""]
                    let fC = ovr?.fill ?? fillC
                    let sC = ovr?.stroke ?? strokeC
                    let cgp = buildPolygonPath(polygon, cx: mx, cy: my,
                                               zoomX: zoomX, zoomY: zoomY,
                                               scaleX: 1.0, scaleY: 1.0,
                                               rotation: rot)
                    if mode == .filled || mode == .filledStroked {
                        ctx.fill(Path(cgp),
                                 with: .color(Color(red: fC.r, green: fC.g, blue: fC.b, opacity: fC.a)))
                    }
                    if mode == .stroked || mode == .filledStroked {
                        ctx.stroke(Path(cgp),
                                   with: .color(Color(red: sC.r, green: sC.g, blue: sC.b, opacity: sC.a)),
                                   lineWidth: strokeW)
                    }
                }
            }
        }
    }

    private func drawGrid(in ctx: inout GraphicsContext,
                          layer: UMLayer,
                          motionMap: [UUID: UMMotionSet]) {
        let config = layer.document.gridConfig
        let cellW = gridW / Double(config.cols)
        let cellH = gridH / Double(config.rows)
        let scaleX = cellW / config.cellWidth
        let scaleY = cellH / config.cellHeight
        let styleMap = Dictionary(uniqueKeysWithValues: layer.document.styles.map { ($0.id, $0) })
        let pathMap = Dictionary(uniqueKeysWithValues: layer.document.paths.map { ($0.id, $0) })
        let loopMode = layer.document.colorSource?.videoLoopMode ?? .loop
        let colorGrid = colorMapEngines[layer.id]?.currentGrid(animationFrame: frame, loopMode: loopMode)
        let scroll = DriverEvaluator.evaluate(layer.gridScrollDriver, frame: frame)
        let fracX = scroll.x - floor(scroll.x)
        let fracY = scroll.y - floor(scroll.y)
        let specs = gridScrollRenderSpecs(cells: layer.document.cells, scroll: scroll,
                                          mode: layer.gridScrollMode,
                                          rows: config.rows, cols: config.cols)

        for spec in specs {
            let cell = spec.cell
            let r = spec.displayRow
            let c = spec.displayCol
            let style = styleMap[cell.styleID]
            let motionSet = cell.motionID.flatMap { motionMap[$0] }
            let path = cell.pathID.flatMap { pathMap[$0] }
            var motion = computeMotion(motionSet: motionSet, style: style, path: path,
                                       frame: frame,
                                       phaseOffset: cell.phaseOffset,
                                       cellIndex: cell.gridIndex,
                                       cellW: cellW, cellH: cellH)
            if cell.lockedFillColor != nil || cell.lockedStrokeColor != nil {
                if let fc = cell.lockedFillColor { motion.fillOverride = fc }
                if let sc = cell.lockedStrokeColor { motion.strokeOverride = sc }
            } else if let src = layer.document.colorSource, let grid = colorGrid,
                      r < grid.count, c < grid[r].count {
                applyColorMap(grid[r][c], source: src, style: style, to: &motion)
            }

            let dCell = layer.gridDistortion.evaluate(row: r, col: c,
                                                      rows: config.rows, cols: config.cols,
                                                      uniformCellW: cellW, uniformCellH: cellH,
                                                      gridW: gridW, gridH: gridH)
            let mx = dCell.cx - fracX * cellW + cell.positionOffset.dx * scaleX + motion.dx
            let my = dCell.cy - fracY * cellH + cell.positionOffset.dy * scaleY + motion.dy
            let effectiveShapeID = resolveSequenceShapeID(motionSet: motionSet,
                                                          cellShapeID: cell.shapeID,
                                                          frame: frame,
                                                          phaseOffset: cell.phaseOffset)
            let polygons = resolvePolygons(shapeID: effectiveShapeID,
                                           shapeMap: shapePolygonMap,
                                           fallback: fallbackPolygons)
            let fillC = motion.fillOverride ?? style?.fillColor ?? .defaultFill
            let strokeC = motion.strokeOverride ?? style?.strokeColor ?? .defaultStroke
            let strokeW = (style?.strokeWidth ?? 1.5) * strokeScale
            let mode = style?.renderMode ?? .filledStroked

            if polygons.isEmpty {
                let rw = (dCell.cellW - 4 * strokeScale) / 2 * motion.scaleX
                let rh = (dCell.cellH - 4 * strokeScale) / 2 * motion.scaleY
                let rect = CGRect(x: mx - rw, y: my - rh, width: rw * 2, height: rh * 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                         with: .color(Color(red: fillC.r, green: fillC.g, blue: fillC.b, opacity: fillC.a)))
            } else {
                let dCellHalf = min(dCell.cellW, dCell.cellH)
                let zoomX = (stretchSprites ? dCell.cellW : dCellHalf) * motion.scaleX
                let zoomY = (stretchSprites ? dCell.cellH : dCellHalf) * motion.scaleY
                for polygon in polygons.filter(\.visible) {
                    let cgp = buildPolygonPath(polygon, cx: mx, cy: my,
                                               zoomX: zoomX, zoomY: zoomY,
                                               scaleX: cell.scaleX, scaleY: cell.scaleY,
                                               rotation: cell.rotation + motion.rotation)
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
    }
}

// MARK: - Video exporter

@MainActor
enum UMVideoExporter {

    /// Render all `frameCount` frames, compositing all visible layers, to a .mov file at `url`.
    static func export(
        layers: [UMLayer],
        backgroundColor: UMColor,
        backgroundImage: CGImage? = nil,
        shapePolygonMap: [UUID: [Polygon2D]],
        shapePolygonIDMap: [UUID: [UUID]],
        fallbackPolygons: [Polygon2D],
        projectMotionSets: [UMMotionSet],
        colorMapEngines: [UUID: UMColorMapEngine],
        backgroundDraw: Bool,
        stretchSprites: Bool,
        startFrame: Int = 0,
        frameCount: Int,
        fps: Int,
        exportW: Double,
        exportH: Double,
        strokeScale: Double,
        camera: UMCamera = .identity,
        to url: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {

        let w = Int(exportW)
        let h = Int(exportH)

        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings = umExportVideoSettings(width: w, height: h)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey           as String: w,
            kCVPixelBufferHeightKey          as String: h,
        ].merging(umExportPixelBufferColorAttributes()) { current, _ in current }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(writerInput) else { throw UMExportError.setupFailed }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else { throw UMExportError.setupFailed }

        let visibleLayers = layers.filter(\.isVisible)
        var accum: CGImage? = nil

        for outputIndex in 0..<max(1, frameCount) {
            let animationFrame = startFrame + outputIndex

            let cgImage = renderComposited(
                layers:            visibleLayers,
                backgroundColor:   backgroundColor,
                backgroundImage:   backgroundImage,
                shapePolygonMap:   shapePolygonMap,
                shapePolygonIDMap: shapePolygonIDMap,
                fallbackPolygons:  fallbackPolygons,
                projectMotionSets: projectMotionSets,
                colorMapEngines:   colorMapEngines,
                backgroundDraw:    backgroundDraw,
                stretchSprites:    stretchSprites,
                frame:             animationFrame,
                exportW:           exportW,
                exportH:           exportH,
                strokeScale:       strokeScale,
                camera:            camera,
                accumulationBuffer: accum
            )

            if !backgroundDraw { accum = cgImage }

            if let image = cgImage {
                var pixelBuffer: CVPixelBuffer?
                if CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                   let pb = pixelBuffer {

                    CVPixelBufferLockBaseAddress(pb, [])
                    if let base = CVPixelBufferGetBaseAddress(pb) {
                        let bpr       = CVPixelBufferGetBytesPerRow(pb)
                        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                                       | CGBitmapInfo.byteOrder32Little.rawValue
                        if let ctx = CGContext(data: base, width: w, height: h,
                                               bitsPerComponent: 8, bytesPerRow: bpr,
                                               space: umExportColorSpace,
                                               bitmapInfo: bitmapInfo) {
                            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                        }
                    }
                    CVPixelBufferUnlockBaseAddress(pb, [])

                    while !writerInput.isReadyForMoreMediaData { await Task.yield() }

                    let pts = CMTime(value: CMTimeValue(outputIndex),
                                    timescale: CMTimeScale(max(1, fps)))
                    adaptor.append(pb, withPresentationTime: pts)
                }
            }

            progress(Double(outputIndex + 1) / Double(max(1, frameCount)))
            await Task.yield()
        }

        writerInput.markAsFinished()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }

        if let error = writer.error { throw error }
    }

    // MARK: - Per-frame composite render

    private static func renderComposited(
        layers: [UMLayer],
        backgroundColor: UMColor,
        backgroundImage: CGImage? = nil,
        shapePolygonMap: [UUID: [Polygon2D]],
        shapePolygonIDMap: [UUID: [UUID]],
        fallbackPolygons: [Polygon2D],
        projectMotionSets: [UMMotionSet],
        colorMapEngines: [UUID: UMColorMapEngine],
        backgroundDraw: Bool,
        stretchSprites: Bool,
        frame: Int,
        exportW: Double,
        exportH: Double,
        strokeScale: Double,
        camera: UMCamera = .identity,
        accumulationBuffer: CGImage?
    ) -> CGImage? {
        let w = Int(exportW); let h = Int(exportH)
        guard w > 0, h > 0 else { return nil }
        let renderer = ImageRenderer(content: UMExportFrameCapture(
            existingBuffer:    backgroundDraw ? nil : accumulationBuffer,
            backgroundColor:   backgroundColor,
            backgroundImage:   backgroundImage,
            layers:            layers,
            shapePolygonMap:   shapePolygonMap,
            shapePolygonIDMap: shapePolygonIDMap,
            fallbackPolygons:  fallbackPolygons,
            projectMotionSets: projectMotionSets,
            colorMapEngines:   colorMapEngines,
            stretchSprites:    stretchSprites,
            frame:             frame,
            gridW:             exportW,
            gridH:             exportH,
            strokeScale:       strokeScale,
            camera:            camera
        )
        .saturation(umExportPreviewMatchSaturation)
        .brightness(umExportPreviewMatchBrightness))
        renderer.scale = 1.0
        renderer.colorMode = .nonLinear
        return renderer.cgImage
    }

    // Render one layer's cells onto a transparent background and return a CGImage.
    private static func renderLayerCells(
        layer: UMLayer,
        shapePolygonMap: [UUID: [Polygon2D]],
        shapePolygonIDMap: [UUID: [UUID]],
        fallbackPolygons: [Polygon2D],
        projectMotionSets: [UMMotionSet],
        colorMapEngine: UMColorMapEngine?,
        stretchSprites: Bool,
        frame: Int,
        exportW: Double,
        exportH: Double,
        strokeScale: Double,
        cameraFrame: UMCameraFrame = .identity
    ) -> CGImage? {
        let layerOff = DriverEvaluator.evaluate(layer.layerOffset, frame: frame)
        let layerXF  = umLayerTransform(cameraFrame: cameraFrame,
                                         parallaxFactor: layer.parallaxFactor,
                                         layerOffset: layerOff,
                                         canvasW: exportW, canvasH: exportH)

        if layer.layerMode == .sprite {
            let renderer = ImageRenderer(content: SpriteCapture(
                sprites:           layer.sprites,
                projectStyles:     layer.document.styles,
                projectMotionSets: projectMotionSets,
                shapePolygonMap:   shapePolygonMap,
                shapePolygonIDMap: shapePolygonIDMap,
                fallbackPolygons:  fallbackPolygons,
                currentFrame:      frame,
                gridW: exportW, gridH: exportH,
                strokeScale:       strokeScale,
                layerTransform:    layerXF
            ))
            renderer.scale = 1.0
            renderer.colorMode = .nonLinear
            return renderer.cgImage
        }

        let config = layer.document.gridConfig
        let cellW  = exportW / Double(config.cols)
        let cellH  = exportH / Double(config.rows)
        let sx     = cellW / config.cellWidth
        let sy     = cellH / config.cellHeight
        let loopMode  = layer.document.colorSource?.videoLoopMode ?? .loop
        let colorGrid = colorMapEngine?.currentGrid(animationFrame: frame, loopMode: loopMode)

        let renderer = ImageRenderer(content: FrameCapture(
            existingBuffer:    nil,
            backgroundColor:   UMColor(r: 0, g: 0, b: 0, a: 0),
            gridConfig:        config,
            cells:             layer.document.cells,
            styles:            layer.document.styles,
            motionPaths:       layer.document.paths,
            projectMotionSets: projectMotionSets,
            shapePolygonMap:   shapePolygonMap,
            fallbackPolygons:  fallbackPolygons,
            stretchSprites:    stretchSprites,
            currentFrame:      frame,
            gridW: exportW, gridH: exportH,
            cellW: cellW, cellH: cellH,
            scaleX: sx, scaleY: sy,
            displayScale:      1.0,
            colorGrid:         colorGrid,
            colorSource:       layer.document.colorSource,
            strokeScale:       strokeScale,
            drawBackground:    false,
            layerTransform:    layerXF,
            gridScrollDriver:  layer.gridScrollDriver,
            gridScrollMode:    layer.gridScrollMode,
            gridDistortion:    layer.gridDistortion
        ))
        renderer.scale = 1.0
        renderer.colorMode = .nonLinear
        return renderer.cgImage
    }

    // MARK: - Cut-based export

    /// Render a cut sequence from `timeline` states.
    /// Each state is rendered for `state.holdFrames` output frames, then the grid is swapped
    /// to the next state. The animation frame counter (for parametric/keyframe motion) runs
    /// continuously across all cuts. All layers other than the active grid layer stay constant;
    /// `activeLayerID` identifies which layer's document gets swapped per state.
    static func exportCuts(
        baseLayer: UMLayer,
        otherLayers: [UMLayer],
        timeline: [UMTimelineState],
        backgroundColor: UMColor,
        backgroundImage: CGImage? = nil,
        shapePolygonMap: [UUID: [Polygon2D]],
        shapePolygonIDMap: [UUID: [UUID]],
        fallbackPolygons: [Polygon2D],
        projectMotionSets: [UMMotionSet],
        colorMapEngines: [UUID: UMColorMapEngine],
        backgroundDraw: Bool,
        stretchSprites: Bool,
        fps: Int,
        exportW: Double,
        exportH: Double,
        strokeScale: Double,
        camera: UMCamera = .identity,
        to url: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard !timeline.isEmpty else { throw UMExportError.renderFailed }

        let totalFrames = timeline.reduce(0) { $0 + $1.holdFrames }
        let w = Int(exportW); let h = Int(exportH)
        guard w > 0, h > 0, totalFrames > 0 else { throw UMExportError.setupFailed }

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings = umExportVideoSettings(width: w, height: h)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey           as String: w,
            kCVPixelBufferHeightKey          as String: h,
        ].merging(umExportPixelBufferColorAttributes()) { current, _ in current }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttrs)
        guard writer.canAdd(writerInput) else { throw UMExportError.setupFailed }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw UMExportError.setupFailed }

        var outputIndex = 0
        var accum: CGImage? = nil

        for state in timeline {
            // Build the current-state layer: swap cells/styles/config into the base layer's document.
            var stateDoc = baseLayer.document
            stateDoc.gridConfig = state.gridConfig
            stateDoc.cells      = state.cells
            stateDoc.styles     = state.styles
            var stateLayer = baseLayer
            stateLayer.document = stateDoc

            // Compose the full layer list: others below, state layer at its original z-order
            // (preserve the original visible layer order including stateLayer's position).
            // For simplicity: render stateLayer + otherLayers sorted by their original order.
            // The exporter renders layers[0] first (bottom). Insert stateLayer at its position.
            let visibleOthers = otherLayers.filter(\.isVisible)
            // We'll pass stateLayer and otherLayers; sort is preserved from the call site.

            for _ in 0..<max(1, state.holdFrames) {
                let animFrame = outputIndex  // continuous animation frame
                var allLayers = otherLayers
                // Replace the matching layer slot with the state-swapped version.
                if let idx = allLayers.firstIndex(where: { $0.id == baseLayer.id }) {
                    allLayers[idx] = stateLayer
                } else {
                    allLayers.append(stateLayer)
                }
                let visibleLayers = allLayers.filter(\.isVisible)

                let cgImage = renderComposited(
                    layers:            visibleLayers,
                    backgroundColor:   backgroundColor,
                    backgroundImage:   backgroundImage,
                    shapePolygonMap:   shapePolygonMap,
                    shapePolygonIDMap: shapePolygonIDMap,
                    fallbackPolygons:  fallbackPolygons,
                    projectMotionSets: projectMotionSets,
                    colorMapEngines:   colorMapEngines,
                    backgroundDraw:    backgroundDraw,
                    stretchSprites:    stretchSprites,
                    frame:             animFrame,
                    exportW:           exportW,
                    exportH:           exportH,
                    strokeScale:       strokeScale,
                    camera:            camera,
                    accumulationBuffer: accum)

                if !backgroundDraw { accum = cgImage }

                if let image = cgImage {
                    var pixelBuffer: CVPixelBuffer?
                    if CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                       let pb = pixelBuffer {
                        CVPixelBufferLockBaseAddress(pb, [])
                        if let base = CVPixelBufferGetBaseAddress(pb) {
                            let bpr       = CVPixelBufferGetBytesPerRow(pb)
                            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue
                            if let ctx = CGContext(data: base, width: w, height: h,
                                                   bitsPerComponent: 8, bytesPerRow: bpr,
                                                   space: umExportColorSpace,
                                                   bitmapInfo: bitmapInfo) {
                                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                            }
                        }
                        CVPixelBufferUnlockBaseAddress(pb, [])
                        while !writerInput.isReadyForMoreMediaData { await Task.yield() }
                        let pts = CMTime(value: CMTimeValue(outputIndex),
                                        timescale: CMTimeScale(max(1, fps)))
                        adaptor.append(pb, withPresentationTime: pts)
                    }
                }

                outputIndex += 1
                progress(Double(outputIndex) / Double(totalFrames))
                await Task.yield()
            }
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        if let error = writer.error { throw error }
    }
}

// MARK: - Error

enum UMExportError: Error {
    case setupFailed
    case renderFailed
}
