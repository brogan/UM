import Foundation

/// Per-layer geometric distortion applied to the grid before rendering.
/// Only affects rendered cell positions/sizes; the underlying cell data is unchanged.
public enum UMGridDistortion: Sendable, Equatable {

    /// No distortion — uniform grid.
    case none

    /// Perspective taper: row heights and column widths vary exponentially from one edge to the
    /// other. `vertical` ∈ [-1, 1]: positive compresses top rows, expands bottom (floor receding).
    /// `horizontal` ∈ [-1, 1]: positive compresses left columns, expands right.
    /// `convergence` ∈ [0, 1]: links each row's horizontal span to its vertical scale factor so
    /// compressed rows are also narrower. An auto-zoom is applied so the most-foreshortened row
    /// still fills the full canvas width; wider rows overflow and are clipped.
    case perspective(vertical: Double, horizontal: Double, convergence: Double)

    /// Radial size modulation. `amount` ∈ [-1, 1]:
    ///   > 0 → centre cells drawn larger, corner cells normal (spherical/barrel look).
    ///   < 0 → centre cells drawn smaller, corner cells normal (cone look).
    /// Cell centres remain at their uniform positions; only drawn size changes.
    case barrel(amount: Double)

    /// Per-cell stable random position jitter. `amount` ∈ [0, 1] in cell-fraction units.
    /// `seed` selects the hash stream so different layers can have independent noise.
    case fractured(amount: Double, seed: UInt64)

    // MARK: - Cell geometry

    public struct Cell {
        public var cx, cy, cellW, cellH: Double
    }

    /// Returns the distorted centre (cx, cy) and effective drawn size (cellW, cellH) for a cell.
    /// Scroll offset (fracX, fracY) is applied by the caller as an additive delta to cx/cy.
    public func evaluate(
        row: Int, col: Int,
        rows: Int, cols: Int,
        uniformCellW: Double, uniformCellH: Double,
        gridW: Double, gridH: Double
    ) -> Cell {
        let baseCx = (Double(col) + 0.5) * uniformCellW
        let baseCy = (Double(row) + 0.5) * uniformCellH
        switch self {
        case .none:
            return Cell(cx: baseCx, cy: baseCy, cellW: uniformCellW, cellH: uniformCellH)

        case .perspective(let vStr, let hStr, let convergence):
            let rh = Self.perspectiveSizes(count: rows, total: gridH, strength: vStr)
            let cw = Self.perspectiveSizes(count: cols, total: gridW, strength: hStr)
            let cy = rh[0..<row].reduce(0, +) + rh[row] / 2

            if convergence > 1e-6, abs(vStr) > 1e-6 {
                let (bandLeft, bandWidth) = Self.convergenceBand(
                    forRow: row, rowHeights: rh, gridW: gridW, convergence: convergence)
                let colFrac = (Double(col) + 0.5) / Double(cols)
                return Cell(cx: bandLeft + colFrac * bandWidth,
                            cy: cy,
                            cellW: bandWidth / Double(cols),
                            cellH: rh[row])
            }

            let cx = cw[0..<col].reduce(0, +) + cw[col] / 2
            return Cell(cx: cx, cy: cy, cellW: cw[col], cellH: rh[row])

        case .barrel(let amount):
            let u  = (Double(col) + 0.5) / Double(cols)  * 2 - 1   // ∈ (-1, 1)
            let v  = (Double(row) + 0.5) / Double(rows)  * 2 - 1
            let r2 = (u * u + v * v) / 2.0                          // 0 at centre, 1 at corners
            let s  = max(0.05, 1.0 + amount * (1.0 - r2))
            return Cell(cx: baseCx, cy: baseCy, cellW: uniformCellW * s, cellH: uniformCellH * s)

        case .fractured(let amount, let seed):
            let dx = Self.stableHash(row, col, seed, 0) * amount * uniformCellW
            let dy = Self.stableHash(row, col, seed, 1) * amount * uniformCellH
            return Cell(cx: baseCx + dx, cy: baseCy + dy,
                        cellW: uniformCellW, cellH: uniformCellH)
        }
    }

    // MARK: - Perspective helpers (public for grid-line drawing)

    /// Returns an array of `count` sizes that sum to `total`, tapering exponentially by `strength`.
    /// Positive strength → early elements smaller, later elements larger.
    public static func perspectiveSizes(count: Int, total: Double, strength: Double) -> [Double] {
        guard count > 0 else { return [] }
        guard count > 1, abs(strength) > 1e-6 else {
            return Array(repeating: total / Double(count), count: count)
        }
        let weights = (0..<count).map { i -> Double in
            let t = Double(i) / Double(count - 1)   // 0…1
            return exp(strength * (2 * t - 1))       // exp(-s) … exp(+s)
        }
        let sum = weights.reduce(0, +)
        return weights.map { $0 / sum * total }
    }

    /// Returns (bandLeft, bandWidth) for the converged horizontal band of a specific row.
    /// The most-foreshortened row's band spans exactly `gridW`; others overflow the canvas.
    /// Pass the full `rowHeights` array (from `perspectiveSizes`) to avoid recomputation.
    public static func convergenceBand(
        forRow row: Int,
        rowHeights: [Double],
        gridW: Double,
        convergence: Double
    ) -> (left: Double, width: Double) {
        let rows = rowHeights.count
        guard rows > 0 else { return (0, gridW) }
        let uniformH = rowHeights.reduce(0, +) / Double(rows)
        let autoZoom = Self.convergenceAutoZoom(rowHeights: rowHeights, convergence: convergence)
        let rowScale = rowHeights[min(row, rows - 1)] / uniformH
        let eff = 1.0 - convergence * (1.0 - rowScale)
        let width = gridW * eff * autoZoom
        return (left: (gridW - width) / 2, width: width)
    }

    /// Auto-zoom factor that brings the most-compressed row's band to exactly `gridW`.
    public static func convergenceAutoZoom(rowHeights: [Double], convergence: Double) -> Double {
        guard !rowHeights.isEmpty else { return 1.0 }
        let uniformH = rowHeights.reduce(0, +) / Double(rowHeights.count)
        let minEff = rowHeights.map { h -> Double in
            let s = h / uniformH
            return 1.0 - convergence * (1.0 - s)
        }.min() ?? 1.0
        return minEff > 1e-8 ? 1.0 / minEff : 1.0
    }

    // MARK: - Stable hash

    private static func stableHash(_ row: Int, _ col: Int, _ seed: UInt64, _ ch: Int) -> Double {
        var h = UInt64(bitPattern: Int64(row &* 2_654_435_761 &+ col &* 2_246_822_519 &+ ch &* 374_761_393))
        h = h &+ seed
        h ^= h >> 33;  h = h &* 0xff51afd7ed558ccd
        h ^= h >> 33;  h = h &* 0xc4ceb9fe1a85ec53
        h ^= h >> 33
        return Double(h) / Double(UInt64.max) - 0.5   // ∈ (-0.5, 0.5)
    }
}

// MARK: - Codable

extension UMGridDistortion: Codable {
    private enum K: String, CodingKey { case type, vertical, horizontal, convergence, amount, seed }

    public init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: K.self)
        let type = (try? c.decode(String.self, forKey: .type)) ?? "none"
        switch type {
        case "perspective":
            self = .perspective(
                vertical:    (try? c.decodeIfPresent(Double.self, forKey: .vertical))    ?? 0,
                horizontal:  (try? c.decodeIfPresent(Double.self, forKey: .horizontal))  ?? 0,
                convergence: (try? c.decodeIfPresent(Double.self, forKey: .convergence)) ?? 0)
        case "barrel":
            self = .barrel(amount: (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0)
        case "fractured":
            self = .fractured(
                amount: (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0.3,
                seed:   (try? c.decodeIfPresent(UInt64.self, forKey: .seed))   ?? 42)
        default:
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .none:
            try c.encode("none", forKey: .type)
        case .perspective(let v, let h, let conv):
            try c.encode("perspective", forKey: .type)
            try c.encode(v, forKey: .vertical)
            try c.encode(h, forKey: .horizontal)
            if conv != 0 { try c.encode(conv, forKey: .convergence) }
        case .barrel(let a):
            try c.encode("barrel", forKey: .type)
            try c.encode(a, forKey: .amount)
        case .fractured(let a, let s):
            try c.encode("fractured", forKey: .type)
            try c.encode(a, forKey: .amount)
            try c.encode(s, forKey: .seed)
        }
    }
}
