import Foundation

/// A named, reusable sequence of transform keyframes.
///
/// Cells reference a path by `pathID: UUID?`. At render time the path is
/// evaluated at `(currentFrame + cell.phaseOffset)` and the result is added
/// on top of the style's parametric motion:
///   • position is additive  (path.dx + parametric.dx)
///   • rotation is additive  (path.rotation + parametric.rotation)
///   • scale is multiplicative (path.scaleX × parametric.scaleX)
///
/// Paths live in UMGridDocument.paths and UMLibrary.paths.
public struct UMMotionPath: Codable, Identifiable, Sendable {
    public var id:        UUID
    public var name:      String
    public var keyframes: [PathKeyframe]   // always sorted ascending by .frame
    public var loops:     Bool

    /// Frame number of the last keyframe — the loop/clamp boundary.
    public var duration: Int { keyframes.last?.frame ?? 0 }

    public init(name: String = "Untitled Path", loops: Bool = true) {
        self.id        = UUID()
        self.name      = name
        self.loops     = loops
        // Two identity keyframes so the editor always has something to show.
        self.keyframes = [
            PathKeyframe(frame: 0),
            PathKeyframe(frame: 48)
        ]
    }

    // MARK: - Keyframe mutation (maintain sort order)

    public mutating func addKeyframe(_ kf: PathKeyframe) {
        keyframes.append(kf)
        keyframes.sort { $0.frame < $1.frame }
    }

    public mutating func removeKeyframe(id kfID: UUID) {
        keyframes.removeAll { $0.id == kfID }
    }

    public mutating func updateKeyframe(_ kf: PathKeyframe) {
        guard let i = keyframes.firstIndex(where: { $0.id == kf.id }) else { return }
        keyframes[i] = kf
        keyframes.sort { $0.frame < $1.frame }
    }

    // MARK: - Evaluation

    /// Evaluate the path at absolute frame `t` (= currentFrame + cell.phaseOffset).
    ///
    /// Returns dx/dy in **absolute canvas points** (cell-fraction × cell dimension)
    /// so they can be added directly to the position offset in the Canvas loop.
    public func evaluate(atFrame t: Int, cellW: Double, cellH: Double)
        -> (dx: Double, dy: Double, rotation: Double, scaleX: Double, scaleY: Double)
    {
        guard !keyframes.isEmpty else { return (0, 0, 0, 1, 1) }

        let dur = duration
        let frame: Int
        if loops && dur > 0 {
            frame = ((t % dur) + dur) % dur   // positive modulo
        } else {
            frame = dur > 0 ? max(0, min(t, dur)) : 0
        }

        let kfs = keyframes

        // Single keyframe or frame before the first
        if kfs.count == 1 || frame <= kfs[0].frame {
            let k = kfs[0]
            return (k.dx * cellW, k.dy * cellH, k.rotation, k.scaleX, k.scaleY)
        }
        // Frame at or beyond the last keyframe
        if frame >= kfs[kfs.count - 1].frame {
            let k = kfs[kfs.count - 1]
            return (k.dx * cellW, k.dy * cellH, k.rotation, k.scaleX, k.scaleY)
        }

        // Binary-search for the bounding pair [lo, hi]
        var lo = 0, hi = kfs.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if kfs[mid].frame <= frame { lo = mid } else { hi = mid }
        }

        let k0   = kfs[lo], k1 = kfs[hi]
        let span = Double(k1.frame - k0.frame)
        guard span > 0 else {
            return (k0.dx * cellW, k0.dy * cellH, k0.rotation, k0.scaleX, k0.scaleY)
        }

        let raw   = Double(frame - k0.frame) / span
        let alpha = k0.easing.apply(raw)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * alpha }

        return (
            dx:       lerp(k0.dx,       k1.dx)       * cellW,
            dy:       lerp(k0.dy,       k1.dy)       * cellH,
            rotation: lerp(k0.rotation, k1.rotation),
            scaleX:   lerp(k0.scaleX,   k1.scaleX),
            scaleY:   lerp(k0.scaleY,   k1.scaleY)
        )
    }
}
