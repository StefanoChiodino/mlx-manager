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
    func launch(command: String, arguments: [String], onExit: @escaping () -> Void) throws -> ProcessHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.terminationHandler = { _ in
            DispatchQueue.main.async { onExit() }
        }
        try process.run()
        return RealProcessHandle(process: process)
    }
}
