import Foundation

// MARK: - UMAnimatedGeometry

/// A reusable animated sprite asset. Stores an ordered list of geometry states that
/// play back as a cycle. The asset is assigned to a UMSprite via `animatedGeometryID`;
/// when set it overrides the sprite's `shapeID` and any Motion Set SEQUENCE cycling.
///
/// Phase 1 implements hard-cut image replacement (transitionFrames == 0).
/// transitionFrames and easing fields are stored for future morph support (Phase 2).
public struct UMAnimatedGeometry: Codable, Identifiable, Sendable {
    public var id:        UUID
    public var name:      String
    public var states:    [UMAnimatedGeometryState]
    public var loopMode:  UMAnimatedGeometryLoopMode

    public init(
        id:       UUID                        = UUID(),
        name:     String,
        states:   [UMAnimatedGeometryState]   = [],
        loopMode: UMAnimatedGeometryLoopMode  = .loop
    ) {
        self.id       = id
        self.name     = name
        self.states   = states
        self.loopMode = loopMode
    }

    // MARK: - Frame resolution (Phase 1: hard-cut only)

    /// Returns the per-state transform for the active state at the given frame.
    public func resolveStateTransform(atFrame frame: Int) -> UMAnimatedGeometryStateTransform {
        guard !states.isEmpty else { return .identity }
        let s = effectiveFrame(frame).flatMap { state(atEffectiveFrame: $0) } ?? states.last
        guard let s else { return .identity }
        return UMAnimatedGeometryStateTransform(
            offsetX: s.offsetX, offsetY: s.offsetY,
            rotation: s.rotation,
            scaleX: s.scaleX, scaleY: s.scaleY)
    }

    /// Returns the shapeID that should be displayed at the given animation frame.
    /// Phase 1 ignores `transitionFrames` — all cuts are hard.
    public func resolveShapeID(atFrame frame: Int) -> UUID? {
        guard !states.isEmpty else { return nil }
        guard let f = effectiveFrame(frame) else { return states.last?.shapeID }
        return state(atEffectiveFrame: f)?.shapeID
    }

    /// Returns the styleID override at the given frame, or nil if the state carries none.
    public func resolveStyleID(atFrame frame: Int) -> UUID? {
        guard !states.isEmpty else { return nil }
        guard let f = effectiveFrame(frame) else { return states.last?.styleID }
        return state(atEffectiveFrame: f)?.styleID
    }

    /// Returns the total frame count of one forward pass through all states.
    public var totalForwardFrames: Int {
        states.reduce(0) { $0 + max(1, $1.holdFrames) }
    }

    /// Returns the full cycle length including the reverse pass for pingPong.
    public var totalCycleFrames: Int {
        let fwd = totalForwardFrames
        guard fwd > 0 else { return 1 }
        switch loopMode {
        case .loop, .once, .holdLast:
            return fwd
        case .pingPong:
            guard states.count > 1 else { return fwd }
            let back = states.dropLast().reduce(0) { $0 + max(1, $1.holdFrames) }
            return fwd + back
        }
    }

    // MARK: - Private helpers

    private func effectiveFrame(_ frame: Int) -> Int? {
        let total = totalForwardFrames
        guard total > 0 else { return nil }
        switch loopMode {
        case .loop:
            return ((frame % total) + total) % total
        case .pingPong:
            guard states.count > 1 else { return 0 }
            let fwdPairs = states.map { max(1, $0.holdFrames) }
            let bwdPairs = fwdPairs.dropLast().reversed()
            let back = bwdPairs.reduce(0, +)
            let cycle = total + back
            let r = ((frame % cycle) + cycle) % cycle
            if r < total { return r }
            return pingPongBack(offset: r - total, backHolds: Array(bwdPairs))
        case .once, .holdLast:
            return max(0, min(frame, total - 1))
        }
    }

    private func pingPongBack(offset: Int, backHolds: [Int]) -> Int {
        // Map an offset into the reverse pass back to a forward-pass frame index
        var cursor = 0
        var fwdCursor = totalForwardFrames - max(1, states.last!.holdFrames)
        let fwdHolds = states.map { max(1, $0.holdFrames) }
        for (i, hold) in backHolds.enumerated() {
            let stateIdx = states.count - 2 - i
            if stateIdx < 0 { break }
            if offset < cursor + hold {
                // Within this back-state — map to forward frame
                let progress = offset - cursor
                let start = fwdHolds[0..<stateIdx].reduce(0, +)
                return start + progress
            }
            cursor += hold
            fwdCursor -= (stateIdx > 0 ? max(1, states[stateIdx - 1].holdFrames) : 0)
        }
        return 0
    }

    private func state(atEffectiveFrame f: Int) -> UMAnimatedGeometryState? {
        var cursor = 0
        for state in states {
            cursor += max(1, state.holdFrames)
            if f < cursor { return state }
        }
        return states.last
    }
}

// MARK: - UMAnimatedGeometryState

/// One frame-state in an animated geometry cycle.
public struct UMAnimatedGeometryState: Codable, Identifiable, Sendable {
    public var id:                UUID
    public var shapeID:           UUID            // shape from project shape library
    public var styleID:           UUID?           // nil = inherit sprite's style
    public var holdFrames:        Int             // frames this state is fully on
    public var transitionFrames:  Int             // Phase 2: blend frames into next state (0 = hard cut)
    public var easing:            PathEasing      // Phase 2: easing during transitionFrames
    public var offsetX:           Double          // per-state registration offset (canvas px)
    public var offsetY:           Double
    public var rotation:          Double          // per-state rotation offset (degrees)
    public var scaleX:            Double
    public var scaleY:            Double

    public init(
        id:               UUID       = UUID(),
        shapeID:          UUID,
        styleID:          UUID?      = nil,
        holdFrames:       Int        = 2,
        transitionFrames: Int        = 0,
        easing:           PathEasing = .easeInOut,
        offsetX:          Double     = 0,
        offsetY:          Double     = 0,
        rotation:         Double     = 0,
        scaleX:           Double     = 1,
        scaleY:           Double     = 1
    ) {
        self.id               = id
        self.shapeID          = shapeID
        self.styleID          = styleID
        self.holdFrames       = holdFrames
        self.transitionFrames = transitionFrames
        self.easing           = easing
        self.offsetX          = offsetX
        self.offsetY          = offsetY
        self.rotation         = rotation
        self.scaleX           = scaleX
        self.scaleY           = scaleY
    }

    private enum CodingKeys: String, CodingKey {
        case id, shapeID, styleID, holdFrames, transitionFrames, easing
        case offsetX, offsetY, rotation, scaleX, scaleY
    }

    public init(from decoder: Decoder) throws {
        let c             = try decoder.container(keyedBy: CodingKeys.self)
        id                = try  c.decode(UUID.self,    forKey: .id)
        shapeID           = try  c.decode(UUID.self,    forKey: .shapeID)
        styleID           = try? c.decodeIfPresent(UUID.self,       forKey: .styleID)
        holdFrames        = (try? c.decodeIfPresent(Int.self,       forKey: .holdFrames))        ?? 2
        transitionFrames  = (try? c.decodeIfPresent(Int.self,       forKey: .transitionFrames))  ?? 0
        easing            = (try? c.decodeIfPresent(PathEasing.self, forKey: .easing))           ?? .easeInOut
        offsetX           = (try? c.decodeIfPresent(Double.self,    forKey: .offsetX))           ?? 0
        offsetY           = (try? c.decodeIfPresent(Double.self,    forKey: .offsetY))           ?? 0
        rotation          = (try? c.decodeIfPresent(Double.self,    forKey: .rotation))          ?? 0
        scaleX            = (try? c.decodeIfPresent(Double.self,    forKey: .scaleX))            ?? 1
        scaleY            = (try? c.decodeIfPresent(Double.self,    forKey: .scaleY))            ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,      forKey: .id)
        try c.encode(shapeID, forKey: .shapeID)
        if let v = styleID           { try c.encode(v,    forKey: .styleID) }
        try c.encode(holdFrames,     forKey: .holdFrames)
        if transitionFrames != 0     { try c.encode(transitionFrames, forKey: .transitionFrames) }
        if easing != .easeInOut      { try c.encode(easing,           forKey: .easing) }
        if offsetX   != 0 { try c.encode(offsetX,  forKey: .offsetX) }
        if offsetY   != 0 { try c.encode(offsetY,  forKey: .offsetY) }
        if rotation  != 0 { try c.encode(rotation, forKey: .rotation) }
        if scaleX    != 1 { try c.encode(scaleX,   forKey: .scaleX) }
        if scaleY    != 1 { try c.encode(scaleY,   forKey: .scaleY) }
    }
}

// MARK: - UMAnimatedGeometryLoopMode

// MARK: - UMAnimatedGeometryStateTransform

/// The resolved per-state transform offsets for a sprite at a given frame.
public struct UMAnimatedGeometryStateTransform: Sendable {
    public var offsetX:  Double
    public var offsetY:  Double
    public var rotation: Double
    public var scaleX:   Double
    public var scaleY:   Double

    public static let identity = UMAnimatedGeometryStateTransform(
        offsetX: 0, offsetY: 0, rotation: 0, scaleX: 1, scaleY: 1)
}

// MARK: - UMAnimatedGeometryLoopMode

public enum UMAnimatedGeometryLoopMode: String, Codable, CaseIterable, Sendable {
    case loop
    case pingPong
    case once
    case holdLast

    public var displayName: String {
        switch self {
        case .loop:     return "Loop"
        case .pingPong: return "Ping-Pong"
        case .once:     return "Once"
        case .holdLast: return "Hold Last"
        }
    }
}
