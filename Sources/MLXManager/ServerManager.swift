import Foundation

/// Errors from server management.
public enum ServerError: Error, Equatable {
    case alreadyRunning
}

/// A handle to a launched process that can be terminated.
public protocol ProcessHandle: AnyObject {
    var isRunning: Bool { get }
    var processIdentifier: Int32 { get }
    func terminate()
}

/// Abstraction over process launching for testability.
public protocol ProcessLauncher {
    func launch(command: String, arguments: [String], onExit: @escaping () -> Void) throws -> ProcessHandle
}

/// Abstraction over kill(pid, signal) for testability.
public protocol ProcessTerminating {
    func terminate(pid: Int32, signal: Int32)
}

/// Default implementation that calls the real kill(2).
public struct RealProcessTerminator: ProcessTerminating {
    public init() {}
    public func terminate(pid: Int32, signal: Int32) {
        kill(pid, signal)
    }
}

/// Manages starting, stopping, and restarting the MLX server process.
public final class ServerManager {
    private let launcher: ProcessLauncher
    private let pidFile: PIDFileWriting?
    private let processTerminator: ProcessTerminating
    private var process: ProcessHandle?
    private var adoptedPID: Int32?

    /// Called when the server process exits unexpectedly.
    public var onExit: (() -> Void)?

    /// Whether the server process is currently running.
    public var isRunning: Bool {
        if adoptedPID != nil { return true }
        return process?.isRunning ?? false
    }

    /// PID of the running process, or nil if not running.
    public var pid: Int32? {
        if let adopted = adoptedPID { return adopted }
        return process?.isRunning == true ? process?.processIdentifier : nil
    }

    public init(
        launcher: ProcessLauncher,
        pidFile: PIDFileWriting? = nil,
        processTerminator: ProcessTerminating = RealProcessTerminator()
    ) {
        self.launcher = launcher
        self.pidFile = pidFile
        self.processTerminator = processTerminator
    }

    /// Start the server with the given config. Throws if already running.
    public func start(config: ServerConfig) throws {
        if isRunning { throw ServerError.alreadyRunning }

        let arguments = [
            "-m", "mlx_lm.server",
            "--model", config.model,
            "--max-tokens", String(config.maxTokens)
        ] + config.extraArgs

        process = try launcher.launch(command: config.pythonPath, arguments: arguments) { [weak self] in
            self?.process = nil
            self?.pidFile?.delete()
            self?.onExit?()
        }

        if let pid = process?.processIdentifier {
            try? pidFile?.write(pid: pid)
        }
    }

    /// Stop the running server. No-op if not running.
    public func stop() {
        if let adopted = adoptedPID {
            processTerminator.terminate(pid: adopted, signal: 15) // SIGTERM
            adoptedPID = nil
        } else {
            process?.terminate()
            process = nil
        }
        pidFile?.delete()
    }

    /// Restart: stop then start with the given config.
    public func restart(config: ServerConfig) throws {
        stop()
        try start(config: config)
    }

    /// Adopt an externally-started process by PID.
    public func adoptProcess(pid: Int32) throws {
        if isRunning { throw ServerError.alreadyRunning }
        adoptedPID = pid
    }
}
