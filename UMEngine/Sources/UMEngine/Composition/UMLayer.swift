import Foundation

/// How the grid scroll behaves at its edges.
public enum GridScrollMode: String, Codable, CaseIterable, Sendable {
    case wrap    // toroidal: cells that exit one edge re-enter from the opposite edge
    case consume // cells that exit are gone; vacated positions are empty
    case clamp   // scroll stops at the boundary; edge cells pin in place
}

/// One layer in a composition. Each layer owns an independent grid document
/// (its own rows/cols, cells, styles, paths, shapes) and renders into the shared canvas
/// area at a given opacity. Layers are composited bottom-to-top.
public struct UMLayer: Codable, Identifiable, Sendable {
    public var id:        UUID
    public var name:      String
    public var isVisible: Bool
    public var opacity:   Double      // 0–1; 1 = fully opaque

    /// Parallax response to camera pan.
    /// 0 = fixed to screen (distant background, no movement).
    /// 1 = full response (foreground, moves fully with camera).
    public var parallaxFactor: Double

    /// Per-layer positional offset independent of camera (driven or constant).
    public var layerOffset: UMVectorDriver

    /// Animated opacity driver. When mode is .constant, `base` mirrors `opacity`.
    /// Non-constant modes override the opacity slider.
    public var opacityDriver: UMDoubleDriver

    /// Tank-tread grid scroll, expressed in cell units (1.0 = one full cell width/height).
    public var gridScrollDriver: UMVectorDriver
    /// Edge behaviour when the scroll moves cells past the grid boundary.
    public var gridScrollMode: GridScrollMode

    public var document:  UMGridDocument

    /// Whether this layer renders as a grid or free-placed sprites.
    public var layerMode: LayerMode
    /// Free-placed sprites (only meaningful when layerMode == .sprite).
    public var sprites:   [UMSprite]

    public init(
        id:              UUID            = UUID(),
        name:            String          = "Layer",
        isVisible:       Bool            = true,
        opacity:         Double          = 1.0,
        parallaxFactor:  Double          = 1.0,
        layerOffset:     UMVectorDriver  = .zero,
        opacityDriver:   UMDoubleDriver  = .one,
        gridScrollDriver: UMVectorDriver = .zero,
        gridScrollMode:  GridScrollMode  = .wrap,
        document:        UMGridDocument  = UMGridDocument.makeDefault(),
        layerMode:       LayerMode       = .grid,
        sprites:         [UMSprite]      = []
    ) {
        self.id               = id
        self.name             = name
        self.isVisible        = isVisible
        self.opacity          = opacity
        self.parallaxFactor   = parallaxFactor
        self.layerOffset      = layerOffset
        self.opacityDriver    = opacityDriver
        self.gridScrollDriver = gridScrollDriver
        self.gridScrollMode   = gridScrollMode
        self.document         = document
        self.layerMode        = layerMode
        self.sprites          = sprites
    }

    // MARK: - Codable (backward-compatible: new fields use decodeIfPresent)

    private enum CodingKeys: String, CodingKey {
        case id, name, isVisible, opacity, document
        case parallaxFactor, layerOffset, opacityDriver
        case gridScrollDriver, gridScrollMode
        case layerMode, sprites
    }

    public init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,           forKey: .id)
        name           = try c.decode(String.self,         forKey: .name)
        isVisible      = try c.decode(Bool.self,           forKey: .isVisible)
        opacity        = try c.decode(Double.self,         forKey: .opacity)
        document       = try c.decode(UMGridDocument.self, forKey: .document)
        parallaxFactor    = try c.decodeIfPresent(Double.self,        forKey: .parallaxFactor)    ?? 1.0
        layerOffset       = try c.decodeIfPresent(UMVectorDriver.self, forKey: .layerOffset)      ?? .zero
        gridScrollDriver  = try c.decodeIfPresent(UMVectorDriver.self, forKey: .gridScrollDriver) ?? .zero
        gridScrollMode    = try c.decodeIfPresent(GridScrollMode.self, forKey: .gridScrollMode)   ?? .wrap
        layerMode         = try c.decodeIfPresent(LayerMode.self,  forKey: .layerMode) ?? .grid
        sprites           = try c.decodeIfPresent([UMSprite].self, forKey: .sprites)   ?? []
        // Backward compat: existing files have no opacityDriver; seed from opacity
        if let od = try c.decodeIfPresent(UMDoubleDriver.self, forKey: .opacityDriver) {
            opacityDriver = od
        } else {
            opacityDriver = UMDoubleDriver(mode: .constant, base: opacity)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(name,             forKey: .name)
        try c.encode(isVisible,        forKey: .isVisible)
        try c.encode(opacity,          forKey: .opacity)
        try c.encode(document,         forKey: .document)
        try c.encode(parallaxFactor,   forKey: .parallaxFactor)
        try c.encode(layerOffset,      forKey: .layerOffset)
        try c.encode(opacityDriver,    forKey: .opacityDriver)
        try c.encode(gridScrollDriver, forKey: .gridScrollDriver)
        try c.encode(gridScrollMode,   forKey: .gridScrollMode)
        if layerMode != .grid  { try c.encode(layerMode, forKey: .layerMode) }
        if !sprites.isEmpty    { try c.encode(sprites,   forKey: .sprites) }
    }
}
