import Foundation

/// A simple RGBA colour stored as normalised doubles (0–1).
/// Kept in UMEngine with no SwiftUI or AppKit dependency; conversion
/// to platform colour types happens at the app layer.
public struct UMColor: Codable, Equatable, Sendable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let black   = UMColor(r: 0,    g: 0,    b: 0)
    public static let white   = UMColor(r: 1,    g: 1,    b: 1)
    public static let clear   = UMColor(r: 0,    g: 0,    b: 0,    a: 0)
    public static let defaultFill   = UMColor(r: 0.25, g: 0.47, b: 0.88, a: 0.85)
    public static let defaultStroke = UMColor(r: 0,    g: 0,    b: 0,    a: 1)

    /// RGB-inverted colour; alpha is preserved.
    public var inverted: UMColor { UMColor(r: 1-r, g: 1-g, b: 1-b, a: a) }

    /// Return a copy with a different alpha.
    public func withAlpha(_ alpha: Double) -> UMColor { UMColor(r: r, g: g, b: b, a: alpha) }

    /// Return a copy with the hue rotated by `degrees` (HSL space). Achromatic colours are unchanged.
    public func rotatingHue(by degrees: Double) -> UMColor {
        let maxC = Swift.max(r, g, b)
        let minC = Swift.min(r, g, b)
        let l    = (maxC + minC) / 2.0
        guard maxC != minC else { return self }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC)
        var h: Double
        switch maxC {
        case r:  h = (g - b) / d + (g < b ? 6 : 0)
        case g:  h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h /= 6.0
        let raw  = h + degrees / 360.0
        let newH = ((raw.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
        let q    = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p    = 2 * l - q
        func hf(_ t: Double) -> Double {
            let t = ((t.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }
        return UMColor(r: hf(newH + 1/3), g: hf(newH), b: hf(newH - 1/3), a: a)
    }
}

public enum UMRenderMode: String, Codable, CaseIterable, Sendable {
    case filled        = "filled"
    case stroked       = "stroked"
    case filledStroked = "filledStroked"

    public var displayName: String {
        switch self {
        case .filled:        return "Filled"
        case .stroked:       return "Stroked"
        case .filledStroked: return "Fill & Stroke"
        }
    }
}
