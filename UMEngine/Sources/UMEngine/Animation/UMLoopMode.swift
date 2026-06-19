import Foundation

public enum UMLoopMode: String, Codable, CaseIterable, Sendable {
    case loop
    case once
    case pingPong

    public var displayName: String {
        switch self {
        case .loop:     return "Loop"
        case .once:     return "Once"
        case .pingPong: return "Ping-Pong"
        }
    }
}
