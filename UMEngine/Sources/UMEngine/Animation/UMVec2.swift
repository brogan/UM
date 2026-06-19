import Foundation

public struct UMVec2: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = UMVec2(x: 0, y: 0)
    public static let one  = UMVec2(x: 1, y: 1)

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public static func lerp(_ a: UMVec2, _ b: UMVec2, t: Double) -> UMVec2 {
        UMVec2(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    public static func + (lhs: UMVec2, rhs: UMVec2) -> UMVec2 { UMVec2(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    public static func - (lhs: UMVec2, rhs: UMVec2) -> UMVec2 { UMVec2(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public static func * (lhs: UMVec2, rhs: Double)  -> UMVec2 { UMVec2(x: lhs.x * rhs, y: lhs.y * rhs) }
}
