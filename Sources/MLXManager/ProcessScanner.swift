import Foundation
import Darwin

/// A running mlx server process found by the scanner.
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
    func argv(for pid: Int32) -> [String]?
}

/// Production implementation of PIDListing using proc_listallpids.
public struct SystemPIDLister: PIDListing {
    public init() {}

    public func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 16)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled)).filter { $0 > 0 })
    }
}

/// Production implementation that reads process argv via sysctl(KERN_PROCARGS2).
public struct SystemProcessArgvReader: ProcessArgvReading {
    public init() {}

    public func argv(for pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        guard size > 4 else { return nil }
        var offset = 4
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }
        var args: [String] = []
        var start = offset
        while offset < size {
            if buffer[offset] == 0 {
                if offset > start {
                    let slice = Array(buffer[start..<offset])
                    if let s = String(bytes: slice, encoding: .utf8) { args.append(s) }
                }
                start = offset + 1
            }
            offset += 1
        }
        if start < size {
            let slice = Array(buffer[start..<size])
            if let s = String(bytes: slice, encoding: .utf8), !s.isEmpty { args.append(s) }
        }
        return args.isEmpty ? nil : args
    }
}

/// Scans all running processes and returns the first one identified as
/// a server matching the given backend.
public struct ProcessScanner {
    private let pidLister: PIDListing
    private let argvReader: ProcessArgvReading

    public init(pidLister: PIDListing, argvReader: ProcessArgvReading) {
        self.pidLister = pidLister
        self.argvReader = argvReader
    }

    /// Returns the first discovered server process for the given backend, or nil.
    public func findServer(backend: ServerType) -> DiscoveredProcess? {
        for pid in pidLister.allPIDs() {
            guard let args = argvReader.argv(for: pid) else { continue }
            guard isServer(args, backend: backend) else { continue }
            return DiscoveredProcess(pid: pid, port: extractPort(from: args))
        }
        return nil
    }

    private func isServer(_ args: [String], backend: ServerType) -> Bool {
        let module = backend.serverEntryName  // e.g. "mlx_lm.server" or "mlx_vlm.server"
        // Path suffix matching: "mlx_lm/server.py" or "mlx_vlm/server.py"
        let pathComponent = module.replacingOccurrences(of: ".", with: "/") + ".py"

        if let idx = args.firstIndex(of: "-m"),
           args.indices.contains(idx + 1),
           args[idx + 1] == module { return true }
        if args.contains(module) { return true }
        if args.contains(where: { $0.hasSuffix(pathComponent) }) { return true }
        // venv bin script: ends in /mlx_lm.server or /mlx_vlm.server
        if args.contains(where: { $0.hasSuffix("/\(module)") }) { return true }
        return false
    }

    private func extractPort(from args: [String]) -> Int {
        if let idx = args.firstIndex(of: "--port"),
           args.indices.contains(idx + 1),
           let port = Int(args[idx + 1]) { return port }
        return 8080
    }
}
