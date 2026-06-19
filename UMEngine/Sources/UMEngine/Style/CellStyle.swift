import Foundation

/// Pure visual rendering properties for a grid cell.
/// Motion, shape, and path are independent axes assigned directly to cells.
public struct CellStyle: Codable, Identifiable, Sendable {
    public var id:               UUID
    public var name:             String
    public var lockedFillHex:    String?
    public var lockedStrokeHex:  String?
    public var fillColor:        UMColor
    public var strokeColor:      UMColor
    public var strokeWidth:      Double
    public var renderMode:       UMRenderMode

    public init(
        name:        String       = "Untitled",
        fillColor:   UMColor      = .defaultFill,
        strokeColor: UMColor      = .defaultStroke,
        strokeWidth: Double       = 1.5,
        renderMode:  UMRenderMode = .filledStroked
    ) {
        self.id              = UUID()
        self.name            = name
        self.lockedFillHex   = nil
        self.lockedStrokeHex = nil
        self.fillColor       = fillColor
        self.strokeColor     = strokeColor
        self.strokeWidth     = strokeWidth
        self.renderMode      = renderMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case lockedFillHex, lockedStrokeHex
        case fillColor, strokeColor, strokeWidth, renderMode
    }

    public init(from decoder: Decoder) throws {
        let c            = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,    forKey: .id)
        name             = try c.decode(String.self,  forKey: .name)
        lockedFillHex    = try? c.decodeIfPresent(String.self,        forKey: .lockedFillHex)
        lockedStrokeHex  = try? c.decodeIfPresent(String.self,        forKey: .lockedStrokeHex)
        fillColor        = (try? c.decodeIfPresent(UMColor.self,       forKey: .fillColor))   ?? .defaultFill
        strokeColor      = (try? c.decodeIfPresent(UMColor.self,       forKey: .strokeColor)) ?? .defaultStroke
        strokeWidth      = (try? c.decodeIfPresent(Double.self,        forKey: .strokeWidth)) ?? 1.5
        renderMode       = (try? c.decodeIfPresent(UMRenderMode.self,  forKey: .renderMode))  ?? .filledStroked
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(name,             forKey: .name)
        try c.encodeIfPresent(lockedFillHex,   forKey: .lockedFillHex)
        try c.encodeIfPresent(lockedStrokeHex, forKey: .lockedStrokeHex)
        try c.encode(fillColor,        forKey: .fillColor)
        try c.encode(strokeColor,      forKey: .strokeColor)
        try c.encode(strokeWidth,      forKey: .strokeWidth)
        try c.encode(renderMode,       forKey: .renderMode)
    }
}
