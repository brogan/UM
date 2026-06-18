import Foundation

/// A named Loom geometry asset stored within a UM project or global library.
///
/// The raw JSON content of a Loom polygonSet `.json` file is preserved verbatim
/// in `geometryJSON`.  At render time `AppController` decodes this via
/// `EditableGeometryJSONLoader.decode(from:)` to obtain the runtime polygons.
public struct UMShape: Codable, Sendable, Identifiable, Equatable {
    public var id:               UUID
    public var name:             String
    public var sourceFilename:   String     // original Loom file name, for display
    public var geometryJSON:     String     // raw Loom JSON content

    public init(
        id:             UUID   = UUID(),
        name:           String,
        sourceFilename: String,
        geometryJSON:   String
    ) {
        self.id             = id
        self.name           = name
        self.sourceFilename = sourceFilename
        self.geometryJSON   = geometryJSON
    }
}
