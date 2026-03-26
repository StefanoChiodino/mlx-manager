import AppKit
import MLXManager
import os
import UserNotifications

private let logger = Logger(subsystem: "com.mlx-manager", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var serverCoordinator: ServerCoordinator!
    private var gatewayServer: ManagedGatewayServer?
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

    // Package update
    private var updateTimer: Timer?
    private var notificationTimer: Timer?
    private lazy var packageChecker: PackageUpdateChecker? = {
        guard let uvPath = UVLocator().locate() else { return nil }
        return PackageUpdateChecker(uvPath: uvPath, runner: ProcessCommandRunner())
    }()

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

        serverCoordinator.autoRestartEnabled = settings.autoRestartEnabled

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
                self.statusBarController.updateLogLine(LogLineStripper.strip(line, event: event))
            }
        }

        serverCoordinator.onProcessExit = { [weak self] in
            guard let self else { return }
            self.stopRAMPolling()
            self.stopGateway()
            self.resetSession()
        }

        serverCoordinator.onAutoRestart = { [weak self] in
            guard let self else { return }
            self.stopRAMPolling()
        }

        serverCoordinator.onRestartExhausted = { [weak self] in
            guard let self else { return }
            self.postRestartExhaustedNotification()
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
        bootstrapEnvironmentIfNeeded(presets: presets)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        scheduleUpdateCheck()
    }

    // MARK: - Environment bootstrap

    private func bootstrapEnvironmentIfNeeded(presets: [ServerConfig]) {
        guard !settings.hasPythonPathOverride else { return }
        let checker = EnvironmentChecker()
        let backendsNeeded = Set(presets.map(\.serverType))
        let missing = backendsNeeded.filter { !checker.isReady(pythonPath: EnvironmentInstaller.pythonPath(for: $0)) }
        guard let first = missing.first else { return }
        statusBarController.environmentInstallStarted()
        let inst = EnvironmentInstaller(backend: first)
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
        guard let found = scanner.inspectAnyServer() else { return }
        do {
            try serverCoordinator.adoptProcess(server: found)
        } catch {
            logger.info("adoptProcess skipped: \(error) — app likely owns the process")
        }
        if let routing = ManagedGatewayRouting.recovered(server: found, presets: presets, settings: settings) {
            do {
                try startGateway(routing: routing)
            } catch {
                logger.error("recover gateway failed: \(error)")
                serverCoordinator.stop()
                return
            }
        }
        loadHistoricalLog()
        statusBarController.serverDidStart(server: found)
        if settings.ramGraphEnabled {
            startRAMPolling(pid: found.pid)
        }
    }

    // MARK: - Server lifecycle

    private func startServer(config: ServerConfig) {
        if settings.restartNeeded {
            settings.restartNeeded = false
            saveSettings(settings)
            statusBarController.applySettings(settings)
            notificationTimer?.invalidate()
            notificationTimer = nil
        }
        let resolvedConfig = config.withPythonPath(settings.resolvedPythonPath(for: config))
        let launchPlan = ServerLaunchPlan.plan(for: resolvedConfig, settings: settings)
        do {
            switch launchPlan {
            case let .direct(directConfig):
                try serverCoordinator.start(config: directConfig)
                statusBarController.serverDidStart()

            case let .managed(routing):
                try serverCoordinator.start(config: routing.backendConfig)
                try startGateway(routing: routing)
                statusBarController.serverDidStart(server: managedServerDescription(for: routing))
            }

            loadHistoricalLog()
            if settings.ramGraphEnabled, let pid = serverCoordinator.pid {
                startRAMPolling(pid: pid)
            }
        } catch {
            stopGateway()
            serverCoordinator.stop()
            statusBarController.serverDidStop()
            resetSession()
            logger.warning("startServer failed: \(error)")
        }
    }

    private func stopServer() {
        stopRAMPolling()
        stopGateway()
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

    // MARK: - Gateway

    private func startGateway(routing: ManagedGatewayRouting) throws {
        let gateway = gatewayServer ?? ManagedGatewayServer()
        gateway.onError = { [weak self] error in
            self?.handleGatewayFailure(error)
        }
        try gateway.start(routing: routing)
        gatewayServer = gateway
    }

    private func stopGateway() {
        gatewayServer?.stop()
    }

    private func handleGatewayFailure(_ error: Error) {
        logger.error("gateway failed: \(error)")
        stopRAMPolling()
        stopGateway()
        serverCoordinator.stop()
        statusBarController.serverDidStop()
        resetSession()
    }

    private func managedServerDescription(for routing: ManagedGatewayRouting) -> DiscoveredServer {
        DiscoveredServer(
            pid: serverCoordinator.pid ?? 0,
            command: routing.backendConfig.pythonPath,
            arguments: [
                "-m", routing.backendConfig.serverType.serverEntryName,
                "--model", routing.activeModel,
                "--port", String(routing.publicPort)
            ],
            serverType: routing.backendConfig.serverType,
            model: routing.activeModel,
            port: routing.publicPort
        )
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

    private func postRestartExhaustedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "MLX Server Stopped"
        content.body = "Server crashed 3 times in 3 minutes. Automatic restart disabled."
        let request = UNNotificationRequest(identifier: "restart-exhausted", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { logger.error("notification failed: \(error)") }
        }
    }

    private func showSettings(presets: [ServerConfig]) {
        if settingsWindowController == nil {
            let swc = SettingsWindowController(presets: presets, settings: settings)
            settingsWindowController = swc

            // onChange fires on every keystroke — only persist settings, don't rebuild the controller
            swc.onChange = { [weak self] _, newSettings in
                guard let self else { return }
                self.settings = newSettings
                self.saveSettings(newSettings)
                self.serverCoordinator.autoRestartEnabled = newSettings.autoRestartEnabled
            }
            swc.onDismiss = { [weak self] newPresets, newSettings, cancelled in
                guard let self else { return }
                self.settings = newSettings
                self.saveSettings(newSettings)
                self.statusBarController.applySettings(newSettings)
                self.statusBarController.updatePresets(newPresets)
                self.scheduleUpdateCheck()
                self.settingsWindowController = nil
            }
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

    // MARK: - Package updates

    private func scheduleUpdateCheck() {
        updateTimer?.invalidate()
        updateTimer = nil

        let action = UpdateScheduler.evaluate(
            interval: settings.updateCheckInterval,
            lastCheck: settings.lastUpdateCheck,
            now: Date()
        )

        switch action {
        case .checkNow:
            performUpdateCheck()
        case .scheduleAfter(let delay):
            updateTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.performUpdateCheck()
            }
        case .disabled:
            break
        }
    }

    private func performUpdateCheck() {
        guard let checker = packageChecker else { return }

        DispatchQueue.global(qos: .utility).async {
            checker.checkForUpdates { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.settings.lastUpdateCheck = Date()
                    self.saveSettings(self.settings)

                    if result.hasUpdates {
                        DispatchQueue.global(qos: .utility).async {
                            checker.upgrade { [weak self] success in
                                DispatchQueue.main.async {
                                    guard let self else { return }
                                    if success && self.serverCoordinator.isRunning {
                                        self.settings.restartNeeded = true
                                        self.saveSettings(self.settings)
                                        self.statusBarController.applySettings(self.settings)
                                        self.postRestartNotification()
                                        self.startNotificationTimer()
                                    }
                                    self.scheduleUpdateCheck()
                                }
                            }
                        }
                    } else {
                        self.scheduleUpdateCheck()
                    }
                }
            }
        }
    }

    private func postRestartNotification() {
        let content = UNMutableNotificationContent()
        content.title = "MLX Manager"
        content.body = "MLX packages updated — restart server to apply"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "package-update-restart",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func startNotificationTimer() {
        notificationTimer?.invalidate()
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2 * 3600, repeats: true) { [weak self] _ in
            guard let self, self.settings.restartNeeded else {
                self?.notificationTimer?.invalidate()
                self?.notificationTimer = nil
                return
            }
            self.postRestartNotification()
        }
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
