import Foundation

public enum PathEasing: String, Codable, Sendable, CaseIterable {
    case linear    = "linear"
    case easeIn    = "easeIn"
    case easeOut   = "easeOut"
    case easeInOut = "easeInOut"
    case step      = "step"

    public var displayName: String {
        switch self {
        case .linear:    return "Linear"
        case .easeIn:    return "Ease In"
        case .easeOut:   return "Ease Out"
        case .easeInOut: return "Ease In/Out"
        case .step:      return "Step"
        }
    }

    // Easing curve applied to normalised t ∈ [0, 1].
    // "step" jumps at t=1, so the FROM keyframe holds until the TO keyframe.
    public func apply(_ t: Double) -> Double {
        switch self {
        case .linear:    return t
        case .step:      return t < 1 ? 0 : 1
        case .easeIn:    return t * t
        case .easeOut:   return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}

/// One sample point on a UMMotionPath.
///
/// Position offsets (dx, dy) are stored in **cell-fraction units** so that paths
/// are independent of grid resolution: 1.0 = shift one full cell dimension.
/// The easing field describes the curve from *this* keyframe to the *next* one.
public struct PathKeyframe: Codable, Identifiable, Sendable {
    public var id:       UUID
    public var frame:    Int
    public var dx:       Double      // +right, cell-width fractions
    public var dy:       Double      // +down,  cell-height fractions
    public var rotation: Double      // degrees, added to cell.rotation + parametric rotation
    public var scaleX:   Double      // multiplied with cell.scaleX and parametric scaleX
    public var scaleY:   Double
    public var easing:   PathEasing  // curve from this keyframe to the next

    public init(frame: Int,
                dx: Double = 0, dy: Double = 0,
                rotation: Double = 0,
                scaleX: Double = 1, scaleY: Double = 1,
                easing: PathEasing = .easeInOut) {
        self.id       = UUID()
        self.frame    = frame
        self.dx       = dx
        self.dy       = dy
        self.rotation = rotation
        self.scaleX   = scaleX
        self.scaleY   = scaleY
        self.easing   = easing
    }
}
