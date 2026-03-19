import Foundation

/// Result of attempting to recover a previously-running server process.
public enum RecoveryResult: Equatable {
    case noFile
    case staleFile
    case adopted(pid: Int32)
}

/// Checks for a PID file on launch and determines if a server process is still alive.
public struct PIDRecovery {
    public init() {}

    /// Attempt to recover a running server from a PID file.
    public func recover(pidFile: PIDFileReading, isAlive: (Int32) -> Bool) -> RecoveryResult {
        guard let pid = pidFile.read() else { return .noFile }
        if isAlive(pid) {
            return .adopted(pid: pid)
        } else {
            pidFile.delete()
            return .staleFile
        }
    }
}
