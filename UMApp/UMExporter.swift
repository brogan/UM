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
        fallbackPolygons: [Polygon2D],
        projectMotionSets: [UMMotionSet],
        colorMapEngines: [UUID: UMColorMapEngine],
        backgroundDraw: Bool,
        stretchSprites: Bool,
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

        for frameIndex in 0..<max(1, frameCount) {

            let cgImage = renderComposited(
                layers:            visibleLayers,
                backgroundColor:   backgroundColor,
                backgroundImage:   backgroundImage,
                shapePolygonMap:   shapePolygonMap,
                fallbackPolygons:  fallbackPolygons,
                projectMotionSets: projectMotionSets,
                colorMapEngines:   colorMapEngines,
                backgroundDraw:    backgroundDraw,
                stretchSprites:    stretchSprites,
                frame:             frameIndex,
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

                    let pts = CMTime(value: CMTimeValue(frameIndex),
                                    timescale: CMTimeScale(max(1, fps)))
                    adaptor.append(pb, withPresentationTime: pts)
                }
            }

            progress(Double(frameIndex + 1) / Double(max(1, frameCount)))
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
        let config = layer.document.gridConfig
        let cellW  = exportW / Double(config.cols)
        let cellH  = exportH / Double(config.rows)
        let sx     = cellW / config.cellWidth
        let sy     = cellH / config.cellHeight
        let loopMode  = layer.document.colorSource?.videoLoopMode ?? .loop
        let colorGrid = colorMapEngine?.currentGrid(animationFrame: frame, loopMode: loopMode)
        let layerOff  = DriverEvaluator.evaluate(layer.layerOffset, frame: frame)
        let layerXF   = umLayerTransform(cameraFrame: cameraFrame,
                                          parallaxFactor: layer.parallaxFactor,
                                          layerOffset: layerOff,
                                          canvasW: exportW, canvasH: exportH)

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
}

// MARK: - Error

enum UMExportError: Error {
    case setupFailed
    case renderFailed
}
