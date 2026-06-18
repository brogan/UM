import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import UniformTypeIdentifiers
import UMEngine
import LoomEngine

// MARK: - Video exporter

@MainActor
enum UMVideoExporter {

    /// Render all `frameCount` frames of `doc` to a .mov file at `url`.
    ///
    /// - Parameters:
    ///   - backgroundDraw: when false, each frame composites onto the previous (accumulation mode)
    ///   - strokeScale:    multiplier applied to stroke widths; pass `exportMultiplier` when scaleDrawing is on
    ///   - progress:       called on MainActor after each frame with a 0→1 value
    static func export(
        doc: UMGridDocument,
        backgroundColor: UMColor,
        polygons: [Polygon2D],
        colorMapEngine: UMColorMapEngine,
        backgroundDraw: Bool,
        stretchSprites: Bool,
        frameCount: Int,
        fps: Int,
        exportW: Double,
        exportH: Double,
        strokeScale: Double,
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

        var accum: CGImage? = nil

        for frameIndex in 0..<max(1, frameCount) {

            let cgImage = umRenderFrame(
                doc:                doc,
                backgroundColor:    backgroundColor,
                polygons:           polygons,
                colorMapEngine:     colorMapEngine,
                backgroundDraw:     backgroundDraw,
                stretchSprites:     stretchSprites,
                frame:              frameIndex,
                exportW:            exportW,
                exportH:            exportH,
                strokeScale:        strokeScale,
                accumulationBuffer: accum
            )

            if !backgroundDraw { accum = cgImage }

            if let image = cgImage {
                var pixelBuffer: CVPixelBuffer?
                if CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                   let pb = pixelBuffer {

                    CVPixelBufferLockBaseAddress(pb, [])
                    if let base = CVPixelBufferGetBaseAddress(pb) {
                        let bpr      = CVPixelBufferGetBytesPerRow(pb)
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
}

// MARK: - Error

enum UMExportError: Error {
    case setupFailed
    case renderFailed
}
