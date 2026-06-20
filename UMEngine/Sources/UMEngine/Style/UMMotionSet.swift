import Foundation

// MARK: - SequenceMode

public enum SequenceMode: String, Codable, CaseIterable, Sendable {
    case off        // use each cell's own shapeID
    case sequential // advance through shapeIDs in order every framesPerStep frames
    case random     // deterministic random pick per framesPerStep step

    public var displayName: String {
        switch self {
        case .off:        return "Off"
        case .sequential: return "Sequential"
        case .random:     return "Random"
        }
    }
}

// MARK: - UMMotionSet

/// A named, reusable motion configuration — one of four independent axes per cell.
/// Contains all parametric motion parameters previously embedded in CellStyle.
public struct UMMotionSet: Codable, Identifiable, Sendable {
    public var id:            UUID
    public var name:          String
    public var motionPreset:  MotionPreset
    public var motionSpeed:   Double
    public var motionAmount:  Double
    public var motionPhase:   Double
    public var orderChaos:    Double
    public var framesPerStep: Int
    public var sequenceMode:  SequenceMode
    public var shapeIDs:      [UUID]

    /// Per-axis multipliers (0 = suppressed, 1 = full, fractional = attenuated).
    /// Applied after the preset's parametric output; existing projects decode to 1.0 (no change).
    public var axisX:        Double   // position X
    public var axisY:        Double   // position Y
    public var axisRotation: Double   // rotation
    public var axisScale:    Double   // scale deviation from 1.0

    public static let staticDefault = UMMotionSet(name: "Static")

    public init(
        id:            UUID         = UUID(),
        name:          String       = "Untitled Motion",
        motionPreset:  MotionPreset = .static,
        motionSpeed:   Double       = 1.0,
        motionAmount:  Double       = 0.5,
        motionPhase:   Double       = 0.0,
        orderChaos:    Double       = 0.0,
        framesPerStep: Int          = 4,
        sequenceMode:  SequenceMode = .off,
        shapeIDs:      [UUID]       = [],
        axisX:        Double = 1.0,
        axisY:        Double = 1.0,
        axisRotation: Double = 1.0,
        axisScale:    Double = 1.0
    ) {
        self.id            = id
        self.name          = name
        self.motionPreset  = motionPreset
        self.motionSpeed   = motionSpeed
        self.motionAmount  = motionAmount
        self.motionPhase   = motionPhase
        self.orderChaos    = orderChaos
        self.framesPerStep = framesPerStep
        self.sequenceMode  = sequenceMode
        self.shapeIDs      = shapeIDs
        self.axisX         = axisX
        self.axisY         = axisY
        self.axisRotation  = axisRotation
        self.axisScale     = axisScale
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, motionPreset, motionSpeed, motionAmount, motionPhase
        case orderChaos, framesPerStep, sequenceMode, shapeIDs
        case axisX, axisY, axisRotation, axisScale
    }

    public init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        motionPreset   = (try? c.decodeIfPresent(MotionPreset.self,  forKey: .motionPreset))  ?? .static
        motionSpeed    = (try? c.decodeIfPresent(Double.self,        forKey: .motionSpeed))   ?? 1.0
        motionAmount   = (try? c.decodeIfPresent(Double.self,        forKey: .motionAmount))  ?? 0.5
        motionPhase    = (try? c.decodeIfPresent(Double.self,        forKey: .motionPhase))   ?? 0.0
        orderChaos     = (try? c.decodeIfPresent(Double.self,        forKey: .orderChaos))    ?? 0.0
        framesPerStep  = (try? c.decodeIfPresent(Int.self,           forKey: .framesPerStep)) ?? 4
        sequenceMode   = (try? c.decodeIfPresent(SequenceMode.self,  forKey: .sequenceMode))  ?? .off
        shapeIDs       = (try? c.decodeIfPresent([UUID].self,        forKey: .shapeIDs))      ?? []
        axisX          = (try? c.decodeIfPresent(Double.self,        forKey: .axisX))         ?? 1.0
        axisY          = (try? c.decodeIfPresent(Double.self,        forKey: .axisY))         ?? 1.0
        axisRotation   = (try? c.decodeIfPresent(Double.self,        forKey: .axisRotation))  ?? 1.0
        axisScale      = (try? c.decodeIfPresent(Double.self,        forKey: .axisScale))     ?? 1.0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,            forKey: .id)
        try c.encode(name,          forKey: .name)
        try c.encode(motionPreset,  forKey: .motionPreset)
        try c.encode(motionSpeed,   forKey: .motionSpeed)
        try c.encode(motionAmount,  forKey: .motionAmount)
        try c.encode(motionPhase,   forKey: .motionPhase)
        try c.encode(orderChaos,    forKey: .orderChaos)
        try c.encode(framesPerStep, forKey: .framesPerStep)
        try c.encode(sequenceMode,  forKey: .sequenceMode)
        if !shapeIDs.isEmpty { try c.encode(shapeIDs, forKey: .shapeIDs) }
        if axisX        != 1.0 { try c.encode(axisX,        forKey: .axisX) }
        if axisY        != 1.0 { try c.encode(axisY,        forKey: .axisY) }
        if axisRotation != 1.0 { try c.encode(axisRotation, forKey: .axisRotation) }
        if axisScale    != 1.0 { try c.encode(axisScale,    forKey: .axisScale) }
    }
}
