import Foundation

/// A collection of reusable styles and motion paths.
/// Used for both the global app library (persisted in Application Support)
/// and as the container type when serialising library data.
public struct UMLibrary: Codable, Sendable {
    public var styles: [CellStyle]
    public var paths:  [UMMotionPath]

    public static let empty = UMLibrary()

    public init(styles: [CellStyle] = [], paths: [UMMotionPath] = []) {
        self.styles = styles
        self.paths  = paths
    }
}
