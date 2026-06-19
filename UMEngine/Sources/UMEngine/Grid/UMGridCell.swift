import Foundation

public struct UMOffset: Codable, Sendable, Equatable {
    public var dx: Double
    public var dy: Double

    public static let zero = UMOffset(dx: 0, dy: 0)

    public init(dx: Double = 0, dy: Double = 0) {
        self.dx = dx; self.dy = dy
    }

    public func flippedHorizontally() -> UMOffset { UMOffset(dx: -dx, dy:  dy) }
    public func flippedVertically()   -> UMOffset { UMOffset(dx:  dx, dy: -dy) }
    public func rotatedLeft90()       -> UMOffset { UMOffset(dx:  dy, dy: -dx) }
    public func rotatedRight90()      -> UMOffset { UMOffset(dx: -dy, dy:  dx) }
}

public struct UMGridCell: Codable, Identifiable, Sendable {
    public var id:             UUID
    public var gridIndex:      Int
    public var isDrawn:        Bool
    public var styleID:        UUID

    public var positionOffset: UMOffset
    public var phaseOffset:    Int

    public var scaleX:         Double
    public var scaleY:         Double
    public var rotation:       Double

    /// Optional reference to a UMMotionSet in the project motion palette.
    public var motionID: UUID?
    /// Optional reference to a UMShape in the project shape palette.
    public var shapeID:  UUID?
    /// Optional reference to a UMMotionPath in document.paths.
    public var pathID:   UUID?

    /// Baked color from a color map "lock" operation. When set, the cell
    /// uses this color instead of live color map sampling so the color
    /// travels with the cell through transforms.
    public var lockedFillColor:   UMColor?
    public var lockedStrokeColor: UMColor?

    public init(
        gridIndex:      Int,
        styleID:        UUID     = UUID(),
        isDrawn:        Bool     = false,
        positionOffset: UMOffset = .zero,
        phaseOffset:    Int      = 0,
        scaleX:         Double   = 1.0,
        scaleY:         Double   = 1.0,
        rotation:       Double   = 0.0,
        motionID:       UUID?    = nil,
        shapeID:        UUID?    = nil,
        pathID:         UUID?    = nil
    ) {
        self.id             = UUID()
        self.gridIndex      = gridIndex
        self.styleID        = styleID
        self.isDrawn        = isDrawn
        self.positionOffset = positionOffset
        self.phaseOffset    = phaseOffset
        self.scaleX         = scaleX
        self.scaleY         = scaleY
        self.rotation       = rotation
        self.motionID       = motionID
        self.shapeID        = shapeID
        self.pathID         = pathID
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, gridIndex, isDrawn, styleID
        case positionOffset, phaseOffset
        case scaleX, scaleY, rotation
        case motionID, shapeID, pathID
        case lockedFillColor, lockedStrokeColor
    }

    public init(from decoder: Decoder) throws {
        let c               = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decode(UUID.self,     forKey: .id)
        gridIndex           = try c.decode(Int.self,      forKey: .gridIndex)
        isDrawn             = try c.decode(Bool.self,     forKey: .isDrawn)
        styleID             = try c.decode(UUID.self,     forKey: .styleID)
        positionOffset      = try c.decode(UMOffset.self, forKey: .positionOffset)
        phaseOffset         = try c.decode(Int.self,      forKey: .phaseOffset)
        scaleX              = try c.decode(Double.self,   forKey: .scaleX)
        scaleY              = try c.decode(Double.self,   forKey: .scaleY)
        rotation            = try c.decode(Double.self,   forKey: .rotation)
        motionID            = try c.decodeIfPresent(UUID.self,    forKey: .motionID)
        shapeID             = try c.decodeIfPresent(UUID.self,    forKey: .shapeID)
        pathID              = try c.decodeIfPresent(UUID.self,    forKey: .pathID)
        lockedFillColor     = try c.decodeIfPresent(UMColor.self, forKey: .lockedFillColor)
        lockedStrokeColor   = try c.decodeIfPresent(UMColor.self, forKey: .lockedStrokeColor)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,             forKey: .id)
        try c.encode(gridIndex,      forKey: .gridIndex)
        try c.encode(isDrawn,        forKey: .isDrawn)
        try c.encode(styleID,        forKey: .styleID)
        try c.encode(positionOffset, forKey: .positionOffset)
        try c.encode(phaseOffset,    forKey: .phaseOffset)
        try c.encode(scaleX,         forKey: .scaleX)
        try c.encode(scaleY,         forKey: .scaleY)
        try c.encode(rotation,       forKey: .rotation)
        try c.encodeIfPresent(motionID,          forKey: .motionID)
        try c.encodeIfPresent(shapeID,           forKey: .shapeID)
        try c.encodeIfPresent(pathID,            forKey: .pathID)
        try c.encodeIfPresent(lockedFillColor,   forKey: .lockedFillColor)
        try c.encodeIfPresent(lockedStrokeColor, forKey: .lockedStrokeColor)
    }
}
