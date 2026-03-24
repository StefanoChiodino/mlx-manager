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
        serverManager.logPath = logPath
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

        recoverRunningServer(presets: presets)
        bootstrapEnvironmentIfNeeded()
    }

    // MARK: - Environment bootstrap

    private func bootstrapEnvironmentIfNeeded() {
        let presets = loadPresets()
        let backend = presets.first?.serverType ?? .mlxLM
        let checker = EnvironmentChecker()
        guard !checker.isReady(pythonPath: EnvironmentInstaller.pythonPath(for: backend)) else { return }
        statusBarController.environmentInstallStarted()
        let inst = EnvironmentInstaller(backend: backend)
        inst.onComplete = { [weak self] _ in
            self?.statusBarController.environmentInstallFinished()
            self?.backgroundInstaller = nil
        }
        inst.install()
        backgroundInstaller = inst
    }

    // MARK: - Process recovery

    private func recoverRunningServer(presets: [ServerConfig]) {
        let scanner = ProcessScanner(
            pidLister: SystemPIDLister(),
            argvReader: SystemProcessArgvReader()
        )
        guard let found = scanner.findAnyServer() else { return }
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
        let resolvedConfig = config.withResolvedPythonPath()
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
        statusBarController.updateLogLine(nil)
    }

    // MARK: - Log tailing

    private var logPath: String {
        NSString(string: settings.logPath).expandingTildeInPath
    }

    private func startTailing() {
        loadHistoricalLog()
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

    private func loadHistoricalLog() {
        let path = logPath
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        logLines.append(contentsOf: result.lines)
        requestHistory.append(contentsOf: result.records)
    }

    private func handleLogEvent(_ event: LogEvent) {
        // Feed log window
        let kind = LogLineKind(event)
        let line = rawLine(for: event)
        logLines.append((line, kind))
        if logLines.count > 10_000 { logLines.removeFirst() }

        // Update status bar log line
        if settings.showLastLogLine {
            statusBarController.updateLogLine(LogLineStripper.strip(line))
        }

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
            let swc = SettingsWindowController(presets: presets, settings: settings)
            settingsWindowController = swc

            let rebuild = { [weak self] (newPresets: [ServerConfig], newSettings: AppSettings) in
                guard let self else { return }
                self.settings = newSettings
                self.saveSettings(newSettings)
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

            swc.onChange = rebuild
            swc.onCancel = rebuild
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        installEditMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installEditMenu() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.item(withTitle: "Edit") == nil else { return }
        let mainMenu = NSApp.mainMenu ?? NSMenu()

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut",   action: #selector(NSText.cut(_:)),   keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",  action: #selector(NSText.copy(_:)),  keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Persistence

    private func loadPresets() -> [ServerConfig] {
        // Try user file first, fall back to bundled
        if let presets = try? UserPresetStore.load(from: UserPresetStore.defaultURL) {
            return presets.map { $0.withResolvedPythonPath() }
        }
        guard let url = bundledPresetsURL(),
              let yaml = try? String(contentsOf: url, encoding: .utf8),
              let presets = try? ConfigLoader.load(yaml: yaml) else {
            return []
        }
        return presets.map { $0.withResolvedPythonPath() }
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

}
