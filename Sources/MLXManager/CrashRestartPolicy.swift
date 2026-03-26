import Foundation

/// Rate-limits crash restarts: allows up to `maxRestarts` within a rolling `window`.
public struct CrashRestartPolicy {
    public let maxRestarts: Int
    public let window: TimeInterval
    public private(set) var crashTimestamps: [Date] = []

    public init(maxRestarts: Int = 3, window: TimeInterval = 180) {
        self.maxRestarts = maxRestarts
        self.window = window
    }

    /// Record a crash and return whether a restart is allowed.
    public mutating func recordCrash(at date: Date = Date()) -> Bool {
        crashTimestamps.append(date)
        crashTimestamps.removeAll { date.timeIntervalSince($0) > window }
        return crashTimestamps.count <= maxRestarts
    }

    /// Clear crash history (called on manual start/stop).
    public mutating func reset() {
        crashTimestamps = []
    }
}
