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
    public var shapeNames:       [String]       // each references a ShapeDef name
    public var sequenceMode:     SequenceMode
    public var framesPerStep:    Int

    // Renderer
    public var rendererSetName:  String
    public var lockedFillHex:    String?        // optional override (hex RGBA)
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

    // Shape assignment (nil = hard-wired default shape)
    public var shapeID:          UUID?

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
        shapeID: UUID? = nil
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
        self.shapeID             = shapeID
    }
}
