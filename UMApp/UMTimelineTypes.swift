import SwiftUI
import UMEngine

// MARK: - UMTimelineLane

/// Driver lanes exposed per layer in the keyframe timeline.
enum UMTimelineLane: Int, CaseIterable, Hashable {
    case opacity = 0
    case offset  = 1

    var label: String {
        switch self {
        case .opacity: return "Opacity"
        case .offset:  return "Offset"
        }
    }

    var color: Color {
        switch self {
        case .opacity: return .pink
        case .offset:  return .blue
        }
    }

    @MainActor
    func keyframeFrames(from layer: UMLayerState) -> [Int] {
        switch self {
        case .opacity: return layer.opacityDriver.keyframes.map(\.frame)
        case .offset:  return layer.layerOffset.keyframes.map(\.frame)
        }
    }
}

// MARK: - UMCameraLane

/// Driver lanes exposed for the project camera in the keyframe timeline.
enum UMCameraLane: Int, CaseIterable, Hashable {
    case pan      = 0
    case zoom     = 1
    case rotation = 2

    var label: String {
        switch self {
        case .pan:      return "Pan"
        case .zoom:     return "Zoom"
        case .rotation: return "Rotation"
        }
    }

    var color: Color {
        switch self {
        case .pan:      return .teal
        case .zoom:     return .green
        case .rotation: return .cyan
        }
    }

    func keyframeFrames(from camera: UMCamera) -> [Int] {
        switch self {
        case .pan:      return camera.pan.keyframes.map(\.frame)
        case .zoom:     return camera.zoom.keyframes.map(\.frame)
        case .rotation: return camera.rotation.keyframes.map(\.frame)
        }
    }
}

// MARK: - Selection types

struct UMTimelineKFSelection: Equatable {
    var layerIndex:  Int
    var lane:        UMTimelineLane
    var keyframeIdx: Int
}

struct UMCameraKFSelection: Equatable, Hashable {
    var lane:        UMCameraLane
    var keyframeIdx: Int
}
