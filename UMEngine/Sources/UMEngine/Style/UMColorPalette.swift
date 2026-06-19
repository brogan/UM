import Foundation

public struct UMColorPalette: Codable, Identifiable, Sendable {
    public var id:                UUID
    public var name:              String
    public var colors:            [UMColor]
    public var sourceDescription: String   // e.g. "backdrop.jpg 8×8"

    public init(name: String, colors: [UMColor], sourceDescription: String = "") {
        self.id                = UUID()
        self.name              = name
        self.colors            = colors
        self.sourceDescription = sourceDescription
    }
}
