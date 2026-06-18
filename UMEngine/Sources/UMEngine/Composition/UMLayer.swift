import Foundation

/// One sprite layer in a composition. Each layer owns an independent grid document
/// (its own rows/cols, cells, styles, paths, shapes) and renders into the shared canvas
/// area at a given opacity. Layers are composited bottom-to-top.
public struct UMLayer: Codable, Identifiable, Sendable {
    public var id:        UUID
    public var name:      String
    public var isVisible: Bool
    public var opacity:   Double      // 0–1; 1 = fully opaque
    public var document:  UMGridDocument

    public init(
        id:        UUID            = UUID(),
        name:      String          = "Layer",
        isVisible: Bool            = true,
        opacity:   Double          = 1.0,
        document:  UMGridDocument  = UMGridDocument.makeDefault()
    ) {
        self.id        = id
        self.name      = name
        self.isVisible = isVisible
        self.opacity   = opacity
        self.document  = document
    }
}
