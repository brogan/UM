import Foundation

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

    public static let staticDefault = UMMotionSet(name: "Static")

    public init(
        id:            UUID         = UUID(),
        name:          String       = "Untitled Motion",
        motionPreset:  MotionPreset = .static,
        motionSpeed:   Double       = 1.0,
        motionAmount:  Double       = 0.5,
        motionPhase:   Double       = 0.0,
        orderChaos:    Double       = 0.0,
        framesPerStep: Int          = 4
    ) {
        self.id            = id
        self.name          = name
        self.motionPreset  = motionPreset
        self.motionSpeed   = motionSpeed
        self.motionAmount  = motionAmount
        self.motionPhase   = motionPhase
        self.orderChaos    = orderChaos
        self.framesPerStep = framesPerStep
    }
}
