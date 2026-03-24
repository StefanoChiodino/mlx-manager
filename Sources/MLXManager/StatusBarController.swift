import Foundation

/// A menu item descriptor (AppKit-free).
public struct StatusBarMenuItem {
    public let title: String
    public let isEnabled: Bool
    public let isSeparator: Bool
    public let action: (() -> Void)?

    public init(title: String, isEnabled: Bool = true, isSeparator: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.isEnabled = isEnabled
        self.isSeparator = isSeparator
        self.action = action
    }
}

/// Abstraction over the status bar UI for testability.
public protocol StatusBarViewProtocol: AnyObject {
    func updateState(_ state: StatusBarDisplayState)
    func buildMenu(items: [StatusBarMenuItem])
    func showRAMGraphView(samples: [RAMSample])
    func closeRAMGraphView()
    func showHistoryView(records: [RequestRecord])
    func closeHistoryView()
    func showLogView(lines: [(String, LogLineKind)])
    func updateLogLine(_ line: String?)
}

/// Manages the menu bar icon state and menu, driven by ServerState.
public final class StatusBarController {
    private let view: StatusBarViewProtocol
    private var presets: [ServerConfig]
    private let onStart: (ServerConfig) -> Void
    private let onStop: () -> Void
    private let fileExists: (String) -> Bool
    private var currentSettings: AppSettings
    private var installingEnvironment = false
    private var lastDisplayState: StatusBarDisplayState = .offline

    private var isServerRunning: Bool {
        switch lastDisplayState {
        case .idle, .processing:
            return true
        case .offline, .failed:
            return false
        }
    }

    // Callbacks for window actions — set by AppDelegate
    public var onShowLog: (() -> Void)?
    public var onShowHistory: (() -> Void)?
    public var onShowRAMGraph: (() -> Void)?
    public var onShowSettings: (() -> Void)?

    public init(
        view: StatusBarViewProtocol,
        presets: [ServerConfig],
        onStart: @escaping (ServerConfig) -> Void,
        onStop: @escaping () -> Void,
        settings: AppSettings = AppSettings(),
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.view = view
        self.presets = presets
        self.onStart = onStart
        self.onStop = onStop
        self.fileExists = fileExists
        self.currentSettings = settings
        lastDisplayState = .offline
        view.updateState(.offline)
        rebuildMenu(statusText: "Server: Offline")
    }

    /// Called when the server process has started.
    public func serverDidStart() {
        lastDisplayState = .idle
        view.updateState(.idle)
        rebuildMenu(statusText: "Server: Idle")
    }

    /// Called when the server process has stopped.
    public func serverDidStop() {
        lastDisplayState = .offline
        view.updateState(.offline)
        rebuildMenu(statusText: "Server: Offline")
    }

    /// Update the icon and status text based on current ServerState.
    public func update(state: ServerState) {
        switch state.status {
        case .offline:
            lastDisplayState = .offline
            view.updateState(.offline)
            rebuildMenu(statusText: "Server: Offline")
        case .idle:
            lastDisplayState = .idle
            view.updateState(.idle)
            rebuildMenu(statusText: "Server: Idle")
        case .processing:
            if let progress = state.progress {
                let fraction = Double(progress.current) / Double(progress.total)
                let threshold = currentSettings.progressCompletionThreshold
                if threshold > 0 && fraction >= Double(threshold) / 100.0 {
                    lastDisplayState = .idle
                    view.updateState(.idle)
                    rebuildMenu(statusText: "Server: Idle")
                } else {
                    lastDisplayState = .processing(fraction: fraction)
                    view.updateState(.processing(fraction: fraction))
                    let pct = Int((fraction * 100).rounded())
                    let currentFmt = formatTokens(progress.current)
                    let totalFmt = formatTokens(progress.total)
                    rebuildMenu(statusText: "\(currentFmt) / \(totalFmt)  (\(pct)%)")
                }
            }
        case .failed:
            lastDisplayState = .failed
            view.updateState(.failed)
            rebuildMenu(statusText: "Server: Crashed")
        }
    }

    /// Called when background environment installation begins.
    public func environmentInstallStarted() {
        installingEnvironment = true
        rebuildMenu(statusText: "Server: Offline")
    }

    /// Called when background environment installation completes (success or failure).
    public func environmentInstallFinished() {
        installingEnvironment = false
        rebuildMenu(statusText: statusText(for: lastDisplayState))
    }

    /// Replace the stored presets and rebuild the menu.
    public func updatePresets(_ newPresets: [ServerConfig]) {
        presets = newPresets
        rebuildMenu(statusText: statusText(for: lastDisplayState))
    }

    /// Update app settings and rebuild menu (e.g. after settings saved).
    public func applySettings(_ settings: AppSettings) {
        currentSettings = settings
        rebuildMenu(statusText: statusText(for: lastDisplayState))
    }

    /// Select a preset by index — triggers onStart.
    public func selectPreset(at index: Int) {
        guard index >= 0, index < presets.count else { return }
        onStart(presets[index])
    }

    /// Trigger the stop action.
    public func stopServer() {
        onStop()
    }

    // MARK: - Private

    private func formatTokens(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func statusText(for displayState: StatusBarDisplayState) -> String {
        switch displayState {
        case .offline:
            return "Server: Offline"
        case .idle, .processing:
            return "Server: Idle"
        case .failed:
            return "Server: Crashed"
        }
    }

    private func rebuildMenu(statusText: String) {
        var items: [StatusBarMenuItem] = []

        // Status text (non-clickable)
        items.append(StatusBarMenuItem(title: statusText, isEnabled: false))
        items.append(StatusBarMenuItem(title: "-", isSeparator: true))

        if installingEnvironment {
            items.append(StatusBarMenuItem(title: "Installing environment…", isEnabled: false))
        } else {
            // Preset section header
            let presetHeader = isServerRunning ? "Switch to:" : "Start with:"
            items.append(StatusBarMenuItem(title: presetHeader, isEnabled: false))

            // Preset items
            for (i, preset) in presets.enumerated() {
                let idx = i
                let envReady = fileExists(preset.pythonPath)
                let title = envReady ? preset.name : "\(preset.name)  (env missing)"
                let enabled = !isServerRunning && envReady
                items.append(StatusBarMenuItem(
                    title: title,
                    isEnabled: enabled,
                    action: enabled ? { [weak self] in self?.selectPreset(at: idx) } : nil
                ))
            }
        }

        if isServerRunning {
            items.append(StatusBarMenuItem(title: "-", isSeparator: true))
            items.append(StatusBarMenuItem(
                title: "Stop",
                isEnabled: true,
                action: { [weak self] in self?.stopServer() }
            ))
        }

        items.append(StatusBarMenuItem(title: "-", isSeparator: true))

        items.append(StatusBarMenuItem(title: "Show Log", action: { [weak self] in self?.onShowLog?() }))
        items.append(StatusBarMenuItem(title: "Request History", action: { [weak self] in self?.onShowHistory?() }))

        if currentSettings.ramGraphEnabled {
            items.append(StatusBarMenuItem(title: "RAM Graph", action: { [weak self] in self?.onShowRAMGraph?() }))
        }

        items.append(StatusBarMenuItem(title: "-", isSeparator: true))
        items.append(StatusBarMenuItem(title: "Settings…", action: { [weak self] in self?.onShowSettings?() }))
        items.append(StatusBarMenuItem(title: "-", isSeparator: true))
        items.append(StatusBarMenuItem(title: "Quit", action: nil))

        view.buildMenu(items: items)
    }

    public func showRAMGraphView(samples: [RAMSample]) {
        view.showRAMGraphView(samples: samples)
    }

    public func closeRAMGraphView() {
        view.closeRAMGraphView()
    }

    public func showHistoryView(records: [RequestRecord]) {
        view.showHistoryView(records: records)
    }

    public func closeHistoryView() {
        view.closeHistoryView()
    }

    public func showLogView(lines: [(String, LogLineKind)]) {
        view.showLogView(lines: lines)
    }

    public func updateLogLine(_ line: String?) {
        view.updateLogLine(line)
    }
}
