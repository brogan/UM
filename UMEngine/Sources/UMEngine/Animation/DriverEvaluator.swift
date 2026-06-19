import Foundation

/// Stateless evaluator for UMDoubleDriver and UMVectorDriver.
/// All functions are pure: given driver config + frame number → value. No state mutation.
public enum DriverEvaluator {

    // MARK: - Public API

    /// Evaluate a UMDoubleDriver at `frame` frames elapsed.
    public static func evaluate(
        _ driver: UMDoubleDriver,
        frame: Int,
        fps: Double = 24,
        spriteIndex: Int = 0
    ) -> Double {
        let elapsed = Double(frame)
        switch driver.mode {
        case .constant:
            return driver.base

        case .oscillator:
            let period = max(0.001, driver.oscillatorPeriod)
            let t      = ((elapsed / fps / period) + driver.oscillatorPhase)
                           .truncatingRemainder(dividingBy: 1.0)
            let osc    = sin(t * 2 * .pi)
            return driver.base + osc * driver.oscillatorAmplitude + driver.oscillatorOffset

        case .jitter:
            let dur     = max(1, driver.jitterDuration)
            let bucket  = Int(elapsed) / dur
            let bucketT = Double(Int(elapsed) % dur) / Double(dur)
            let v0      = jitterValue(seed: driver.noiseSeed, index: spriteIndex, bucket: bucket)
            let v1      = jitterValue(seed: driver.noiseSeed, index: spriteIndex, bucket: bucket + 1)
            let eased   = driver.jitterEasing.apply(bucketT)
            return driver.base + (v0 + (v1 - v0) * eased) * driver.jitterRange

        case .noise:
            let t = elapsed / fps * driver.noiseFrequency
            let n = valueNoise(t: t, seed: driver.noiseSeed ^ spriteIndex)
            return driver.base + (n * 2 - 1) * driver.noiseAmplitude

        case .keyframe:
            return evaluateDoubleKeyframes(driver.keyframes, loopMode: driver.loopMode,
                                           base: driver.base, frame: frame)
        }
    }

    /// Evaluate a UMVectorDriver at `frame` frames elapsed.
    public static func evaluate(
        _ driver: UMVectorDriver,
        frame: Int,
        fps: Double = 24,
        spriteIndex: Int = 0
    ) -> UMVec2 {
        let elapsed = Double(frame)
        switch driver.mode {
        case .constant:
            return driver.base

        case .oscillator:
            let period = max(0.001, driver.oscillatorPeriod)
            let t      = ((elapsed / fps / period) + driver.oscillatorPhase)
                           .truncatingRemainder(dividingBy: 1.0)
            let osc    = sin(t * 2 * .pi)
            return UMVec2(
                x: driver.base.x + osc * driver.oscillatorAmplitude.x + driver.oscillatorOffset.x,
                y: driver.base.y + osc * driver.oscillatorAmplitude.y + driver.oscillatorOffset.y
            )

        case .jitter:
            let dur     = max(1, driver.jitterDuration)
            let bucket  = Int(elapsed) / dur
            let bucketT = Double(Int(elapsed) % dur) / Double(dur)
            let v0x     = jitterValue(seed: driver.noiseSeed,     index: spriteIndex, bucket: bucket)
            let v0y     = jitterValue(seed: driver.noiseSeed ^ 1, index: spriteIndex, bucket: bucket)
            let v1x     = jitterValue(seed: driver.noiseSeed,     index: spriteIndex, bucket: bucket + 1)
            let v1y     = jitterValue(seed: driver.noiseSeed ^ 1, index: spriteIndex, bucket: bucket + 1)
            let eased   = driver.jitterEasing.apply(bucketT)
            return UMVec2(
                x: driver.base.x + (v0x + (v1x - v0x) * eased) * driver.jitterRange.x,
                y: driver.base.y + (v0y + (v1y - v0y) * eased) * driver.jitterRange.y
            )

        case .noise:
            let t  = elapsed / fps * driver.noiseFrequency
            let nx = valueNoise(t: t,        seed: driver.noiseSeed ^ spriteIndex)
            let ny = valueNoise(t: t + 31.7, seed: driver.noiseSeed ^ spriteIndex ^ 0xFF)
            return UMVec2(
                x: driver.base.x + (nx * 2 - 1) * driver.noiseAmplitude.x,
                y: driver.base.y + (ny * 2 - 1) * driver.noiseAmplitude.y
            )

        case .keyframe:
            return evaluateVectorKeyframes(driver.keyframes, loopMode: driver.loopMode,
                                           base: driver.base, frame: frame)
        }
    }

    // MARK: - Keyframe evaluation

    private static func evaluateDoubleKeyframes(
        _ keyframes: [UMDoubleKeyframe],
        loopMode: UMLoopMode,
        base: Double,
        frame: Int
    ) -> Double {
        guard !keyframes.isEmpty else { return base }
        let sorted = keyframes.sorted { $0.frame < $1.frame }
        let f      = resolvedFrame(frame, first: sorted.first!.frame,
                                   last: sorted.last!.frame, loopMode: loopMode)
        var lo = sorted.first!
        var hi = sorted.last!
        for k in sorted {
            if k.frame <= f { lo = k } else if hi.frame > f || hi.frame == sorted.first!.frame { hi = k; break }
        }
        guard lo.frame != hi.frame else { return lo.value }
        let rawT = Double(f - lo.frame) / Double(hi.frame - lo.frame)
        return lo.value + (hi.value - lo.value) * lo.easing.apply(rawT)
    }

    private static func evaluateVectorKeyframes(
        _ keyframes: [UMVectorKeyframe],
        loopMode: UMLoopMode,
        base: UMVec2,
        frame: Int
    ) -> UMVec2 {
        guard !keyframes.isEmpty else { return base }
        let sorted = keyframes.sorted { $0.frame < $1.frame }
        let f      = resolvedFrame(frame, first: sorted.first!.frame,
                                   last: sorted.last!.frame, loopMode: loopMode)
        var lo = sorted.first!
        var hi = sorted.last!
        for k in sorted {
            if k.frame <= f { lo = k } else if hi.frame > f || hi.frame == sorted.first!.frame { hi = k; break }
        }
        guard lo.frame != hi.frame else { return lo.value }
        let rawT = Double(f - lo.frame) / Double(hi.frame - lo.frame)
        return UMVec2.lerp(lo.value, hi.value, t: lo.easing.apply(rawT))
    }

    // MARK: - Frame resolution for loop modes

    private static func resolvedFrame(
        _ frame: Int, first: Int, last: Int, loopMode: UMLoopMode
    ) -> Int {
        let span     = last - first
        guard span > 0 else { return first }
        let relative = frame - first
        switch loopMode {
        case .once:
            return first + min(max(relative, 0), span)
        case .loop:
            let m = relative % span
            return first + (m < 0 ? m + span : m)
        case .pingPong:
            let cycle = span * 2
            let m     = relative % cycle
            let pos   = m < 0 ? m + cycle : m
            return first + (pos <= span ? pos : cycle - pos)
        }
    }

    // MARK: - Noise / hash helpers

    private static func hash32(_ x: UInt32) -> UInt32 {
        var h = x &* 0x9E3779B9
        h ^= h >> 16
        h &*= 0x85EBCA6B
        h ^= h >> 13
        h &*= 0xC2B2AE35
        h ^= h >> 16
        return h
    }

    private static func jitterValue(seed: Int, index: Int, bucket: Int) -> Double {
        let s = UInt32(bitPattern: Int32(truncatingIfNeeded: seed))
        let i = UInt32(bitPattern: Int32(truncatingIfNeeded: index))
        let b = UInt32(bitPattern: Int32(truncatingIfNeeded: bucket))
        let h = hash32(s &+ hash32(i &+ hash32(b)))
        return Double(h) / Double(UInt32.max) * 2.0 - 1.0
    }

    private static func valueNoise(t: Double, seed: Int) -> Double {
        let ti   = Int(floor(t))
        let frac = t - floor(t)
        let v0   = Double(hash32(UInt32(bitPattern: Int32(truncatingIfNeeded: ti ^ seed)))) / Double(UInt32.max)
        let v1   = Double(hash32(UInt32(bitPattern: Int32(truncatingIfNeeded: (ti + 1) ^ seed)))) / Double(UInt32.max)
        let s    = frac * frac * (3 - 2 * frac)
        return v0 + (v1 - v0) * s
    }
}
