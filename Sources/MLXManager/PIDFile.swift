import Foundation

/// Reads and checks liveness of a PID file.
public protocol PIDFileReading {
    func read() -> Int32?
    func delete()
    static func isProcessAlive(pid: Int32) -> Bool
}

/// Writes and deletes a PID file.
public protocol PIDFileWriting {
    func write(pid: Int32) throws
    func delete()
}

/// Manages a PID file on disk for server process recovery across app restarts.
public struct PIDFile: PIDFileReading, PIDFileWriting {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Write a PID to the file. Creates parent directories if needed.
    public func write(pid: Int32) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try String(pid).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Read the PID from the file, or nil if the file doesn't exist or is malformed.
    public func read() -> Int32? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Delete the PID file. No-op if it doesn't exist.
    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Check if a process with the given PID is still alive.
    public static func isProcessAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}
