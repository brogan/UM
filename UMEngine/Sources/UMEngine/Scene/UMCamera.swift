import Foundation

/// Scene-level camera. Evaluated statelessly per frame via DriverEvaluator.
/// pan   = world-space offset in canvas pixels (positive x = right, positive y = down)
/// zoom  = scale factor (1.0 = no zoom, 2.0 = 2× in, 0.5 = 2× out)
/// rotation = degrees clockwise
public struct UMCamera: Codable, Sendable, Equatable {
    public var pan:      UMVectorDriver
    public var zoom:     UMDoubleDriver
    public var rotation: UMDoubleDriver

    public init(
        pan:      UMVectorDriver = .zero,
        zoom:     UMDoubleDriver = .one,
        rotation: UMDoubleDriver = .zero
    ) {
        self.pan      = pan
        self.zoom     = zoom
        self.rotation = rotation
    }

    /// Identity camera — no pan, no zoom, no rotation.
    public static let identity = UMCamera(
        pan:      UMVectorDriver(mode: .constant, base: .zero),
        zoom:     UMDoubleDriver(mode: .constant, base: 1.0),
        rotation: UMDoubleDriver(mode: .constant, base: 0.0)
    )
}

/// Resolved camera values for a single frame.
public struct UMCameraFrame: Sendable {
    public let pan:      UMVec2
    public let zoom:     Double
    public let rotation: Double   // degrees clockwise

    public static let identity = UMCameraFrame(pan: .zero, zoom: 1.0, rotation: 0.0)

    public init(pan: UMVec2, zoom: Double, rotation: Double) {
        self.pan = pan; self.zoom = zoom; self.rotation = rotation
    }
}

extension UMCamera {
    public func evaluate(frame: Int, fps: Double = 24) -> UMCameraFrame {
        UMCameraFrame(
            pan:      DriverEvaluator.evaluate(pan,      frame: frame, fps: fps),
            zoom:     DriverEvaluator.evaluate(zoom,     frame: frame, fps: fps),
            rotation: DriverEvaluator.evaluate(rotation, frame: frame, fps: fps)
        )
    }
}
