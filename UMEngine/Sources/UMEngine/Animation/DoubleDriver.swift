import Foundation

public struct UMDoubleKeyframe: Codable, Sendable, Equatable {
    public var frame:  Int
    public var value:  Double
    public var easing: PathEasing

    public init(frame: Int, value: Double, easing: PathEasing = .easeInOut) {
        self.frame  = frame
        self.value  = value
        self.easing = easing
    }
}

public enum UMDoubleDriverMode: String, Codable, CaseIterable, Sendable {
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

/// Animatable double-valued property driver. Stateless — evaluated purely from frame number.
public struct UMDoubleDriver: Codable, Sendable, Equatable {
    public var mode: UMDoubleDriverMode
    public var base: Double

    // oscillator
    public var oscillatorAmplitude: Double
    public var oscillatorPeriod:    Double   // seconds
    public var oscillatorPhase:     Double   // 0–1
    public var oscillatorOffset:    Double

    // jitter
    public var jitterRange:    Double
    public var jitterDuration: Int           // frames between steps
    public var jitterEasing:   PathEasing

    // noise
    public var noiseAmplitude: Double
    public var noiseFrequency: Double        // cycles/second
    public var noiseSeed:      Int

    // keyframe
    public var keyframes: [UMDoubleKeyframe]
    public var loopMode:  UMLoopMode

    public init(
        mode:               UMDoubleDriverMode = .constant,
        base:               Double              = 0,
        oscillatorAmplitude: Double             = 1,
        oscillatorPeriod:    Double             = 2,
        oscillatorPhase:     Double             = 0,
        oscillatorOffset:    Double             = 0,
        jitterRange:         Double             = 1,
        jitterDuration:      Int                = 12,
        jitterEasing:        PathEasing         = .easeInOut,
        noiseAmplitude:      Double             = 1,
        noiseFrequency:      Double             = 1,
        noiseSeed:           Int                = 0,
        keyframes:           [UMDoubleKeyframe] = [],
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

    // Convenience constants
    public static let zero = UMDoubleDriver(mode: .constant, base: 0)
    public static let one  = UMDoubleDriver(mode: .constant, base: 1)
}
