import AppKit
import MLXManager
import os

private let logger = Logger(subsystem: "com.mlx-manager", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var serverCoordinator: ServerCoordinator!
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

        serverCoordinator = ServerCoordinator(
            logPath: logPath,
            launcher: RealProcessLauncher(),
            logTailerFactory: { path, onEvent in
                LogTailer(
                    path: path,
                    fileHandleFactory: { p in
                        guard let fh = FileHandle(forReadingAtPath: p) else { return nil }
                        return RealFileHandle(fh)
                    },
                    watcher: RealFileWatcher(),
                    onEvent: onEvent
                )
            }
        )

        serverCoordinator.onStateChange = { [weak self] state in
            guard let self else { return }
            self.statusBarController.update(state: state)
        }

        serverCoordinator.onRequestCompleted = { [weak self] record in
            guard let self else { return }
            self.requestHistory.append(record)
            if self.requestHistory.count > 500 { self.requestHistory.removeFirst() }
        }

        serverCoordinator.onLogEvent = { [weak self] event, line in
            guard let self else { return }
            let kind = LogLineKind(event)
            self.logLines.append((line, kind))
            if self.logLines.count > 10_000 { self.logLines.removeFirst() }
            if self.settings.showLastLogLine {
                self.statusBarController.updateLogLine(LogLineStripper.strip(line))
            }
        }

        serverCoordinator.onProcessExit = { [weak self] in
            guard let self else { return }
            self.stopRAMPolling()
            self.statusBarController.serverDidStop()
            self.resetSession()
        }

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
        statusBarController.onShowSettings = { [weak self] in
            guard let self else { return }
            self.showSettings(presets: self.loadPresets())
        }

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
        do {
            try serverCoordinator.adoptProcess(pid: found.pid, port: found.port)
        } catch {
            logger.info("adoptProcess skipped: \(error) — app likely owns the process")
        }
        loadHistoricalLog()
        statusBarController.serverDidStart()
        if settings.ramGraphEnabled {
            startRAMPolling(pid: found.pid)
        }
    }

    // MARK: - Server lifecycle

    private func startServer(config: ServerConfig) {
        let resolvedConfig = config.withResolvedPythonPath()
        do {
            try serverCoordinator.start(config: resolvedConfig)
            loadHistoricalLog()
            statusBarController.serverDidStart()
            if settings.ramGraphEnabled, let pid = serverCoordinator.pid {
                startRAMPolling(pid: pid)
            }
        } catch {
            logger.warning("startServer failed: \(error)")
        }
    }

    private func stopServer() {
        stopRAMPolling()
        serverCoordinator.stop()
        statusBarController.serverDidStop()
        resetSession()
    }

    private func resetSession() {
        requestHistory = []
        ramSamples = []
        logLines = []
        statusBarController.updateLogLine(nil)
    }

    // MARK: - Log loading

    private var logPath: String {
        NSString(string: settings.logPath).expandingTildeInPath
    }

    private func loadHistoricalLog() {
        let path = logPath
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        logLines.append(contentsOf: result.lines)
        requestHistory.append(contentsOf: result.records)
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

            let applyChanges = { [weak self] (newPresets: [ServerConfig], newSettings: AppSettings) in
                guard let self else { return }
                self.settings = newSettings
                self.saveSettings(newSettings)
                self.statusBarController.applySettings(newSettings)
                self.statusBarController.updatePresets(newPresets)
                self.settingsWindowController = nil
            }

            // onChange fires on every keystroke — only persist settings, don't rebuild the controller
            swc.onChange = { [weak self] _, newSettings in
                guard let self else { return }
                self.settings = newSettings
                self.saveSettings(newSettings)
            }
            // onClose fires when window closes normally — apply final state in-place
            swc.onClose = applyChanges
            // onCancel fires on Cancel — apply reverted snapshot in-place
            swc.onCancel = applyChanges
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
        do {
            let presets = try UserPresetStore.load(from: UserPresetStore.defaultURL)
            return presets.map { $0.withResolvedPythonPath() }
        } catch {
            logger.error("loadPresets (user file) failed: \(error)")
            // Fall through to bundled presets
        }
        guard let url = bundledPresetsURL() else { return [] }
        do {
            let yaml = try String(contentsOf: url, encoding: .utf8)
            let presets = try ConfigLoader.load(yaml: yaml)
            return presets.map { $0.withResolvedPythonPath() }
        } catch {
            logger.error("loadPresets failed: \(error)")
            return []
        }
    }

    /// Returns the URL for the bundled presets.yaml.
    /// Checks Bundle.module first (SPM dev build), then Bundle.main (.app bundle).
    private func bundledPresetsURL() -> URL? {
        if let url = Bundle.module.url(forResource: "presets", withExtension: "yaml") { return url }
        return Bundle.main.url(forResource: "presets", withExtension: "yaml")
    }

    private func loadSettings() -> AppSettings {
        do {
            let data = try Data(contentsOf: settingsURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            logger.info("loadSettings using defaults: \(error)")
            return AppSettings()
        }
    }

    private func saveSettings(_ s: AppSettings) {
        do {
            let data = try JSONEncoder().encode(s)
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: settingsURL)
        } catch {
            logger.error("saveSettings failed: \(error)")
        }
    }

}
