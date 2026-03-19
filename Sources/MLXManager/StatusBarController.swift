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
    func updateTitle(_ title: String)
    func buildMenu(items: [StatusBarMenuItem])
}

/// Manages the menu bar icon state and menu, driven by ServerState.
public final class StatusBarController {
    private let view: StatusBarViewProtocol
    private let presets: [ServerConfig]
    private let onStart: (ServerConfig) -> Void
    private let onStop: () -> Void
    private var running = false
    private var currentSettings: AppSettings

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
        settings: AppSettings = AppSettings()
    ) {
        self.view = view
        self.presets = presets
        self.onStart = onStart
        self.onStop = onStop
        self.currentSettings = settings
        view.updateTitle("○")
        rebuildMenu(statusText: "Server: Offline")
    }

    /// Called when the server process has started.
    public func serverDidStart() {
        running = true
        view.updateTitle("●")
        rebuildMenu(statusText: "Server: Idle")
    }

    /// Called when the server process has stopped.
    public func serverDidStop() {
        running = false
        view.updateTitle("○")
        rebuildMenu(statusText: "Server: Offline")
    }

    /// Update the icon and status text based on current ServerState.
    public func update(state: ServerState, settings: AppSettings = AppSettings()) {
        currentSettings = settings
        switch state.status {
        case .offline:
            view.updateTitle("○")
            rebuildMenu(statusText: "Server: Offline")
        case .idle:
            view.updateTitle("●")
            rebuildMenu(statusText: "Server: Idle")
        case .processing:
            if let progress = state.progress {
                let fraction = Double(progress.current) / Double(progress.total)
                view.updateTitle(progressTitle(fraction: fraction, settings: settings))
                let pct = Int((fraction * 100).rounded())
                let currentFmt = formatTokens(progress.current)
                let totalFmt = formatTokens(progress.total)
                rebuildMenu(statusText: "\(currentFmt) / \(totalFmt)  (\(pct)%)")
            }
        }
    }

    /// Update app settings and rebuild menu (e.g. after settings saved).
    public func applySettings(_ settings: AppSettings) {
        currentSettings = settings
        // Rebuild with last known status text — simplest approach for now
        rebuildMenu(statusText: running ? "Server: Idle" : "Server: Offline")
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

    private func progressTitle(fraction: Double, settings: AppSettings) -> String {
        switch settings.progressStyle {
        case .bar:
            let bar = progressBar(fraction: fraction)
            let pct = Int((fraction * 100).rounded())
            return "\(bar) \(pct)%"
        case .pie:
            return pieGlyph(fraction: fraction)
        }
    }

    private func progressBar(fraction: Double, width: Int = 10) -> String {
        let filled = Int((fraction * Double(width)).rounded(.up))
        let clamped = min(max(filled, 0), width)
        return String(repeating: "▓", count: clamped) + String(repeating: "░", count: width - clamped)
    }

    private func pieGlyph(fraction: Double) -> String {
        switch fraction {
        case ..<0.2:  return "○"
        case ..<0.4:  return "◔"
        case ..<0.6:  return "◑"
        case ..<0.8:  return "◕"
        default:      return "●"
        }
    }

    private func formatTokens(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func rebuildMenu(statusText: String) {
        var items: [StatusBarMenuItem] = []

        // Status text (non-clickable)
        items.append(StatusBarMenuItem(title: statusText, isEnabled: false))
        items.append(StatusBarMenuItem(title: "-", isSeparator: true))

        // Preset section header
        let presetHeader = running ? "Switch to:" : "Start with:"
        items.append(StatusBarMenuItem(title: presetHeader, isEnabled: false))

        // Preset items
        for (i, preset) in presets.enumerated() {
            let idx = i
            items.append(StatusBarMenuItem(
                title: preset.name,
                isEnabled: !running,
                action: { [weak self] in self?.selectPreset(at: idx) }
            ))
        }

        items.append(StatusBarMenuItem(title: "-", isSeparator: true))

        items.append(StatusBarMenuItem(
            title: "Stop",
            isEnabled: running,
            action: { [weak self] in self?.stopServer() }
        ))

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
}
