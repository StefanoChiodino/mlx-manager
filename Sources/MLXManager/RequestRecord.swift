import Foundation

/// Data captured for a single completed inference request.
public struct RequestRecord: Equatable {
    public let startedAt: Date
    public let completedAt: Date
    public let tokens: Int
    public let prefillTPS: Double?

    public var duration: TimeInterval { completedAt.timeIntervalSince(startedAt) }

    public init(startedAt: Date, completedAt: Date, tokens: Int, prefillTPS: Double? = nil) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.tokens = tokens
        self.prefillTPS = prefillTPS
    }
}
