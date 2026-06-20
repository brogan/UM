import Foundation

// MARK: - Layer mode

public enum LayerMode: String, Codable, Sendable {
    case grid    // default — UMGridDocument / UMGridEngine rendering
    case sprite  // free-placed UMSprite list; grid engine present but empty
}

// MARK: - Per-polygon color override

/// Overrides the style's fill and/or stroke for a specific polygon index within a shape.
/// Keyed by polygon index in the shape's array — stable as long as the shape is not
/// re-imported with different polygon ordering.
public struct UMPolygonOverride: Codable, Sendable {
    public var fill:   UMColor?
    public var stroke: UMColor?

    public init(fill: UMColor? = nil, stroke: UMColor? = nil) {
        self.fill   = fill
        self.stroke = stroke
    }
}

// MARK: - UMSprite

/// A free-placed sprite in a sprite layer. Position is stored as normalized [0,1]
/// fractions of canvas dimensions. At render time: displayX = x * gridW.
public struct UMSprite: Codable, Identifiable, Sendable {
    public var id:               UUID
    public var name:             String
    public var x:                Double      // normalized 0–1 fraction of canvas width
    public var y:                Double      // normalized 0–1 fraction of canvas height
    public var rotation:         Double      // degrees
    public var scaleX:           Double      // 1.0 = reference size
    public var scaleY:           Double
    public var styleID:          UUID?
    public var shapeID:          UUID?
    public var motionID:         UUID?
    public var phaseOffset:      Int
    public var polygonOverrides: [Int: UMPolygonOverride]
    /// Animated position offset added on top of (x*gridW + motion.dx). Output units are canvas pixels.
    public var positionDriver:   UMVectorDriver

    public init(
        id:               UUID                     = UUID(),
        name:             String                   = "Sprite",
        x:                Double                   = 0,
        y:                Double                   = 0,
        rotation:         Double                   = 0,
        scaleX:           Double                   = 1.0,
        scaleY:           Double                   = 1.0,
        styleID:          UUID?                    = nil,
        shapeID:          UUID?                    = nil,
        motionID:         UUID?                    = nil,
        phaseOffset:      Int                      = 0,
        polygonOverrides: [Int: UMPolygonOverride] = [:],
        positionDriver:   UMVectorDriver            = .zero
    ) {
        self.id               = id
        self.name             = name
        self.x                = x
        self.y                = y
        self.rotation         = rotation
        self.scaleX           = scaleX
        self.scaleY           = scaleY
        self.styleID          = styleID
        self.shapeID          = shapeID
        self.motionID         = motionID
        self.phaseOffset      = phaseOffset
        self.polygonOverrides = polygonOverrides
        self.positionDriver   = positionDriver
    }

    // MARK: Codable — [Int: T] keys need String bridging

    private enum CodingKeys: String, CodingKey {
        case id, name, x, y, rotation, scaleX, scaleY
        case styleID, shapeID, motionID, phaseOffset, polygonOverrides
        case positionDriver
    }

    public init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try  c.decode(UUID.self,   forKey: .id)
        name          = try  c.decode(String.self, forKey: .name)
        x             = (try? c.decodeIfPresent(Double.self, forKey: .x))        ?? 0
        y             = (try? c.decodeIfPresent(Double.self, forKey: .y))        ?? 0
        rotation      = (try? c.decodeIfPresent(Double.self, forKey: .rotation)) ?? 0
        scaleX        = (try? c.decodeIfPresent(Double.self, forKey: .scaleX))   ?? 1.0
        scaleY        = (try? c.decodeIfPresent(Double.self, forKey: .scaleY))   ?? 1.0
        styleID       = try? c.decodeIfPresent(UUID.self, forKey: .styleID)
        shapeID       = try? c.decodeIfPresent(UUID.self, forKey: .shapeID)
        motionID      = try? c.decodeIfPresent(UUID.self, forKey: .motionID)
        phaseOffset   = (try? c.decodeIfPresent(Int.self,              forKey: .phaseOffset))    ?? 0
        positionDriver = (try? c.decodeIfPresent(UMVectorDriver.self,  forKey: .positionDriver)) ?? .zero
        // [Int: UMPolygonOverride] — JSON keys are strings; decode via [String: T] then rekey
        let rawOvr    = (try? c.decodeIfPresent([String: UMPolygonOverride].self, forKey: .polygonOverrides)) ?? [:]
        polygonOverrides = Dictionary(uniqueKeysWithValues: rawOvr.compactMap { k, v in
            guard let i = Int(k) else { return nil }
            return (i, v)
        })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(name,     forKey: .name)
        try c.encode(x,        forKey: .x)
        try c.encode(y,        forKey: .y)
        if rotation  != 0   { try c.encode(rotation,  forKey: .rotation) }
        if scaleX    != 1.0 { try c.encode(scaleX,    forKey: .scaleX) }
        if scaleY    != 1.0 { try c.encode(scaleY,    forKey: .scaleY) }
        if let v = styleID   { try c.encode(v, forKey: .styleID) }
        if let v = shapeID   { try c.encode(v, forKey: .shapeID) }
        if let v = motionID  { try c.encode(v, forKey: .motionID) }
        if phaseOffset != 0  { try c.encode(phaseOffset, forKey: .phaseOffset) }
        if positionDriver != .zero { try c.encode(positionDriver, forKey: .positionDriver) }
        if !polygonOverrides.isEmpty {
            let strKeyed = Dictionary(uniqueKeysWithValues: polygonOverrides.map { (String($0.key), $0.value) })
            try c.encode(strKeyed, forKey: .polygonOverrides)
        }
    }
}
