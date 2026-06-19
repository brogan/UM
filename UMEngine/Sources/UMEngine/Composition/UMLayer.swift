import Foundation

/// One sprite layer in a composition. Each layer owns an independent grid document
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

    public var document:  UMGridDocument

    public init(
        id:            UUID            = UUID(),
        name:          String          = "Layer",
        isVisible:     Bool            = true,
        opacity:       Double          = 1.0,
        parallaxFactor: Double         = 1.0,
        layerOffset:   UMVectorDriver    = .zero,
        opacityDriver: UMDoubleDriver    = .one,
        document:      UMGridDocument  = UMGridDocument.makeDefault()
    ) {
        self.id            = id
        self.name          = name
        self.isVisible     = isVisible
        self.opacity       = opacity
        self.parallaxFactor = parallaxFactor
        self.layerOffset   = layerOffset
        self.opacityDriver  = opacityDriver
        self.document      = document
    }

    // MARK: - Codable (backward-compatible: new fields use decodeIfPresent)

    private enum CodingKeys: String, CodingKey {
        case id, name, isVisible, opacity, document
        case parallaxFactor, layerOffset, opacityDriver
    }

    public init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,          forKey: .id)
        name           = try c.decode(String.self,        forKey: .name)
        isVisible      = try c.decode(Bool.self,          forKey: .isVisible)
        opacity        = try c.decode(Double.self,        forKey: .opacity)
        document       = try c.decode(UMGridDocument.self, forKey: .document)
        parallaxFactor = try c.decodeIfPresent(Double.self,        forKey: .parallaxFactor) ?? 1.0
        layerOffset    = try c.decodeIfPresent(UMVectorDriver.self,   forKey: .layerOffset)   ?? .zero
        // Backward compat: existing files have no opacityDriver; seed from opacity
        if let od = try c.decodeIfPresent(UMDoubleDriver.self, forKey: .opacityDriver) {
            opacityDriver = od
        } else {
            opacityDriver = UMDoubleDriver(mode: .constant, base: opacity)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,             forKey: .id)
        try c.encode(name,           forKey: .name)
        try c.encode(isVisible,      forKey: .isVisible)
        try c.encode(opacity,        forKey: .opacity)
        try c.encode(document,       forKey: .document)
        try c.encode(parallaxFactor, forKey: .parallaxFactor)
        try c.encode(layerOffset,    forKey: .layerOffset)
        try c.encode(opacityDriver,  forKey: .opacityDriver)
    }
}
