import Foundation

/// A collection of reusable palette items.
/// Used for both the global app library (persisted in Application Support)
/// and as the container type when serialising library data.
public struct UMLibrary: Codable, Sendable {
    public var styles:     [CellStyle]
    public var paths:      [UMMotionPath]
    public var motionSets: [UMMotionSet]

    public static let empty = UMLibrary()

    public init(styles: [CellStyle] = [], paths: [UMMotionPath] = [], motionSets: [UMMotionSet] = []) {
        self.styles     = styles
        self.paths      = paths
        self.motionSets = motionSets
    }

    private enum CodingKeys: String, CodingKey { case styles, paths, motionSets }

    public init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        styles      = (try? c.decodeIfPresent([CellStyle].self,    forKey: .styles))     ?? []
        paths       = (try? c.decodeIfPresent([UMMotionPath].self, forKey: .paths))      ?? []
        motionSets  = (try? c.decodeIfPresent([UMMotionSet].self,  forKey: .motionSets)) ?? []
    }
}
