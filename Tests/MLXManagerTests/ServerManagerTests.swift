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

// MARK: - Process Terminator Mock

final class MockProcessTerminator: ProcessTerminating {
    var killedPID: Int32?
    var killedSignal: Int32?

    func terminate(pid: Int32, signal: Int32) {
        killedPID = pid
        killedSignal = signal
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
            port: 8081,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: false,
            extraArgs: [],
            pythonPath: "/custom/venv/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedCommand == "/custom/venv/bin/python3")
        #expect(launcher.launchedArguments == [
            "-m", "mlx_lm.server",
            "--model", "mlx-community/Qwen3.5-35B-A3B-4bit",
            "--max-tokens", "40960",
            "--port", "8081",
            "--prefill-step-size", "4096",
            "--prompt-cache-size", "4",
            "--prompt-cache-bytes", String(10 * 1024 * 1024 * 1024),
            "--trust-remote-code",
            "--chat-template-args",
            "{\"enable_thinking\":false}"
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
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
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
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
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
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
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
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
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
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: false,
            extraArgs: [],
            pythonPath: "/usr/bin/python3"
        )
        let config2 = ServerConfig(
            name: "8-bit 80k",
            model: "mlx-community/Qwen3.5-35B-A3B-8bit",
            maxTokens: 81920,
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: false,
            extraArgs: [],
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
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
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
            port: 8081,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: true,
            enableThinking: false,
            extraArgs: [],
            pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments == [
            "-m", "mlx_lm.server",
            "--model", "mlx-community/Qwen3.5-35B-A3B-4bit",
            "--max-tokens", "40960",
            "--port", "8081",
            "--prefill-step-size", "4096",
            "--prompt-cache-size", "4",
            "--prompt-cache-bytes", String(10 * 1024 * 1024 * 1024),
            "--trust-remote-code",
            "--chat-template-args",
            "{\"enable_thinking\":false}"
        ])
    }

    // MARK: - T15: adoptProcess sets isRunning and pid

    @Test("adoptProcess sets isRunning to true and pid to adopted PID")
    func adoptProcess_setsRunningAndPID() throws {
        let launcher = MockLauncher()
        let terminator = MockProcessTerminator()
        let manager = ServerManager(launcher: launcher, processTerminator: terminator)

        try manager.adoptProcess(pid: 12345)

        #expect(manager.isRunning == true)
        #expect(manager.pid == 12345)
    }

    // MARK: - T16: stop on adopted process sends SIGTERM

    @Test("stop on adopted process sends SIGTERM and clears state")
    func stop_adopted_sendsSIGTERM() throws {
        let launcher = MockLauncher()
        let terminator = MockProcessTerminator()
        let manager = ServerManager(launcher: launcher, processTerminator: terminator)

        try manager.adoptProcess(pid: 12345)
        manager.stop()

        #expect(terminator.killedPID == 12345)
        #expect(terminator.killedSignal == 15) // SIGTERM
        #expect(manager.isRunning == false)
    }

    // MARK: - adoptProcess with port

    @Test("adoptProcess with explicit port stores it")
    func adoptProcess_withPort_storesPort() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)

        try manager.adoptProcess(pid: 777, port: 9000)

        #expect(manager.isRunning == true)
        #expect(manager.pid == 777)
        #expect(manager.adoptedPort == 9000)
    }

    // MARK: - T17: start while adopted throws alreadyRunning

    @Test("start while adopted throws alreadyRunning")
    func start_whileAdopted_throws() throws {
        let launcher = MockLauncher()
        let terminator = MockProcessTerminator()
        let manager = ServerManager(launcher: launcher, processTerminator: terminator)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.adoptProcess(pid: 12345)

        #expect(throws: ServerError.alreadyRunning) {
            try manager.start(config: config)
        }
    }

    // MARK: - T18: adoptProcess when already running throws

    @Test("adoptProcess when already running throws alreadyRunning")
    func adoptProcess_whileRunning_throws() throws {
        let launcher = MockLauncher()
        let terminator = MockProcessTerminator()
        let manager = ServerManager(launcher: launcher, processTerminator: terminator)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(throws: ServerError.alreadyRunning) {
            try manager.adoptProcess(pid: 999)
        }
    }

    // MARK: - T19: start includes port

    @Test("start includes port from config")
    func start_includesPort() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 9000, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--port") == true)
        #expect(launcher.launchedArguments?.contains("9000") == true)
    }

    // MARK: - T20: start includes prefillStepSize

    @Test("start includes prefillStepSize from config")
    func start_includesPrefillStepSize() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 2048, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--prefill-step-size") == true)
        #expect(launcher.launchedArguments?.contains("2048") == true)
    }

    // MARK: - T21: start includes promptCacheSize

    @Test("start includes promptCacheSize from config")
    func start_includesPromptCacheSize() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 8,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--prompt-cache-size") == true)
        #expect(launcher.launchedArguments?.contains("8") == true)
    }

    // MARK: - T22: start includes promptCacheBytes

    @Test("start includes promptCacheBytes from config")
    func start_includesPromptCacheBytes() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 5 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--prompt-cache-bytes") == true)
        #expect(launcher.launchedArguments?.contains(String(5 * 1024 * 1024 * 1024)) == true)
    }

    // MARK: - T23: start includes trustRemoteCode when true

    @Test("start includes --trust-remote-code when trustRemoteCode is true")
    func start_includesTrustRemoteCode() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: true, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--trust-remote-code") == true)
    }

    // MARK: - T24: start excludes trustRemoteCode when false

    @Test("start excludes --trust-remote-code when trustRemoteCode is false")
    func start_excludesTrustRemoteCode() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--trust-remote-code") == false)
    }

    // MARK: - T25: start enables thinking when enableThinking is true

    @Test("start includes enable_thinking:true when enableThinking is true")
    func start_includesEnableThinking() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: true,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--chat-template-args") == true)
        #expect(launcher.launchedArguments?.contains("{\"enable_thinking\":true}") == true)
    }

    // MARK: - T26: start disables thinking when enableThinking is false

    @Test("start includes enable_thinking:false when enableThinking is false")
    func start_excludesEnableThinking() throws {
        let launcher = MockLauncher()
        let manager = ServerManager(launcher: launcher)
        let config = ServerConfig(
            name: "test", model: "m", maxTokens: 1024,
            port: 8080, prefillStepSize: 4096, promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false, enableThinking: false,
            extraArgs: [], pythonPath: "/usr/bin/python3"
        )

        try manager.start(config: config)

        #expect(launcher.launchedArguments?.contains("--chat-template-args") == true)
        #expect(launcher.launchedArguments?.contains("{\"enable_thinking\":false}") == true)
    }
}
