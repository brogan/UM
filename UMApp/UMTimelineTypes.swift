import SwiftUI
import UMEngine

// MARK: - UMTimelineLane

/// Driver lanes exposed per layer in the keyframe timeline.
enum UMTimelineLane: Int, CaseIterable, Hashable {
    case opacity    = 0
    case offset     = 1
    case gridScroll = 2

    var label: String {
        switch self {
        case .opacity:    return "Opacity"
        case .offset:     return "Offset"
        case .gridScroll: return "Scroll"
        }
    }

    var color: Color {
        switch self {
        case .opacity:    return .pink
        case .offset:     return .blue
        case .gridScroll: return .orange
        }
    }

    @MainActor
    func keyframeFrames(from layer: UMLayerState) -> [Int] {
        switch self {
        case .opacity:    return layer.opacityDriver.keyframes.map(\.frame)
        case .offset:     return layer.layerOffset.keyframes.map(\.frame)
        case .gridScroll: return layer.gridScrollDriver.keyframes.map(\.frame)
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

// MARK: - Safe subscript (shared across timeline files)

extension Array {
    subscript(safe index: Int) -> Element? {
        get { indices.contains(index) ? self[index] : nil }
        set {
            guard let v = newValue, indices.contains(index) else { return }
            self[index] = v
        }
    }
}

// MARK: - Named markers

struct UMTimelineMarker: Codable, Identifiable {
    var id:    UUID
    var frame: Int
    var name:  String
    init(frame: Int, name: String) { self.id = UUID(); self.frame = frame; self.name = name }
}

// MARK: - KF clipboard (in-memory only)

struct UMKFClipboard {
    enum Item {
        case layerOpacity(   layerIndex: Int, frameOffset: Int, value: Double, easing: PathEasing)
        case layerOffset(    layerIndex: Int, frameOffset: Int, value: UMVec2, easing: PathEasing)
        case layerGridScroll(layerIndex: Int, frameOffset: Int, value: UMVec2, easing: PathEasing)
        case cameraPan(      frameOffset: Int, value: UMVec2,  easing: PathEasing)
        case cameraZoom(     frameOffset: Int, value: Double,  easing: PathEasing)
        case cameraRotation( frameOffset: Int, value: Double,  easing: PathEasing)
    }
    var items:       [Item]
    var anchorFrame: Int
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
