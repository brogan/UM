import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UMEngine
import LoomEngine

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

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264.rawValue,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey           as String: w,
            kCVPixelBufferHeightKey          as String: h,
        ]
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
                                               space: CGColorSpaceCreateDeviceRGB(),
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
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                       | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo) else { return nil }
        let destRect = CGRect(x: 0, y: 0, width: w, height: h)

        if let buf = accumulationBuffer, !backgroundDraw {
            ctx.draw(buf, in: destRect)
        } else {
            ctx.setFillColor(CGColor(red: backgroundColor.r, green: backgroundColor.g,
                                     blue: backgroundColor.b, alpha: backgroundColor.a))
            ctx.fill(destRect)
            if let bgImg = backgroundImage { ctx.draw(bgImg, in: destRect) }
        }

        let cameraFrame = camera.evaluate(frame: frame)
        for layer in layers {
            if let img = renderLayerCells(layer: layer,
                                          shapePolygonMap: shapePolygonMap,
                                          shapePolygonIDMap: shapePolygonIDMap,
                                          fallbackPolygons: fallbackPolygons,
                                          projectMotionSets: projectMotionSets,
                                          colorMapEngine: colorMapEngines[layer.id],
                                          stretchSprites: stretchSprites,
                                          frame: frame,
                                          exportW: exportW, exportH: exportH,
                                          strokeScale: strokeScale,
                                          cameraFrame: cameraFrame) {
                ctx.setAlpha(DriverEvaluator.evaluate(layer.opacityDriver, frame: frame))
                ctx.draw(img, in: destRect)
                ctx.setAlpha(1.0)
            }
        }

        return ctx.makeImage()
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
            gridScrollMode:    layer.gridScrollMode
        ))
        renderer.scale = 1.0
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
        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264.rawValue,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey           as String: w,
            kCVPixelBufferHeightKey          as String: h,
        ]
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
                                                   space: CGColorSpaceCreateDeviceRGB(),
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
