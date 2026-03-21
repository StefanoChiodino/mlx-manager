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
    func launch(command: String, arguments: [String], logPath: String?, onExit: @escaping () -> Void) throws -> ProcessHandle
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
    private let processTerminator: ProcessTerminating
    private var process: ProcessHandle?
    private var adoptedPID: Int32?
    private(set) public var adoptedPort: Int?

    /// Path to redirect server stderr to. Set before calling start().
    public var logPath: String?

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
        processTerminator: ProcessTerminating = RealProcessTerminator()
    ) {
        self.launcher = launcher
        self.processTerminator = processTerminator
    }

    /// Start the server with the given config. Throws if already running.
    public func start(config: ServerConfig) throws {
        if isRunning { throw ServerError.alreadyRunning }

        var arguments: [String] = [
            "-m", config.serverType.serverEntryName,
            "--model", config.model,
            "--port", String(config.port),
            "--prefill-step-size", String(config.prefillStepSize)
        ]

        // MLX-LM uses --max-tokens, --prompt-cache-size, --prompt-cache-bytes
        // MLX-VLM uses --max-kv-size instead
        switch config.serverType {
        case .mlxLM:
            arguments.append(contentsOf: [
                "--max-tokens", String(config.maxTokens),
                "--prompt-cache-size", String(config.promptCacheSize),
                "--prompt-cache-bytes", String(config.promptCacheBytes)
            ])
        case .mlxVLM:
            // For MLX-VLM, interpret maxTokens as max-kv-size
            arguments.append(contentsOf: [
                "--max-kv-size", String(config.maxTokens)
            ])
        }

        if config.trustRemoteCode {
            arguments.append("--trust-remote-code")
        }

        // Only add --chat-template-args for MLX-LM (MLX-VLM doesn't use it)
        if config.serverType == .mlxLM {
            arguments.append("--chat-template-args")
            arguments.append("{\"enable_thinking\":\(config.enableThinking ? "true" : "false")}")
        }

        arguments.append(contentsOf: config.extraArgs)

        process = try launcher.launch(command: config.pythonPath, arguments: arguments, logPath: logPath) { [weak self] in
            self?.process = nil
            self?.onExit?()
        }
    }

    /// Stop the running server. No-op if not running.
    public func stop() {
        if let adopted = adoptedPID {
            processTerminator.terminate(pid: adopted, signal: 15) // SIGTERM
            adoptedPID = nil
            adoptedPort = nil
        } else {
            process?.terminate()
            process = nil
        }
    }

    /// Restart: stop then start with the given config.
    public func restart(config: ServerConfig) throws {
        stop()
        try start(config: config)
    }

    /// Adopt an externally-started process by PID, optionally recording its port.
    public func adoptProcess(pid: Int32, port: Int = 8080) throws {
        if isRunning { throw ServerError.alreadyRunning }
        adoptedPID = pid
        adoptedPort = port
    }
}
