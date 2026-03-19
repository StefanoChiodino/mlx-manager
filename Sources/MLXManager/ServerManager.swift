import Foundation

/// Errors from server management.
public enum ServerError: Error, Equatable {
    case alreadyRunning
}

/// A handle to a launched process that can be terminated.
public protocol ProcessHandle: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

/// Abstraction over process launching for testability.
public protocol ProcessLauncher {
    func launch(command: String, arguments: [String]) throws -> ProcessHandle
}

/// Manages starting, stopping, and restarting the MLX server process.
public final class ServerManager {
    private let launcher: ProcessLauncher
    private var process: ProcessHandle?

    /// Whether the server process is currently running.
    public var isRunning: Bool { process?.isRunning ?? false }

    public init(launcher: ProcessLauncher) {
        self.launcher = launcher
    }

    /// Start the server with the given config. Throws if already running.
    public func start(config: ServerConfig) throws {
        if isRunning { throw ServerError.alreadyRunning }

        let arguments = [
            "-m", "mlx_lm.server",
            "--model", config.model,
            "--max-tokens", String(config.maxTokens)
        ] + config.extraArgs

        process = try launcher.launch(command: "python", arguments: arguments)
    }

    /// Stop the running server. No-op if not running.
    public func stop() {
        process?.terminate()
        process = nil
    }

    /// Restart: stop then start with the given config.
    public func restart(config: ServerConfig) throws {
        stop()
        try start(config: config)
    }
}
