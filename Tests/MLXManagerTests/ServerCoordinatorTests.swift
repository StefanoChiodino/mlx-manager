import Foundation
import Testing
@testable import MLXManager

// MARK: - Test Doubles

final class MockLogTailer: LogTailerProtocol {
    private(set) var started = false
    private(set) var stopped = false
    var eventCallback: ((LogEvent) -> Void)?

    func start() { started = true }
    func stop() { stopped = true }
    func fire(_ event: LogEvent) { eventCallback?(event) }
}

final class MockProcessLauncherForCoordinator: ProcessLauncher {
    var shouldThrow: Error? = nil
    var launched = false
    var exitCallback: (() -> Void)?

    func launch(command: String, arguments: [String], logPath: String?, onExit: @escaping () -> Void) throws -> ProcessHandle {
        if let e = shouldThrow { throw e }
        launched = true
        exitCallback = onExit
        return MockProcessHandleForCoordinator()
    }
}

final class MockProcessHandleForCoordinator: ProcessHandle {
    var isRunning = true
    var processIdentifier: Int32 = 42
    func terminate() { isRunning = false }
}

@Suite("ServerCoordinator")
struct ServerCoordinatorTests {

    private func makeCoordinator(
        launcher: MockProcessLauncherForCoordinator = MockProcessLauncherForCoordinator(),
        tailer: MockLogTailer = MockLogTailer()
    ) -> (ServerCoordinator, MockLogTailer) {
        let t = tailer
        let coordinator = ServerCoordinator(
            logPath: "/tmp/test.log",
            launcher: launcher,
            logTailerFactory: { _, cb -> any LogTailerProtocol in
                t.eventCallback = cb
                return t
            }
        )
        return (coordinator, t)
    }

    @Test("start sets state to idle and starts tailing")
    func test_start_setsStateToIdle_andStartsTailing() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let tailer = MockLogTailer()
        let (coordinator, _) = makeCoordinator(launcher: launcher, tailer: tailer)

        try coordinator.start(config: ServerConfig.fixture())

        #expect(coordinator.isRunning)
        #expect(coordinator.state.status == .idle)
        #expect(tailer.started)
    }

    @Test("stop sets state to offline and stops tailing")
    func test_stop_setsStateToOffline_andStopsTailing() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let tailer = MockLogTailer()
        let (coordinator, _) = makeCoordinator(launcher: launcher, tailer: tailer)

        try coordinator.start(config: ServerConfig.fixture())
        coordinator.stop()

        #expect(!coordinator.isRunning)
        #expect(coordinator.state.status == .offline)
        #expect(tailer.stopped)
    }

    @Test("log event updates state and notifies onStateChange callback")
    func test_logEvent_updatesState_andNotifiesCallback() throws {
        let tailer = MockLogTailer()
        let (coordinator, _) = makeCoordinator(tailer: tailer)
        try coordinator.start(config: ServerConfig.fixture())

        var receivedState: ServerState?
        coordinator.onStateChange = { receivedState = $0 }

        tailer.fire(.progress(current: 5, total: 100, percentage: 5.0, timestamp: Date()))

        #expect(receivedState != nil)
        #expect(receivedState?.status == .processing)
    }

    @Test("process exit fires onProcessExit and state becomes failed")
    func test_processExit_setsStateToFailed() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let (coordinator, _) = makeCoordinator(launcher: launcher)
        coordinator.autoRestartEnabled = false
        try coordinator.start(config: ServerConfig.fixture())

        var exitFired = false
        var receivedState: ServerState?
        coordinator.onStateChange = { receivedState = $0 }
        coordinator.onProcessExit = { exitFired = true }

        launcher.exitCallback?()

        #expect(exitFired)
        #expect(coordinator.state.status == .failed)
        #expect(receivedState?.status == .failed)
    }

    @Test("start when already running throws alreadyRunning")
    func test_start_whenAlreadyRunning_throwsAlreadyRunning() throws {
        let (coordinator, _) = makeCoordinator()
        try coordinator.start(config: ServerConfig.fixture())
        #expect(throws: ServerError.alreadyRunning) {
            try coordinator.start(config: ServerConfig.fixture())
        }
    }

    @Test("process exit with autoRestart enabled fires onAutoRestart")
    func test_processExit_autoRestartEnabled_firesOnAutoRestart() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let (coordinator, _) = makeCoordinator(launcher: launcher)
        coordinator.autoRestartEnabled = true
        coordinator.restartDelay = 0 // no delay in tests
        try coordinator.start(config: ServerConfig.fixture())

        var autoRestartFired = false
        var exitFired = false
        coordinator.onAutoRestart = { autoRestartFired = true }
        coordinator.onProcessExit = { exitFired = true }

        launcher.exitCallback?()

        #expect(autoRestartFired)
        #expect(!exitFired)
    }

    @Test("process exit with autoRestart disabled fires onProcessExit")
    func test_processExit_autoRestartDisabled_firesOnProcessExit() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let (coordinator, _) = makeCoordinator(launcher: launcher)
        coordinator.autoRestartEnabled = false
        try coordinator.start(config: ServerConfig.fixture())

        var exitFired = false
        var autoRestartFired = false
        coordinator.onProcessExit = { exitFired = true }
        coordinator.onAutoRestart = { autoRestartFired = true }

        launcher.exitCallback?()

        #expect(exitFired)
        #expect(!autoRestartFired)
    }

    @Test("exhausted restart retries fires onRestartExhausted")
    func test_processExit_exhaustedRetries_firesOnRestartExhausted() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let (coordinator, _) = makeCoordinator(launcher: launcher)
        coordinator.autoRestartEnabled = true
        coordinator.restartDelay = 0

        // Use a policy with maxRestarts=1 for quick exhaustion
        coordinator.crashRestartPolicy = CrashRestartPolicy(maxRestarts: 1, window: 180)
        try coordinator.start(config: ServerConfig.fixture())

        var autoRestartCount = 0
        var exhaustedFired = false
        var exitFired = false
        coordinator.onAutoRestart = { autoRestartCount += 1 }
        coordinator.onRestartExhausted = { exhaustedFired = true }
        coordinator.onProcessExit = { exitFired = true }

        // First crash — allowed (1 <= 1), triggers auto-restart
        launcher.exitCallback?()
        #expect(autoRestartCount == 1)
        #expect(!exhaustedFired)

        // Second crash — exhausted (2 > 1)
        launcher.exitCallback?()
        #expect(exhaustedFired)
        #expect(exitFired)
    }

    @Test("manual stop resets crash policy")
    func test_stop_resetsCrashPolicy() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let (coordinator, _) = makeCoordinator(launcher: launcher)
        coordinator.autoRestartEnabled = true
        coordinator.restartDelay = 0
        try coordinator.start(config: ServerConfig.fixture())

        // Trigger a crash to populate policy
        launcher.exitCallback?()

        coordinator.stop()

        #expect(coordinator.crashRestartPolicy.crashTimestamps.isEmpty)
    }

    @Test("adopt discovered server preserves recovered runtime details")
    func test_adoptDiscoveredServer_preservesRecoveredRuntimeDetails() throws {
        let tailer = MockLogTailer()
        let (coordinator, _) = makeCoordinator(tailer: tailer)
        let discovered = DiscoveredServer(
            pid: 55,
            command: "/custom/venv/bin/python3",
            arguments: [
                "-m", "mlx_vlm.server",
                "--model", "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
                "--port", "8082"
            ],
            serverType: .mlxVLM,
            model: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
            port: 8082
        )

        try coordinator.adoptProcess(server: discovered)

        #expect(coordinator.isRunning)
        #expect(coordinator.pid == 55)
        #expect(coordinator.adoptedServer == discovered)
        #expect(coordinator.state.status == .idle)
        #expect(tailer.started)
    }
}
