import AppKit
import MLXManager

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var serverManager: ServerManager!
    private var logTailer: LogTailer?
    private var serverState = ServerState()

    private let logPath = NSString("~/repos/mlx/Logs/server.log").expandingTildeInPath

    func applicationDidFinishLaunching(_ notification: Notification) {
        let presets = loadPresets()
        serverManager = ServerManager(launcher: RealProcessLauncher())
        serverManager.onExit = { [weak self] in self?.handleProcessExit() }

        let view = StatusBarView()
        statusBarController = StatusBarController(
            view: view,
            presets: presets,
            onStart: { [weak self] config in self?.startServer(config: config) },
            onStop: { [weak self] in self?.stopServer() }
        )
    }

    private func loadPresets() -> [ServerConfig] {
        guard let url = Bundle.module.url(forResource: "presets", withExtension: "yaml"),
              let yaml = try? String(contentsOf: url, encoding: .utf8),
              let presets = try? ConfigLoader.load(yaml: yaml) else {
            return []
        }
        return presets
    }

    private func startServer(config: ServerConfig) {
        do {
            try serverManager.start(config: config)
            serverState = ServerState()
            serverState.serverStarted()
            statusBarController.serverDidStart()
            startTailing()
        } catch {
            // Already running — ignore
        }
    }

    private func stopServer() {
        logTailer?.stop()
        logTailer = nil
        serverManager.stop()
        serverState.serverStopped()
        statusBarController.serverDidStop()
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
        serverState.handle(event)
        statusBarController.update(state: serverState)
    }

    private func handleProcessExit() {
        logTailer?.stop()
        logTailer = nil
        serverState.serverStopped()
        statusBarController.serverDidStop()
    }
}
