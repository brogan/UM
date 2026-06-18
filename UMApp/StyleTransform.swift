import Foundation
import UMEngine

/// One-shot operations that derive a new `CellStyle` from an existing one.
/// Each transform produces a renamed copy with a new UUID; the source is unchanged.
enum StyleTransform: CaseIterable {
    case inverted
    case faint
    case strong
    case swapColors
    case outlineOnly
    case filledOnly

    var label: String {
        switch self {
        case .inverted:    return "Inverted"
        case .faint:       return "Faint"
        case .strong:      return "Strong"
        case .swapColors:  return "Swap Colors"
        case .outlineOnly: return "Outline Only"
        case .filledOnly:  return "Filled Only"
        }
    }
}

extension CellStyle {
    /// Return a new style derived by applying `transform`.  The new style gets a
    /// fresh UUID and a name of the form "Original (Transform)".
    func applying(_ transform: StyleTransform) -> CellStyle {
        var copy      = self
        copy.id       = UUID()
        copy.name     = "\(name) (\(transform.label))"

        switch transform {
        case .inverted:
            copy.fillColor   = fillColor.inverted
            copy.strokeColor = strokeColor.inverted

        case .faint:
            // Fixed low alphas — predictable regardless of source alpha.
            copy.fillColor   = fillColor.withAlpha(0.15)
            copy.strokeColor = strokeColor.withAlpha(0.25)

        case .strong:
            copy.fillColor   = fillColor.withAlpha(1)
            copy.strokeColor = strokeColor.withAlpha(1)

        case .swapColors:
            copy.fillColor   = strokeColor
            copy.strokeColor = fillColor

        case .outlineOnly:
            copy.renderMode  = .stroked
            copy.fillColor   = fillColor.withAlpha(0)

        case .filledOnly:
            copy.renderMode  = .filled
            copy.strokeColor = strokeColor.withAlpha(0)
        }

        return copy
    }
}
