import Foundation

public struct UMVectorKeyframe: Codable, Sendable, Equatable {
    public var frame:  Int
    public var value:  UMVec2
    public var easing: PathEasing

    public init(frame: Int, value: UMVec2, easing: PathEasing = .easeInOut) {
        self.frame  = frame
        self.value  = value
        self.easing = easing
    }
}

public enum UMVectorDriverMode: String, Codable, CaseIterable, Sendable {
    case constant, jitter, noise, oscillator, keyframe
    public var displayName: String {
        switch self {
        case .constant:   return "Constant"
        case .jitter:     return "Jitter"
        case .noise:      return "Noise"
        case .oscillator: return "Oscillator"
        case .keyframe:   return "Keyframe"
        }
    }
}

/// Animatable 2D vector property driver. Stateless — evaluated purely from frame number.
public struct UMVectorDriver: Codable, Sendable, Equatable {
    public var mode: UMVectorDriverMode
    public var base: UMVec2

    // oscillator (independent amplitude per axis)
    public var oscillatorAmplitude: UMVec2
    public var oscillatorPeriod:    Double   // seconds
    public var oscillatorPhase:     Double   // 0–1
    public var oscillatorOffset:    UMVec2

    // jitter
    public var jitterRange:    UMVec2
    public var jitterDuration: Int           // frames between steps
    public var jitterEasing:   PathEasing

    // noise
    public var noiseAmplitude: UMVec2
    public var noiseFrequency: Double        // cycles/second
    public var noiseSeed:      Int

    // keyframe
    public var keyframes: [UMVectorKeyframe]
    public var loopMode:  UMLoopMode

    public init(
        mode:               UMVectorDriverMode  = .constant,
        base:               UMVec2              = .zero,
        oscillatorAmplitude: UMVec2             = .one,
        oscillatorPeriod:    Double             = 2,
        oscillatorPhase:     Double             = 0,
        oscillatorOffset:    UMVec2             = .zero,
        jitterRange:         UMVec2             = .one,
        jitterDuration:      Int                = 12,
        jitterEasing:        PathEasing         = .easeInOut,
        noiseAmplitude:      UMVec2             = .one,
        noiseFrequency:      Double             = 1,
        noiseSeed:           Int                = 0,
        keyframes:           [UMVectorKeyframe] = [],
        loopMode:            UMLoopMode         = .loop
    ) {
        self.mode               = mode
        self.base               = base
        self.oscillatorAmplitude = oscillatorAmplitude
        self.oscillatorPeriod    = oscillatorPeriod
        self.oscillatorPhase     = oscillatorPhase
        self.oscillatorOffset    = oscillatorOffset
        self.jitterRange         = jitterRange
        self.jitterDuration      = jitterDuration
        self.jitterEasing        = jitterEasing
        self.noiseAmplitude      = noiseAmplitude
        self.noiseFrequency      = noiseFrequency
        self.noiseSeed           = noiseSeed
        self.keyframes           = keyframes
        self.loopMode            = loopMode
    }

    // Convenience constant
    public static let zero = UMVectorDriver(mode: .constant, base: .zero)
}
