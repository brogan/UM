import Foundation

/// Named animation character presets.  Each maps to a specific configuration of
/// Loom's AnimationDriver system (wired up in OrderChaosEngine when rendering is integrated).
public enum MotionPreset: String, Codable, Sendable, CaseIterable {
    case `static`  = "static"
    case spin      = "spin"
    case pulse     = "pulse"
    case wave      = "wave"
    case wander    = "wander"
    case jitter    = "jitter"
    case colorCycle = "colorCycle"
    case custom    = "custom"

    public var displayName: String {
        switch self {
        case .static:     return "Static"
        case .spin:       return "Spin"
        case .pulse:      return "Pulse"
        case .wave:       return "Wave"
        case .wander:     return "Wander"
        case .jitter:     return "Jitter"
        case .colorCycle: return "Color Cycle"
        case .custom:     return "Custom"
        }
    }

    // Loom driver mappings (implemented when rendering is wired in):
    //   .spin       → rotationDriver: .oscillator  (sine wave)
    //   .pulse      → scaleDriver:    .oscillator  (sine wave)
    //   .wave       → positionDriver: .oscillator  (X freq ≠ Y freq → Lissajous)
    //   .wander     → positionDriver: .noise
    //   .jitter     → positionDriver: .jitter + rotationDriver: .jitter
    //   .colorCycle → ColorDriver:    .keyframe on renderer palette
    //   .custom     → raw SpriteAnimation from cell's customAnimation field
}
