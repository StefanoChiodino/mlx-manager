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

/// Checks whether a PID still refers to a live process.
public protocol ProcessLivenessChecking {
    func isAlive(pid: Int32) -> Bool
}

/// Default implementation that calls the real kill(2).
public struct RealProcessTerminator: ProcessTerminating {
    public init() {}
    public func terminate(pid: Int32, signal: Int32) {
        kill(pid, signal)
    }
}

/// Default implementation backed by kill(pid, 0).
public struct RealProcessLivenessChecker: ProcessLivenessChecking {
    public init() {}

    public func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

/// Manages starting, stopping, and restarting the MLX server process.
public final class ServerManager {
    private let launcher: ProcessLauncher
    private let processTerminator: ProcessTerminating
    private let processLivenessChecker: ProcessLivenessChecking
    private let adoptedProcessPollInterval: TimeInterval
    private var process: ProcessHandle?
    private var currentLaunchGeneration: Int?
    private var nextLaunchGeneration: Int = 0
    private var expectedExitGenerations: Set<Int> = []
    private var adoptedPID: Int32?
    private(set) public var adoptedPort: Int?
    private(set) public var adoptedServer: DiscoveredServer?
    private var adoptedProcessMonitor: DispatchSourceTimer?

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
        processTerminator: ProcessTerminating = RealProcessTerminator(),
        processLivenessChecker: ProcessLivenessChecking = RealProcessLivenessChecker(),
        adoptedProcessPollInterval: TimeInterval = 0.1
    ) {
        self.launcher = launcher
        self.processTerminator = processTerminator
        self.processLivenessChecker = processLivenessChecker
        self.adoptedProcessPollInterval = adoptedProcessPollInterval
    }

    /// Start the server with the given config. Throws if already running.
    public func start(config: ServerConfig) throws {
        if isRunning { throw ServerError.alreadyRunning }

        let builder: ServerArgBuilder
        switch config.serverType {
        case .mlxLM:  builder = MLXLmArgBuilder()
        case .mlxVLM: builder = MLXVlmArgBuilder()
        }
        let arguments = builder.arguments(for: config)
        let launchGeneration = nextLaunchGeneration + 1
        nextLaunchGeneration = launchGeneration
        currentLaunchGeneration = launchGeneration
        process = try launcher.launch(command: config.pythonPath, arguments: arguments, logPath: logPath) { [weak self] in
            guard let self else { return }
            if self.currentLaunchGeneration == launchGeneration {
                self.process = nil
                self.currentLaunchGeneration = nil
            }
            if self.expectedExitGenerations.remove(launchGeneration) != nil {
                return
            }
            self.onExit?()
        }
    }

    /// Stop the running server. No-op if not running.
    public func stop() {
        if let adopted = adoptedPID {
            stopMonitoringAdoptedProcess()
            processTerminator.terminate(pid: adopted, signal: 15) // SIGTERM
            clearAdoptedProcess()
        } else {
            if let launchGeneration = currentLaunchGeneration {
                expectedExitGenerations.insert(launchGeneration)
            }
            process?.terminate()
            process = nil
            currentLaunchGeneration = nil
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
        adoptedServer = nil
        startMonitoringAdoptedProcess(pid: pid)
    }

    /// Adopt an externally-started process along with recovered runtime details.
    public func adoptProcess(server: DiscoveredServer) throws {
        if isRunning { throw ServerError.alreadyRunning }
        adoptedPID = server.pid
        adoptedPort = server.port
        adoptedServer = server
        startMonitoringAdoptedProcess(pid: server.pid)
    }

    private func startMonitoringAdoptedProcess(pid: Int32) {
        stopMonitoringAdoptedProcess()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + adoptedProcessPollInterval,
            repeating: adoptedProcessPollInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.adoptedPID == pid else {
                self.stopMonitoringAdoptedProcess()
                return
            }
            guard self.processLivenessChecker.isAlive(pid: pid) == false else { return }

            self.stopMonitoringAdoptedProcess()
            self.clearAdoptedProcess()
            self.onExit?()
        }
        timer.resume()
        adoptedProcessMonitor = timer
    }

    private func stopMonitoringAdoptedProcess() {
        adoptedProcessMonitor?.cancel()
        adoptedProcessMonitor = nil
    }

    private func clearAdoptedProcess() {
        adoptedPID = nil
        adoptedPort = nil
        adoptedServer = nil
    }
}
