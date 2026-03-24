import Foundation

/// Protocol so LogTailer can be replaced by a mock in tests.
public protocol LogTailerProtocol {
    func start()
    func stop()
}

extension LogTailer: LogTailerProtocol {}

/// Coordinates ServerManager, ServerState, and LogTailer into a single unit.
public final class ServerCoordinator {
    private let serverManager: ServerManager
    private var logTailer: (any LogTailerProtocol)?
    private let logPath: String
    private let logTailerFactory: (String, @escaping (LogEvent) -> Void) -> any LogTailerProtocol

    public var onStateChange: ((ServerState) -> Void)?
    public var onLogEvent: ((LogEvent, String) -> Void)?
    public var onRequestCompleted: ((RequestRecord) -> Void)?
    public var onProcessExit: (() -> Void)?

    public private(set) var state: ServerState = ServerState()

    public var isRunning: Bool { serverManager.isRunning }
    public var pid: Int32? { serverManager.pid }
    public var adoptedServer: DiscoveredServer? { serverManager.adoptedServer }

    public init(
        logPath: String,
        launcher: ProcessLauncher,
        logTailerFactory: @escaping (String, @escaping (LogEvent) -> Void) -> any LogTailerProtocol
    ) {
        self.logPath = logPath
        self.logTailerFactory = logTailerFactory
        self.serverManager = ServerManager(launcher: launcher)
        self.serverManager.logPath = logPath
        self.serverManager.onExit = { [weak self] in
            self?.handleProcessExit()
        }
    }

    public func start(config: ServerConfig) throws {
        try serverManager.start(config: config)
        state = ServerState()
        state.serverStarted()
        onStateChange?(state)
        startTailing()
    }

    public func stop() {
        logTailer?.stop()
        logTailer = nil
        serverManager.stop()
        state.serverStopped()
        onStateChange?(state)
    }

    public func adoptProcess(pid: Int32, port: Int = 8080) throws {
        try serverManager.adoptProcess(pid: pid, port: port)
        state = ServerState()
        state.serverStarted()
        onStateChange?(state)
        startTailing()
    }

    public func adoptProcess(server: DiscoveredServer) throws {
        try serverManager.adoptProcess(server: server)
        state = ServerState()
        state.serverStarted()
        onStateChange?(state)
        startTailing()
    }

    // MARK: - Private

    private func startTailing() {
        logTailer?.stop()
        logTailer = logTailerFactory(logPath) { [weak self] event in
            self?.handleLogEvent(event)
        }
        logTailer?.start()
    }

    private func handleLogEvent(_ event: LogEvent) {
        let line = rawLine(for: event)
        onLogEvent?(event, line)
        state.handle(event)
        onStateChange?(state)
        if let record = state.completedRequest {
            onRequestCompleted?(record)
            state.clearCompletedRequest()
        }
    }

    private func handleProcessExit() {
        logTailer?.stop()
        logTailer = nil
        state.serverCrashed()
        onStateChange?(state)
        onProcessExit?()
    }

    private func rawLine(for event: LogEvent) -> String {
        switch event {
        case let .progress(current, total, _):
            return "Prompt processing progress: \(current)/\(total)"
        case let .kvCaches(gpuGB: gpu, tokens: tokens):
            return String(format: "KV Caches: ... %.2f GB, latest user cache %d tokens", gpu, tokens)
        case .httpCompletion:
            return "POST /v1/chat/completions HTTP/1.1\" 200"
        }
    }
}
