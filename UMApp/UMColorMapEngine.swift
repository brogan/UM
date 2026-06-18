import Foundation
import CoreGraphics
import AVFoundation
import ImageIO
import UMEngine

@Observable
@MainActor
final class UMColorMapEngine {

    private(set) var isLoaded      = false
    private(set) var isLoading     = false
    private(set) var isVideo       = false
    private(set) var extractedFrameCount = 0
    private(set) var displayName   = ""

    // Stored originals for re-sampling on grid resize
    private var sourceImage:  CGImage?
    private var sourceFrames: [CGImage] = []

    // Pre-sampled grids: [row][col] for static; [frame][row][col] for video
    private var staticGrid:  [[UMColor]] = []
    private var videoGrids:  [[[UMColor]]] = []

    // MARK: - Public query

    func color(atRow row: Int, col: Int,
               animationFrame: Int,
               loopMode: VideoLoopMode) -> UMColor? {
        guard isLoaded else { return nil }
        if isVideo {
            guard !videoGrids.isEmpty else { return nil }
            let fi = resolvedIndex(animationFrame, count: videoGrids.count, mode: loopMode)
            guard row < videoGrids[fi].count, col < videoGrids[fi][row].count else { return nil }
            return videoGrids[fi][row][col]
        } else {
            guard row < staticGrid.count, col < staticGrid[row].count else { return nil }
            return staticGrid[row][col]
        }
    }

    // Pre-resolved grid for the current frame (passed to FrameCapture to avoid per-cell lookup)
    func currentGrid(animationFrame: Int, loopMode: VideoLoopMode) -> [[UMColor]]? {
        guard isLoaded else { return nil }
        if isVideo {
            guard !videoGrids.isEmpty else { return nil }
            let fi = resolvedIndex(animationFrame, count: videoGrids.count, mode: loopMode)
            return videoGrids[fi]
        }
        return staticGrid.isEmpty ? nil : staticGrid
    }

    // MARK: - Load

    func load(url: URL, rows: Int, cols: Int) {
        let ext = url.pathExtension.lowercased()
        let videoExts = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        if videoExts.contains(ext) {
            Task { await loadVideo(url: url, rows: rows, cols: cols) }
        } else {
            Task { await loadImage(url: url, rows: rows, cols: cols) }
        }
    }

    // Re-sample when grid dimensions change; no file I/O needed
    func resample(rows: Int, cols: Int) {
        guard isLoaded else { return }
        if isVideo {
            videoGrids = sourceFrames.map { Self.sample($0, rows: rows, cols: cols) }
        } else if let img = sourceImage {
            staticGrid = Self.sample(img, rows: rows, cols: cols)
        }
    }

    func clear() {
        isLoaded = false; isVideo = false; isLoading = false
        staticGrid = []; videoGrids = []
        sourceImage = nil; sourceFrames = []
        displayName = ""; extractedFrameCount = 0
    }

    // MARK: - Private loading

    private func loadImage(url: URL, rows: Int, cols: Int) async {
        isLoading = true
        defer { isLoading = false }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        sourceImage = img
        staticGrid  = Self.sample(img, rows: rows, cols: cols)
        displayName = url.lastPathComponent
        isVideo     = false
        isLoaded    = true
    }

    private func loadVideo(url: URL, rows: Int, cols: Int) async {
        isLoading = true
        defer { isLoading = false }

        let fps = 24
        let maxFrames = 240

        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return }
        let total = min(Int(duration.seconds * Double(fps)), maxFrames)
        guard total > 0 else { return }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        let tol = CMTime(value: 1, timescale: CMTimeScale(fps * 2))
        generator.requestedTimeToleranceBefore = tol
        generator.requestedTimeToleranceAfter  = tol

        // Extract frames off the main actor to avoid blocking UI
        let extracted: [CGImage?] = await Task.detached(priority: .utility) {
            (0..<total).map { f -> CGImage? in
                let t = CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps))
                var actual = CMTime.zero
                return try? generator.copyCGImage(at: t, actualTime: &actual)
            }
        }.value

        guard let lastValid = extracted.compactMap({ $0 }).last else { return }
        let filled = extracted.map { $0 ?? lastValid }
        let grids  = filled.map { Self.sample($0, rows: rows, cols: cols) }

        sourceFrames        = filled
        videoGrids          = grids
        extractedFrameCount = total
        displayName         = url.lastPathComponent
        isVideo             = true
        isLoaded            = true
    }

    // MARK: - Sampling

    // Downscale image into a rows×cols bitmap and read back one UMColor per cell.
    // Drawing into a small bitmap is GPU-accelerated bilinear averaging — equivalent
    // to computing the mean color of each cell region from the full-resolution source.
    private static func sample(_ image: CGImage, rows: Int, cols: Int) -> [[UMColor]] {
        guard rows > 0, cols > 0 else { return [] }
        let cs   = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: nil, width: cols, height: rows,
                                  bitsPerComponent: 8, bytesPerRow: cols * 4,
                                  space: cs, bitmapInfo: info.rawValue) else { return [] }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let data = ctx.data else { return [] }
        let ptr = data.bindMemory(to: UInt8.self, capacity: rows * cols * 4)
        return (0..<rows).map { r in
            (0..<cols).map { c in
                let i = (r * cols + c) * 4
                return UMColor(r: Double(ptr[i])   / 255,
                               g: Double(ptr[i+1]) / 255,
                               b: Double(ptr[i+2]) / 255,
                               a: Double(ptr[i+3]) / 255)
            }
        }
    }

    private func resolvedIndex(_ frame: Int, count: Int, mode: VideoLoopMode) -> Int {
        guard count > 0 else { return 0 }
        switch mode {
        case .loop:  return ((frame % count) + count) % count
        case .clamp: return min(max(frame, 0), count - 1)
        }
    }
}
