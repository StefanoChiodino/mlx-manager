import AppKit
import MLXManager

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var serverManager: ServerManager!
    private var logTailer: LogTailer?
    private var serverState = ServerState()
    private var settings = AppSettings()

    // Environment bootstrap
    private var backgroundInstaller: EnvironmentInstaller?

    // History & monitoring
    private var requestHistory: [RequestRecord] = []
    private var ramSamples: [RAMSample] = []
    private var ramPoller: RAMPoller?

    // Log buffer
    private var logLines: [(String, LogLineKind)] = []

    // Windows
    private var settingsWindowController: SettingsWindowController?

    private let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mlx-manager/settings.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = loadSettings()
        let presets = loadPresets()
        serverManager = ServerManager(launcher: RealProcessLauncher())
        serverManager.onExit = { [weak self] in self?.handleProcessExit() }

        let view = StatusBarView()
        statusBarController = StatusBarController(
            view: view,
            presets: presets,
            onStart: { [weak self] config in self?.startServer(config: config) },
            onStop: { [weak self] in self?.stopServer() },
            settings: settings
        )

        statusBarController.onShowLog = { [weak self] in self?.showLog() }
        statusBarController.onShowHistory = { [weak self] in self?.showHistory() }
        statusBarController.onShowRAMGraph = { [weak self] in self?.showRAMGraph() }
        statusBarController.onShowSettings = { [weak self] in self?.showSettings(presets: presets) }

        recoverRunningServer()
        bootstrapEnvironmentIfNeeded()
    }

    // MARK: - Environment bootstrap

    private func bootstrapEnvironmentIfNeeded() {
        let checker = EnvironmentChecker()
        guard !checker.isReady(pythonPath: EnvironmentInstaller.pythonPath) else { return }
        statusBarController.environmentInstallStarted()
        let inst = EnvironmentInstaller()
        inst.onComplete = { [weak self] _ in
            self?.statusBarController.environmentInstallFinished()
            self?.backgroundInstaller = nil
        }
        inst.install()
        backgroundInstaller = inst
    }

    // MARK: - Process recovery

    private func recoverRunningServer() {
        let scanner = ProcessScanner(
            pidLister: SystemPIDLister(),
            argvReader: SystemProcessArgvReader()
        )
        guard let found = scanner.findMLXServer() else { return }
        try? serverManager.adoptProcess(pid: found.pid, port: found.port)
        serverState = ServerState()
        serverState.serverStarted()
        statusBarController.serverDidStart()
        startTailing()
        if settings.ramGraphEnabled {
            startRAMPolling(pid: found.pid)
        }
    }

    // MARK: - Server lifecycle

    private func startServer(config: ServerConfig) {
        let resolvedConfig = resolvedPythonPath(config)
        do {
            try serverManager.start(config: resolvedConfig)
            serverState = ServerState()
            serverState.serverStarted()
            statusBarController.serverDidStart()
            startTailing()

            if settings.ramGraphEnabled, let pid = serverManager.pid {
                startRAMPolling(pid: pid)
            }
        } catch {
            // Already running — ignore
        }
    }

    private func stopServer() {
        stopRAMPolling()
        logTailer?.stop()
        logTailer = nil
        serverManager.stop()
        serverState.serverStopped()
        statusBarController.serverDidStop()
        resetSession()
    }

    private func handleProcessExit() {
        stopRAMPolling()
        logTailer?.stop()
        logTailer = nil
        serverState.serverStopped()
        statusBarController.serverDidStop()
        resetSession()
    }

    private func resetSession() {
        requestHistory = []
        ramSamples = []
        logLines = []
    }

    // MARK: - Log tailing

    private var logPath: String {
        NSString(string: settings.logPath).expandingTildeInPath
    }

    private func startTailing() {
        logTailer?.stop()
        logTailer = LogTailer(
            path: logPath,
            fileHandleFactory: { path in
                guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
                return RealFileHandle(fh)
            },
            watcher: RealFileWatcher(),
            onEvent: { [weak self] event in
                self?.handleLogEvent(event)
            }
        )
        logTailer?.start()
    }

    private func handleLogEvent(_ event: LogEvent) {
        // Feed log window
        let kind = LogLineKind(event)
        let line = rawLine(for: event)
        logLines.append((line, kind))
        if logLines.count > 10_000 { logLines.removeFirst() }

        // Update state
        serverState.handle(event)
        statusBarController.update(state: serverState)

        // Drain completed request
        if let record = serverState.completedRequest {
            requestHistory.append(record)
            if requestHistory.count > 500 { requestHistory.removeFirst() }
            serverState.clearCompletedRequest()
        }
    }

    private func rawLine(for event: LogEvent) -> String {
        switch event {
        case let .progress(current, total, _):
            return "Prompt processing progress: \(current)/\(total)"
        case let .kvCaches(gpu, tokens):
            return String(format: "KV Caches: ... %.2f GB, latest user cache %d tokens", gpu, tokens)
        case .httpCompletion:
            return "POST /v1/chat/completions HTTP/1.1\" 200"
        }
    }

    // MARK: - RAM polling

    private func startRAMPolling(pid: Int32) {
        let poller = RAMPoller(pid: pid, interval: TimeInterval(settings.ramPollInterval))
        poller.onSample = { [weak self] sample in
            guard let self else { return }
            self.ramSamples.append(sample)
            if self.ramSamples.count > 1800 { self.ramSamples.removeFirst() }
        }
        poller.start()
        ramPoller = poller
    }

    private func stopRAMPolling() {
        ramPoller?.stop()
        ramPoller = nil
    }

    // MARK: - Window actions

    private func showLog() {
        statusBarController.showLogView(lines: logLines)
    }

    private func showHistory() {
        statusBarController.showHistoryView(records: requestHistory)
    }

    private func showRAMGraph() {
        statusBarController.showRAMGraphView(samples: ramSamples)
    }

    private func showSettings(presets: [ServerConfig]) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(presets: presets, settings: settings)
            settingsWindowController?.onSave = { [weak self] newPresets, newSettings in
                guard let self else { return }
                self.settings = newSettings
                self.saveSettings(newSettings)
                // Rebuild menu with new presets + settings
                let view = StatusBarView()
                self.statusBarController = StatusBarController(
                    view: view,
                    presets: newPresets,
                    onStart: { [weak self] config in self?.startServer(config: config) },
                    onStop: { [weak self] in self?.stopServer() },
                    settings: newSettings
                )
                self.statusBarController.onShowLog = { [weak self] in self?.showLog() }
                self.statusBarController.onShowHistory = { [weak self] in self?.showHistory() }
                self.statusBarController.onShowRAMGraph = { [weak self] in self?.showRAMGraph() }
                self.statusBarController.onShowSettings = { [weak self] in
                    self?.showSettings(presets: newPresets)
                }
                self.settingsWindowController = nil
            }
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Persistence

    private func loadPresets() -> [ServerConfig] {
        // Try user file first, fall back to bundled
        if let presets = try? UserPresetStore.load(from: UserPresetStore.defaultURL) {
            return presets.map { resolvedPythonPath($0) }
        }
        guard let url = bundledPresetsURL(),
              let yaml = try? String(contentsOf: url, encoding: .utf8),
              let presets = try? ConfigLoader.load(yaml: yaml) else {
            return []
        }
        return presets.map { resolvedPythonPath($0) }
    }

    /// Returns the URL for the bundled presets.yaml.
    /// Checks Bundle.module first (SPM dev build), then Bundle.main (.app bundle).
    private func bundledPresetsURL() -> URL? {
        if let url = Bundle.module.url(forResource: "presets", withExtension: "yaml") { return url }
        return Bundle.main.url(forResource: "presets", withExtension: "yaml")
    }

    private func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return s
    }

    private func saveSettings(_ s: AppSettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: settingsURL)
    }

    /// Expand tilde in pythonPath at runtime.
    private func resolvedPythonPath(_ config: ServerConfig) -> ServerConfig {
        let resolved = NSString(string: config.pythonPath).expandingTildeInPath
        guard resolved != config.pythonPath else { return config }
        return ServerConfig(name: config.name, model: config.model, maxTokens: config.maxTokens,
                            extraArgs: config.extraArgs, pythonPath: resolved)
    }
}
