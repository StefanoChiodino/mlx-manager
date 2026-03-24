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

        tailer.fire(.progress(current: 5, total: 100, percentage: 5.0))

        #expect(receivedState != nil)
        #expect(receivedState?.status == .processing)
    }

    @Test("process exit fires onProcessExit and state becomes offline")
    func test_processExit_setsStateToOffline() throws {
        let launcher = MockProcessLauncherForCoordinator()
        let (coordinator, _) = makeCoordinator(launcher: launcher)
        try coordinator.start(config: ServerConfig.fixture())

        var exitFired = false
        coordinator.onProcessExit = { exitFired = true }

        launcher.exitCallback?()

        #expect(exitFired)
        #expect(coordinator.state.status == .offline)
    }

    @Test("start when already running throws alreadyRunning")
    func test_start_whenAlreadyRunning_throwsAlreadyRunning() throws {
        let (coordinator, _) = makeCoordinator()
        try coordinator.start(config: ServerConfig.fixture())
        #expect(throws: ServerError.alreadyRunning) {
            try coordinator.start(config: ServerConfig.fixture())
        }
    }
}
