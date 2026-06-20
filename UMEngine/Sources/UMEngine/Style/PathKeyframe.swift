import Foundation

public enum PathEasing: String, Codable, Sendable, CaseIterable {
    case linear      = "linear"
    case easeIn      = "easeIn"
    case easeOut     = "easeOut"
    case easeInOut   = "easeInOut"
    case step        = "step"
    case easeInBack    = "easeInBack"
    case easeOutBack   = "easeOutBack"
    case easeInOutBack = "easeInOutBack"
    case easeOutBounce = "easeOutBounce"

    public var displayName: String {
        switch self {
        case .linear:        return "Linear"
        case .easeIn:        return "Ease In"
        case .easeOut:       return "Ease Out"
        case .easeInOut:     return "Ease In/Out"
        case .step:          return "Step"
        case .easeInBack:    return "Back In"
        case .easeOutBack:   return "Back Out"
        case .easeInOutBack: return "Back In/Out"
        case .easeOutBounce: return "Bounce Out"
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

        case .easeInBack:
            let c = 1.70158
            return (c + 1) * t * t * t - c * t * t

        case .easeOutBack:
            let c = 1.70158
            let u = t - 1
            return 1 + (c + 1) * u * u * u + c * u * u

        case .easeInOutBack:
            let c = 1.70158 * 1.525
            if t < 0.5 {
                return (pow(2 * t, 2) * ((c + 1) * 2 * t - c)) / 2
            } else {
                return (pow(2 * t - 2, 2) * ((c + 1) * (2 * t - 2) + c) + 2) / 2
            }

        case .easeOutBounce:
            let d = 2.75, n = 7.5625
            if t < 1 / d        { return n * t * t }
            else if t < 2 / d   { let u = t - 1.5 / d;   return n * u * u + 0.75 }
            else if t < 2.5 / d { let u = t - 2.25 / d;  return n * u * u + 0.9375 }
            else                 { let u = t - 2.625 / d; return n * u * u + 0.984375 }
        }
    }
}

/// One sample point on a UMMotionPath.
///
/// Position offsets (dx, dy) are stored in **cell-fraction units** so that paths
/// are independent of grid resolution: 1.0 = shift one full cell dimension.
/// The easing field describes the curve from *this* keyframe to the *next* one.
///
/// Tangent fields (outTangentX/Y, inTangentX/Y) are also in cell-fraction units.
/// Both default to zero (degenerate = current linear behaviour; backward compatible).
/// When either endpoint has a non-zero tangent, cubic Bezier interpolation is used
/// for position (with linear time t), superseding the easing enum for position only.
/// `smooth` mirrors the opposite tangent for C1 continuity when dragging.
public struct PathKeyframe: Codable, Identifiable, Sendable {
    public var id:          UUID
    public var frame:       Int
    public var dx:          Double      // +right, cell-width fractions
    public var dy:          Double      // +down,  cell-height fractions
    public var rotation:    Double      // degrees
    public var scaleX:      Double
    public var scaleY:      Double
    public var easing:      PathEasing  // curve from this keyframe to the next (position when no tangents)
    public var outTangentX: Double      // out control-point offset from this KF, cell-fraction units
    public var outTangentY: Double
    public var inTangentX:  Double      // in control-point offset from this KF, cell-fraction units
    public var inTangentY:  Double
    public var smooth:      Bool        // mirror in↔out for C1 continuity

    public var hasTangents: Bool {
        outTangentX != 0 || outTangentY != 0 || inTangentX != 0 || inTangentY != 0
    }

    public init(frame: Int,
                dx: Double = 0, dy: Double = 0,
                rotation: Double = 0,
                scaleX: Double = 1, scaleY: Double = 1,
                easing: PathEasing = .easeInOut) {
        self.id          = UUID()
        self.frame       = frame
        self.dx          = dx
        self.dy          = dy
        self.rotation    = rotation
        self.scaleX      = scaleX
        self.scaleY      = scaleY
        self.easing      = easing
        self.outTangentX = 0
        self.outTangentY = 0
        self.inTangentX  = 0
        self.inTangentY  = 0
        self.smooth      = false
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, frame, dx, dy, rotation, scaleX, scaleY, easing
        case outTangentX, outTangentY, inTangentX, inTangentY, smooth
    }

    public init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,       forKey: .id)
        frame        = try c.decode(Int.self,        forKey: .frame)
        dx           = try c.decode(Double.self,     forKey: .dx)
        dy           = try c.decode(Double.self,     forKey: .dy)
        rotation     = try c.decode(Double.self,     forKey: .rotation)
        scaleX       = try c.decode(Double.self,     forKey: .scaleX)
        scaleY       = try c.decode(Double.self,     forKey: .scaleY)
        easing       = try c.decode(PathEasing.self, forKey: .easing)
        outTangentX  = (try? c.decodeIfPresent(Double.self, forKey: .outTangentX)) ?? 0
        outTangentY  = (try? c.decodeIfPresent(Double.self, forKey: .outTangentY)) ?? 0
        inTangentX   = (try? c.decodeIfPresent(Double.self, forKey: .inTangentX))  ?? 0
        inTangentY   = (try? c.decodeIfPresent(Double.self, forKey: .inTangentY))  ?? 0
        smooth       = (try? c.decodeIfPresent(Bool.self,   forKey: .smooth))       ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(frame,    forKey: .frame)
        try c.encode(dx,       forKey: .dx)
        try c.encode(dy,       forKey: .dy)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(scaleX,   forKey: .scaleX)
        try c.encode(scaleY,   forKey: .scaleY)
        try c.encode(easing,   forKey: .easing)
        if outTangentX != 0 { try c.encode(outTangentX, forKey: .outTangentX) }
        if outTangentY != 0 { try c.encode(outTangentY, forKey: .outTangentY) }
        if inTangentX  != 0 { try c.encode(inTangentX,  forKey: .inTangentX) }
        if inTangentY  != 0 { try c.encode(inTangentY,  forKey: .inTangentY) }
        if smooth            { try c.encode(smooth,      forKey: .smooth) }
    }
}
