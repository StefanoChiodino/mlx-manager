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

    public init(
        view: StatusBarViewProtocol,
        presets: [ServerConfig],
        onStart: @escaping (ServerConfig) -> Void,
        onStop: @escaping () -> Void
    ) {
        self.view = view
        self.presets = presets
        self.onStart = onStart
        self.onStop = onStop
        view.updateTitle("○")
        rebuildMenu()
    }

    /// Called when the server process has started.
    public func serverDidStart() {
        running = true
        view.updateTitle("●")
        rebuildMenu()
    }

    /// Called when the server process has stopped.
    public func serverDidStop() {
        running = false
        view.updateTitle("○")
        rebuildMenu()
    }

    /// Update the icon based on current ServerState.
    public func update(state: ServerState) {
        switch state.status {
        case .offline:
            view.updateTitle("○")
        case .idle:
            view.updateTitle("●")
        case .processing:
            if let progress = state.progress {
                let fraction = Double(progress.current) / Double(progress.total)
                view.updateTitle(progressBar(fraction: fraction))
            }
        }
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

    private func progressBar(fraction: Double, width: Int = 10) -> String {
        let filled = Int((fraction * Double(width)).rounded(.up))
        let clamped = min(max(filled, 0), width)
        return String(repeating: "▓", count: clamped) + String(repeating: "░", count: width - clamped)
    }

    private func rebuildMenu() {
        var items: [StatusBarMenuItem] = []

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

        items.append(StatusBarMenuItem(
            title: "Quit",
            action: nil
        ))

        view.buildMenu(items: items)
    }
}
