import Foundation

// MARK: - UMAnimatedGeometry

/// A reusable animated sprite asset. Stores an ordered list of geometry states that
/// play back as a cycle. The asset is assigned to a UMSprite via `animatedGeometryID`;
/// when set it overrides the sprite's `shapeID` and any Motion Set SEQUENCE cycling.
///
/// Phase 1 implements hard-cut image replacement (transitionFrames == 0).
/// Phase 2 adds opacity cross-fade between states using transitionFrames + easing.
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

    // MARK: - Primary API

    /// Returns 1 or 2 render layers for the given frame.
    /// Hard-cut state: one layer at alpha = 1.0.
    /// Transition period: two layers — outgoing at (1 − progress), incoming at progress.
    /// Host apps (UM, Loom) draw each layer at its alpha using their own style lookup.
    public func resolveRenderLayers(atFrame frame: Int) -> [UMRenderLayer] {
        guard !states.isEmpty else { return [] }
        guard let f = effectiveFrame(frame) else {
            // .once / .holdLast past the end — hold the last state
            guard let last = states.last else { return [] }
            return [UMRenderLayer(shapeID: last.shapeID, styleID: last.styleID,
                                  alpha: 1.0, transform: makeTransform(last))]
        }
        let (primary, secondary, progress) = stateAtFrame(f)
        if let next = secondary, progress > 0 {
            let tween = primary.styleTween
            return [
                UMRenderLayer(shapeID: primary.shapeID, styleID: primary.styleID,
                              alpha: 1.0 - progress, transform: makeTransform(primary),
                              styleTween: tween),
                UMRenderLayer(shapeID: next.shapeID,    styleID: next.styleID,
                              alpha: progress,           transform: makeTransform(next),
                              styleTween: tween)
            ]
        }
        return [UMRenderLayer(shapeID: primary.shapeID, styleID: primary.styleID,
                              alpha: 1.0, transform: makeTransform(primary))]
    }

    // MARK: - Convenience accessors (delegate to first render layer)

    /// Primary shapeID at the given frame. During a transition returns the outgoing shape.
    public func resolveShapeID(atFrame frame: Int) -> UUID? {
        resolveRenderLayers(atFrame: frame).first?.shapeID
    }

    /// Primary styleID at the given frame. During a transition returns the outgoing style.
    public func resolveStyleID(atFrame frame: Int) -> UUID? {
        resolveRenderLayers(atFrame: frame).first?.styleID
    }

    /// Primary per-state transform at the given frame.
    public func resolveStateTransform(atFrame frame: Int) -> UMAnimatedGeometryStateTransform {
        resolveRenderLayers(atFrame: frame).first?.transform ?? .identity
    }

    // MARK: - Frame counts

    /// Total frames in one forward pass, including transition periods.
    public var totalForwardFrames: Int {
        states.reduce(0) { $0 + max(1, $1.holdFrames) + max(0, $1.transitionFrames) }
    }

    /// Full cycle length. PingPong back pass uses hold frames only (transitions forward-only).
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

    /// Maps an input frame to an effective forward-pass frame, or nil for .once/.holdLast past end.
    private func effectiveFrame(_ frame: Int) -> Int? {
        let total = totalForwardFrames
        guard total > 0 else { return nil }
        switch loopMode {
        case .loop:
            return ((frame % total) + total) % total
        case .pingPong:
            guard states.count > 1 else { return 0 }
            // Build hold-only pairs for back-pass (transitions apply forward only).
            let fwdPairs = states.map { max(1, $0.holdFrames) + max(0, $0.transitionFrames) }
            let bwdPairs = states.dropLast().map { max(1, $0.holdFrames) }.reversed()
            let back = bwdPairs.reduce(0, +)
            let cycle = total + back
            let r = ((frame % cycle) + cycle) % cycle
            if r < total { return r }
            return pingPongBack(offset: r - total, backHolds: Array(bwdPairs), fwdPairs: fwdPairs)
        case .once, .holdLast:
            return max(0, min(frame, total - 1))
        }
    }

    /// Maps a back-pass offset to a forward-pass effective frame.
    private func pingPongBack(offset: Int, backHolds: [Int], fwdPairs: [Int]) -> Int {
        var cursor = 0
        for (i, hold) in backHolds.enumerated() {
            let stateIdx = states.count - 2 - i
            if stateIdx < 0 { break }
            if offset < cursor + hold {
                // Within this back-state's hold — return its forward-pass start frame.
                let fwdStart = fwdPairs[0..<stateIdx].reduce(0, +)
                return fwdStart + (offset - cursor)
            }
            cursor += hold
        }
        return 0
    }

    /// Resolves an effective forward-pass frame to (primary state, optional secondary, eased progress).
    private func stateAtFrame(_ f: Int)
        -> (primary: UMAnimatedGeometryState, secondary: UMAnimatedGeometryState?, progress: Double) {
        var cursor = 0
        for (i, state) in states.enumerated() {
            let hold  = max(1, state.holdFrames)
            let trans = max(0, state.transitionFrames)
            if f < cursor + hold {
                return (state, nil, 0)
            }
            if trans > 0 && f < cursor + hold + trans {
                let rawT   = Double(f - (cursor + hold)) / Double(trans)
                let easedT = state.easing.apply(rawT)
                let nextIdx = (i + 1) % states.count
                return (state, states[nextIdx], easedT)
            }
            cursor += hold + trans
        }
        return (states.last!, nil, 0)
    }

    private func makeTransform(_ state: UMAnimatedGeometryState) -> UMAnimatedGeometryStateTransform {
        UMAnimatedGeometryStateTransform(
            offsetX: state.offsetX, offsetY: state.offsetY,
            rotation: state.rotation, scaleX: state.scaleX, scaleY: state.scaleY)
    }
}

// MARK: - UMRenderLayer

/// One draw layer produced by `resolveRenderLayers(atFrame:)`.
/// During a hard-cut frame: a single layer at alpha = 1.0.
/// During a cross-fade: two layers at complementary alphas.
/// Host apps look up the shape and style/rendererSet by their UUIDs.
public struct UMRenderLayer: Sendable {
    public let shapeID:    UUID
    public let styleID:    UUID?
    public let alpha:      Double   // draw opacity 0...1
    public let transform:  UMAnimatedGeometryStateTransform
    /// When true, the render site should lerp fill/stroke colors between
    /// geoLayers[0].styleID and geoLayers[1].styleID at t = geoLayers[1].alpha,
    /// instead of drawing each layer at its own style.
    public let styleTween: Bool

    public init(shapeID: UUID, styleID: UUID?, alpha: Double,
                transform: UMAnimatedGeometryStateTransform,
                styleTween: Bool = false) {
        self.shapeID    = shapeID
        self.styleID    = styleID
        self.alpha      = alpha
        self.transform  = transform
        self.styleTween = styleTween
    }
}

// MARK: - UMAnimatedGeometryState

/// One frame-state in an animated geometry cycle.
public struct UMAnimatedGeometryState: Codable, Identifiable, Sendable {
    public var id:                UUID
    public var shapeID:           UUID            // shape from project shape library
    public var styleID:           UUID?           // nil = inherit sprite's style
    public var holdFrames:        Int             // frames this state is fully shown
    public var transitionFrames:  Int             // frames to cross-fade into the next state (0 = hard cut)
    public var easing:            PathEasing      // easing applied during transitionFrames
    /// When true and Trans > 0, render sites lerp fill/stroke between the FROM and TO styles
    /// instead of drawing each layer at its own style colour.
    public var styleTween:        Bool            // false = hard style cut; true = colour interpolation
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
        styleTween:       Bool       = false,
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
        self.styleTween       = styleTween
        self.offsetX          = offsetX
        self.offsetY          = offsetY
        self.rotation         = rotation
        self.scaleX           = scaleX
        self.scaleY           = scaleY
    }

    private enum CodingKeys: String, CodingKey {
        case id, shapeID, styleID, holdFrames, transitionFrames, easing, styleTween
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
        styleTween        = (try? c.decodeIfPresent(Bool.self,      forKey: .styleTween))        ?? false
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
        if styleTween                { try c.encode(styleTween,       forKey: .styleTween) }
        if offsetX   != 0 { try c.encode(offsetX,  forKey: .offsetX) }
        if offsetY   != 0 { try c.encode(offsetY,  forKey: .offsetY) }
        if rotation  != 0 { try c.encode(rotation, forKey: .rotation) }
        if scaleX    != 1 { try c.encode(scaleX,   forKey: .scaleX) }
        if scaleY    != 1 { try c.encode(scaleY,   forKey: .scaleY) }
    }
}

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
