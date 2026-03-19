import Testing
@testable import MLXManager

// MARK: - Test Doubles

final class MockProcessHandle: ProcessHandle {
    var isRunning: Bool = true
    var processIdentifier: Int32 = 99999
    var terminateCalled = false

    func terminate() {
        terminateCalled = true
        isRunning = false
    }
}

final class MockLauncher: ProcessLauncher {
    var launchedCommand: String?
    var launchedArguments: [String]?
    var launchCount = 0
    var handleToReturn = MockProcessHandle()
    var lastOnExit: (() -> Void)?

    func launch(command: String, arguments: [String], onExit: @escaping () -> Void) throws -> ProcessHandle {
        launchedCommand = command
        launchedArguments = arguments
        launchCount += 1
        lastOnExit = onExit
        return handleToReturn
    }
}

// MARK: - Tests

@Suite("ServerManager")
struct ServerManagerTests {

    // MARK: - Start: argument assembly

    @Test("start uses pythonPath from config as the command")
    func startUsesPythonPathFromConfig() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "4-bit 40k",
            model: "mlx-community/Qwen3.5-35B-A3B-4bit",
            maxTokens: 40960,
            extraArgs: ["--trust-remote-code"],
            pythonPath: "/custom/venv/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedCommand == "/custom/venv/bin/python3")
        #expect(launcher.launchedArguments == [
            "-m", "mlx_lm.server",
            "--model", "mlx-community/Qwen3.5-35B-A3B-4bit",
            "--max-tokens", "40960",
            "--trust-remote-code"
        ])
    }

    // MARK: - Start: isRunning becomes true

    @Test("start sets isRunning to true")
    func startSetsIsRunning() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test",
            model: "test-model",
            maxTokens: 1024,
            extraArgs: [],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(manager.isRunning == true)
    }

    // MARK: - Start: already running throws

    @Test("start while already running throws alreadyRunning")
    func startWhileRunningThrows() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test",
            model: "test-model",
            maxTokens: 1024,
            extraArgs: [],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(throws: ServerError.alreadyRunning) {
            try manager.start(config: config)
        }
    }

    // MARK: - Stop: terminates process

    @Test("stop terminates the running process")
    func stopTerminatesProcess() throws {
        let launcher = MockLauncher()
        let handle = MockProcessHandle()
        launcher.handleToReturn = handle
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test",
            model: "test-model",
            maxTokens: 1024,
            extraArgs: [],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)
        manager.stop()

        #expect(handle.terminateCalled == true)
    }

    // MARK: - Stop: isRunning becomes false

    @Test("stop sets isRunning to false")
    func stopSetsIsRunningFalse() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test",
            model: "test-model",
            maxTokens: 1024,
            extraArgs: [],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)
        manager.stop()

        #expect(manager.isRunning == false)
    }

    // MARK: - Stop: no-op when not running

    @Test("stop while not running is a no-op")
    func stopWhileNotRunningIsNoOp() {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)

        // Should not throw or crash
        manager.stop()
        #expect(manager.isRunning == false)
    }

    // MARK: - Restart: stops then starts

    @Test("restart stops the current process and starts with new config")
    func restartStopsAndStarts() throws {
        let launcher = MockLauncher()
        let oldHandle = MockProcessHandle()
        launcher.handleToReturn = oldHandle
        let manager = ServerManager(launcher: launcher)
        let config1 = ServerConfig(
            name: "4-bit 40k",
            model: "mlx-community/Qwen3.5-35B-A3B-4bit",
            maxTokens: 40960,
            extraArgs: ["--trust-remote-code"],
            pythonPath: "/usr/bin/python3"
        )
        let config2 = ServerConfig(
            name: "8-bit 80k",
            model: "mlx-community/Qwen3.5-35B-A3B-8bit",
            maxTokens: 81920,
            extraArgs: ["--trust-remote-code"],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config1)

        // Swap handle for second launch
        let newHandle = MockProcessHandle()
        launcher.handleToReturn = newHandle

        try manager.restart(config: config2)

        #expect(oldHandle.terminateCalled == true)
        #expect(manager.isRunning == true)
        #expect(launcher.launchedArguments?.contains("mlx-community/Qwen3.5-35B-A3B-8bit") == true)
        #expect(launcher.launchCount == 2)
    }

    // MARK: - onExit: process exits unexpectedly

    @Test("onExit is called when process terminates")
    func onExitCalledWhenProcessTerminates() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        var exitCalled = false
        manager.onExit = { exitCalled = true }
        let config = ServerConfig(
            name: "test",
            model: "test-model",
            maxTokens: 1024,
            extraArgs: [],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)
        launcher.lastOnExit?()

        #expect(exitCalled == true)
        #expect(manager.isRunning == false)
    }

    // MARK: - Start: includes extra args

    @Test("start includes all extraArgs in argument list")
    func startIncludesExtraArgs() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "4-bit 40k",
            model: "mlx-community/Qwen3.5-35B-A3B-4bit",
            maxTokens: 40960,
            extraArgs: [
                "--trust-remote-code",
                "--chat-template-args",
                "{\"enable_thinking\":false}"
            ],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments == [
            "-m", "mlx_lm.server",
            "--model", "mlx-community/Qwen3.5-35B-A3B-4bit",
            "--max-tokens", "40960",
            "--trust-remote-code",
            "--chat-template-args",
            "{\"enable_thinking\":false}"
        ])
    }
}
