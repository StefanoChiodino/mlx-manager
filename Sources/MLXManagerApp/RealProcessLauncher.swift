import Foundation
import MLXManager

/// Production ProcessHandle wrapping Foundation's Process.
final class RealProcessHandle: ProcessHandle {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    var isRunning: Bool { process.isRunning }
    var processIdentifier: Int32 { process.processIdentifier }

    func terminate() {
        process.terminate()
    }
}

/// Production ProcessLauncher using Foundation's Process.
final class RealProcessLauncher: ProcessLauncher {
    func launch(command: String, arguments: [String], logPath: String?, onExit: @escaping () -> Void) throws -> ProcessHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        if let logPath {
            process.standardOutput = FileHandle(forWritingAtPath: logPath)
            process.standardError = FileHandle(forWritingAtPath: logPath)
        }
        process.terminationHandler = { _ in
            DispatchQueue.main.async { onExit() }
        }

        if let logPath {
            let logURL = URL(fileURLWithPath: logPath)
            let dir = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let logHandle = try FileHandle(forWritingTo: logURL)
            logHandle.seekToEndOfFile()
            process.standardError = logHandle
            process.standardOutput = logHandle
        }

        try process.run()
        return RealProcessHandle(process: process)
    }
}
