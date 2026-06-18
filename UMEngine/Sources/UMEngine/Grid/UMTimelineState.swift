import Foundation

/// A snapshot of the complete grid state at a moment in time,
/// plus how long (in frames) this state should hold before the next one plays.
public struct UMTimelineState: Codable, Identifiable, Sendable {
    public var id: UUID
    public var gridConfig: UMGridConfig
    public var cells: [UMGridCell]
    public var styles: [CellStyle]
    public var holdFrames: Int

    public init(gridConfig: UMGridConfig, cells: [UMGridCell], styles: [CellStyle], holdFrames: Int = 48) {
        self.id = UUID()
        self.gridConfig = gridConfig
        self.cells = cells
        self.styles = styles
        self.holdFrames = holdFrames
    }
}
