import Foundation
import Darwin

/// A running mlx_lm.server process found by the scanner.
public struct DiscoveredProcess: Equatable {
    public let pid: Int32
    public let port: Int

    public init(pid: Int32, port: Int) {
        self.pid = pid
        self.port = port
    }
}

/// Returns all PIDs currently running on the system.
public protocol PIDListing {
    func allPIDs() -> [Int32]
}

/// Reads the argument vector of a running process by PID.
public protocol ProcessArgvReading {
    /// Returns the argv array for the given PID, or nil if unavailable.
    func argv(for pid: Int32) -> [String]?
}

/// Production implementation of PIDListing using proc_listallpids.
public struct SystemPIDLister: PIDListing {
    public init() {}

    public func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 16) // pad for race safety
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled)).filter { $0 > 0 })
    }
}

/// Production implementation that reads process argv via sysctl(KERN_PROCARGS2).
public struct SystemProcessArgvReader: ProcessArgvReading {
    public init() {}

    public func argv(for pid: Int32) -> [String]? {
        // Step 1: determine required buffer size
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        // Step 2: fetch raw bytes
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Step 3: first 4 bytes = argc as Int32 (we don't need it, just skip)
        guard size > 4 else { return nil }
        var offset = 4

        // Step 4: skip the null-terminated executable path
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // skip the null terminator
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Step 5: parse remaining null-separated strings as argv
        var args: [String] = []
        var start = offset
        while offset < size {
            if buffer[offset] == 0 {
                if offset > start {
                    let slice = Array(buffer[start..<offset])
                    if let s = String(bytes: slice, encoding: .utf8) {
                        args.append(s)
                    }
                }
                start = offset + 1
            }
            offset += 1
        }
        // capture last token if no trailing null
        if start < size {
            let slice = Array(buffer[start..<size])
            if let s = String(bytes: slice, encoding: .utf8), !s.isEmpty {
                args.append(s)
            }
        }

        return args.isEmpty ? nil : args
    }
}

/// Scans all running processes and returns the first one identified as
/// an mlx_lm.server instance.
public struct ProcessScanner {
    private let pidLister: PIDListing
    private let argvReader: ProcessArgvReading

    public init(pidLister: PIDListing, argvReader: ProcessArgvReading) {
        self.pidLister = pidLister
        self.argvReader = argvReader
    }

    /// Returns the first discovered mlx_lm.server process, or nil.
    public func findMLXServer() -> DiscoveredProcess? {
        for pid in pidLister.allPIDs() {
            guard let args = argvReader.argv(for: pid) else { continue }
            guard isMLXServer(args) else { continue }
            return DiscoveredProcess(pid: pid, port: extractPort(from: args))
        }
        return nil
    }

    private func isMLXServer(_ args: [String]) -> Bool {
        // "python -m mlx_lm.server"
        if let idx = args.firstIndex(of: "-m"),
           args.indices.contains(idx + 1),
           args[idx + 1] == "mlx_lm.server" {
            return true
        }
        // bare "mlx_lm.server" element
        if args.contains("mlx_lm.server") { return true }
        // script path ending in mlx_lm/server.py
        if args.contains(where: { $0.hasSuffix("mlx_lm/server.py") }) { return true }
        return false
    }

    private func extractPort(from args: [String]) -> Int {
        if let idx = args.firstIndex(of: "--port"),
           args.indices.contains(idx + 1),
           let port = Int(args[idx + 1]) {
            return port
        }
        return 8080
    }
}
