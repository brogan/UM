import Foundation

public enum PhasePolicy: String, Codable, Sendable, CaseIterable {
    case synchronized, random, sequential, spatial, radial
}

public enum ResizeOffsetPolicy: String, Codable, Sendable, CaseIterable {
    case preserveAbsolute   // sprites stay at same screen pixels
    case scaleProportional  // offset scales with new cell size
    case reset              // offset zeroed; sprites re-centre
}

public enum ResizePhasePolicy: String, Codable, Sendable, CaseIterable {
    case inherit            // child gets parent's phaseOffset unchanged
    case inheritWithScatter // child gets parent's phaseOffset ± scatter
    case reset              // child phaseOffset = 0
}

public struct UMGridConfig: Codable, Sendable {
    public var rows:               Int
    public var cols:               Int
    public var cellWidth:          Double
    public var cellHeight:         Double
    public var canvasWidth:        Double      // output pixel dimensions
    public var canvasHeight:       Double
    public var xOffset:            Int
    public var yOffset:            Int
    public var borderWidth:        Int

    // Paint-time policies (apply to newly painted cells; don't retroactively affect existing)
    public var phasePolicy:        PhasePolicy
    public var phaseStepFrames:    Int
    public var spatialScatter:     Double      // 0.0–1.0

    // Resolution-change policies (user-settable in the resize sheet)
    public var resizeOffsetPolicy:    ResizeOffsetPolicy
    public var resizePhasePolicy:     ResizePhasePolicy
    public var resizePhaseScatter:    Double   // 0.0–1.0; used by inheritWithScatter
    public var resizePositionScatter: Double   // 0.0–1.0; random offset added to cells on resample

    public init(
        rows: Int = 8,
        cols: Int = 8,
        cellWidth: Double = 60,
        cellHeight: Double = 60,
        canvasWidth: Double = 1080,
        canvasHeight: Double = 1080,
        xOffset: Int = 0,
        yOffset: Int = 0,
        borderWidth: Int = 1,
        phasePolicy: PhasePolicy = .synchronized,
        phaseStepFrames: Int = 4,
        spatialScatter: Double = 0,
        resizeOffsetPolicy: ResizeOffsetPolicy = .preserveAbsolute,
        resizePhasePolicy: ResizePhasePolicy = .inherit,
        resizePhaseScatter: Double = 0,
        resizePositionScatter: Double = 0
    ) {
        self.rows                  = rows
        self.cols                  = cols
        self.cellWidth             = cellWidth
        self.cellHeight            = cellHeight
        self.canvasWidth           = canvasWidth
        self.canvasHeight          = canvasHeight
        self.xOffset               = xOffset
        self.yOffset               = yOffset
        self.borderWidth           = borderWidth
        self.phasePolicy           = phasePolicy
        self.phaseStepFrames       = phaseStepFrames
        self.spatialScatter        = spatialScatter
        self.resizeOffsetPolicy    = resizeOffsetPolicy
        self.resizePhasePolicy     = resizePhasePolicy
        self.resizePhaseScatter    = resizePhaseScatter
        self.resizePositionScatter = resizePositionScatter
    }

    private enum CodingKeys: String, CodingKey {
        case rows, cols, cellWidth, cellHeight, canvasWidth, canvasHeight
        case xOffset, yOffset, borderWidth
        case phasePolicy, phaseStepFrames, spatialScatter
        case resizeOffsetPolicy, resizePhasePolicy, resizePhaseScatter
        case resizePositionScatter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows         = try c.decode(Int.self,    forKey: .rows)
        cols         = try c.decode(Int.self,    forKey: .cols)
        cellWidth    = try c.decode(Double.self, forKey: .cellWidth)
        cellHeight   = try c.decode(Double.self, forKey: .cellHeight)
        canvasWidth  = try c.decode(Double.self, forKey: .canvasWidth)
        canvasHeight = try c.decode(Double.self, forKey: .canvasHeight)
        xOffset      = try c.decode(Int.self,    forKey: .xOffset)
        yOffset      = try c.decode(Int.self,    forKey: .yOffset)
        borderWidth  = try c.decode(Int.self,    forKey: .borderWidth)
        phasePolicy        = (try? c.decodeIfPresent(PhasePolicy.self,        forKey: .phasePolicy))        ?? .synchronized
        phaseStepFrames    = (try? c.decodeIfPresent(Int.self,                forKey: .phaseStepFrames))    ?? 4
        spatialScatter     = (try? c.decodeIfPresent(Double.self,             forKey: .spatialScatter))     ?? 0
        resizeOffsetPolicy = (try? c.decodeIfPresent(ResizeOffsetPolicy.self, forKey: .resizeOffsetPolicy)) ?? .preserveAbsolute
        resizePhasePolicy  = (try? c.decodeIfPresent(ResizePhasePolicy.self,  forKey: .resizePhasePolicy))  ?? .inherit
        resizePhaseScatter = (try? c.decodeIfPresent(Double.self,             forKey: .resizePhaseScatter)) ?? 0
        resizePositionScatter = (try? c.decodeIfPresent(Double.self,          forKey: .resizePositionScatter)) ?? 0
    }
}
