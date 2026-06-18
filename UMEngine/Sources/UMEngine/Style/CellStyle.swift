import Foundation

public enum SequenceMode: String, Codable, Sendable, CaseIterable {
    case sequential
    case all
    case random
}

/// The primary creative unit in UM.  Merges what Java UM split across
/// DrawSet, Drawer, Animator, and BRenderer into a single named entity.
public struct CellStyle: Codable, Identifiable, Sendable {
    public var id:               UUID
    public var name:             String

    // Shape sequence (replaces DrawSet + Drawers)
    public var shapeNames:       [String]       // legacy named refs (not used in current renderer)
    public var sequenceMode:     SequenceMode
    public var framesPerStep:    Int

    // Renderer
    public var rendererSetName:  String
    public var lockedFillHex:    String?
    public var lockedStrokeHex:  String?
    public var fillColor:        UMColor
    public var strokeColor:      UMColor
    public var strokeWidth:      Double
    public var renderMode:       UMRenderMode

    // Motion preset
    public var motionPreset:     MotionPreset
    public var motionSpeed:      Double         // maps to freqHz
    public var motionAmount:     Double         // maps to amplitude
    public var motionPhase:      Double         // oscillator phase within cycle (not cell phase offset)

    // Order ←→ Chaos (0 = fully ordered, 1 = fully chaotic)
    public var orderChaos:       Double

    // Subdivision
    public var subdivParamsSetName: String

    // Assigned shapes, in sequence order.  SEQUENCE mode cycles through this list.
    public var shapeIDs:         [UUID]

    /// Convenience: first assigned shape (nil when none assigned).
    public var shapeID: UUID? { shapeIDs.first }

    public init(
        name: String = "Untitled",
        shapeNames: [String] = [],
        sequenceMode: SequenceMode = .sequential,
        framesPerStep: Int = 4,
        rendererSetName: String = "",
        fillColor: UMColor = .defaultFill,
        strokeColor: UMColor = .defaultStroke,
        strokeWidth: Double = 1.5,
        renderMode: UMRenderMode = .filledStroked,
        motionPreset: MotionPreset = .static,
        motionSpeed: Double = 1.0,
        motionAmount: Double = 0.5,
        motionPhase: Double = 0.0,
        orderChaos: Double = 0.0,
        subdivParamsSetName: String = "",
        shapeIDs: [UUID] = []
    ) {
        self.id                  = UUID()
        self.name                = name
        self.shapeNames          = shapeNames
        self.sequenceMode        = sequenceMode
        self.framesPerStep       = framesPerStep
        self.rendererSetName     = rendererSetName
        self.lockedFillHex       = nil
        self.lockedStrokeHex     = nil
        self.fillColor           = fillColor
        self.strokeColor         = strokeColor
        self.strokeWidth         = strokeWidth
        self.renderMode          = renderMode
        self.motionPreset        = motionPreset
        self.motionSpeed         = motionSpeed
        self.motionAmount        = motionAmount
        self.motionPhase         = motionPhase
        self.orderChaos          = orderChaos
        self.subdivParamsSetName = subdivParamsSetName
        self.shapeIDs            = shapeIDs
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, shapeNames, sequenceMode, framesPerStep
        case rendererSetName, lockedFillHex, lockedStrokeHex
        case fillColor, strokeColor, strokeWidth, renderMode
        case motionPreset, motionSpeed, motionAmount, motionPhase
        case orderChaos, subdivParamsSetName
        case shapeIDs           // canonical (current)
        case shapeID            // legacy — written by older .umproj files
    }

    public init(from decoder: Decoder) throws {
        let c               = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decode(UUID.self, forKey: .id)
        name                = try c.decode(String.self, forKey: .name)
        shapeNames          = (try? c.decodeIfPresent([String].self,     forKey: .shapeNames))          ?? []
        sequenceMode        = (try? c.decodeIfPresent(SequenceMode.self, forKey: .sequenceMode))        ?? .sequential
        framesPerStep       = (try? c.decodeIfPresent(Int.self,          forKey: .framesPerStep))       ?? 4
        rendererSetName     = (try? c.decodeIfPresent(String.self,       forKey: .rendererSetName))     ?? ""
        lockedFillHex       = try? c.decodeIfPresent(String.self,        forKey: .lockedFillHex)
        lockedStrokeHex     = try? c.decodeIfPresent(String.self,        forKey: .lockedStrokeHex)
        fillColor           = (try? c.decodeIfPresent(UMColor.self,      forKey: .fillColor))           ?? .defaultFill
        strokeColor         = (try? c.decodeIfPresent(UMColor.self,      forKey: .strokeColor))         ?? .defaultStroke
        strokeWidth         = (try? c.decodeIfPresent(Double.self,       forKey: .strokeWidth))         ?? 1.5
        renderMode          = (try? c.decodeIfPresent(UMRenderMode.self, forKey: .renderMode))          ?? .filledStroked
        motionPreset        = (try? c.decodeIfPresent(MotionPreset.self, forKey: .motionPreset))        ?? .static
        motionSpeed         = (try? c.decodeIfPresent(Double.self,       forKey: .motionSpeed))         ?? 1.0
        motionAmount        = (try? c.decodeIfPresent(Double.self,       forKey: .motionAmount))        ?? 0.5
        motionPhase         = (try? c.decodeIfPresent(Double.self,       forKey: .motionPhase))         ?? 0.0
        orderChaos          = (try? c.decodeIfPresent(Double.self,       forKey: .orderChaos))          ?? 0.0
        subdivParamsSetName = (try? c.decodeIfPresent(String.self,       forKey: .subdivParamsSetName)) ?? ""
        // Migration: prefer shapeIDs list; fall back to legacy single shapeID
        do {
            if let ids = try c.decodeIfPresent([UUID].self, forKey: .shapeIDs) {
                shapeIDs = ids
            } else if let single = try c.decodeIfPresent(UUID.self, forKey: .shapeID) {
                shapeIDs = [single]
            } else {
                shapeIDs = []
            }
        } catch {
            shapeIDs = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                  forKey: .id)
        try c.encode(name,                forKey: .name)
        try c.encode(shapeNames,          forKey: .shapeNames)
        try c.encode(sequenceMode,        forKey: .sequenceMode)
        try c.encode(framesPerStep,       forKey: .framesPerStep)
        try c.encode(rendererSetName,     forKey: .rendererSetName)
        try c.encodeIfPresent(lockedFillHex,   forKey: .lockedFillHex)
        try c.encodeIfPresent(lockedStrokeHex, forKey: .lockedStrokeHex)
        try c.encode(fillColor,           forKey: .fillColor)
        try c.encode(strokeColor,         forKey: .strokeColor)
        try c.encode(strokeWidth,         forKey: .strokeWidth)
        try c.encode(renderMode,          forKey: .renderMode)
        try c.encode(motionPreset,        forKey: .motionPreset)
        try c.encode(motionSpeed,         forKey: .motionSpeed)
        try c.encode(motionAmount,        forKey: .motionAmount)
        try c.encode(motionPhase,         forKey: .motionPhase)
        try c.encode(orderChaos,          forKey: .orderChaos)
        try c.encode(subdivParamsSetName, forKey: .subdivParamsSetName)
        try c.encode(shapeIDs,            forKey: .shapeIDs)
    }
}
