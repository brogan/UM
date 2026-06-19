import Foundation

public struct UMColorSource: Codable, Sendable, Equatable {
    public var filePath:           String    // absolute path, resolved at load time; legacy fallback
    public var relativeFilePath:   String?   // filename within project's colorSources/ dir (preferred)
    public var applyTo:            ColorApplyTarget
    public var preserveStyleAlpha: Bool
    public var videoLoopMode:      VideoLoopMode

    public var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }

    public init(
        filePath: String,
        relativeFilePath: String? = nil,
        applyTo: ColorApplyTarget = .fill,
        preserveStyleAlpha: Bool = true,
        videoLoopMode: VideoLoopMode = .loop
    ) {
        self.filePath           = filePath
        self.relativeFilePath   = relativeFilePath
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
