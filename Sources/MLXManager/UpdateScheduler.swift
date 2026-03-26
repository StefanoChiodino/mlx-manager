import Foundation

/// Determines when the next package update check should run.
public struct UpdateScheduler {

    public enum Action: Equatable {
        case checkNow
        case scheduleAfter(TimeInterval)
        case disabled
    }

    /// Evaluate what action to take based on current settings.
    /// - Parameters:
    ///   - interval: Hours between checks. 0 means disabled.
    ///   - lastCheck: Timestamp of last successful check, or nil if never checked.
    ///   - now: Current time.
    public static func evaluate(interval: Int, lastCheck: Date?, now: Date) -> Action {
        guard interval > 0 else { return .disabled }

        guard let lastCheck else { return .checkNow }

        let intervalSeconds = TimeInterval(interval * 3600)
        let elapsed = now.timeIntervalSince(lastCheck)

        if elapsed >= intervalSeconds {
            return .checkNow
        } else {
            return .scheduleAfter(intervalSeconds - elapsed)
        }
    }
}
