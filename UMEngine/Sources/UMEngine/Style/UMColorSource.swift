import Foundation

public struct UMColorSource: Codable, Sendable, Equatable {
    public var filePath:           String           // absolute path to image or video file
    public var applyTo:            ColorApplyTarget
    public var preserveStyleAlpha: Bool             // use style alpha; ignore sampled alpha
    public var videoLoopMode:      VideoLoopMode

    public var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }

    public init(
        filePath: String,
        applyTo: ColorApplyTarget = .fill,
        preserveStyleAlpha: Bool = true,
        videoLoopMode: VideoLoopMode = .loop
    ) {
        self.filePath           = filePath
        self.applyTo            = applyTo
        self.preserveStyleAlpha = preserveStyleAlpha
        self.videoLoopMode      = videoLoopMode
    }
}

public enum ColorApplyTarget: String, Codable, Sendable, CaseIterable {
    case fill, stroke, fillAndStroke

    public var displayName: String {
        switch self {
        case .fill:          return "Fill"
        case .stroke:        return "Stroke"
        case .fillAndStroke: return "Both"
        }
    }
}

public enum VideoLoopMode: String, Codable, Sendable, CaseIterable {
    case loop, clamp

    public var displayName: String {
        switch self {
        case .loop:  return "Loop"
        case .clamp: return "Clamp"
        }
    }
}
