import AppKit
import MLXManager

// MARK: - ArcProgressView

/// Custom view drawn into the NSStatusItem button.
/// Shows a filled arc (clockwise from 12 o'clock) + percentage when processing,
/// a solid green circle when idle, and an outline circle when offline.
final class ArcProgressView: NSView {

    var displayState: StatusBarDisplayState = .offline {
        didSet {
            guard displayState != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let diameter: CGFloat = 13
    private let gap: CGFloat = 4
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    override var intrinsicContentSize: NSSize {
        if case .processing = displayState {
            let labelWidth = ("100%" as NSString).size(withAttributes: [.font: labelFont]).width
            return NSSize(width: diameter + gap + labelWidth + 2, height: 22)
        }
        return NSSize(width: diameter + 4, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let arcRect = NSRect(
            x: 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        let center = NSPoint(x: arcRect.midX, y: arcRect.midY)
        let radius = diameter / 2

        switch displayState {

        case .offline:
            let path = NSBezierPath(ovalIn: arcRect.insetBy(dx: 1, dy: 1))
            path.lineWidth = 1.5
            NSColor.tertiaryLabelColor.setStroke()
            path.stroke()

        case .idle:
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: arcRect).fill()

        case let .processing(fraction):
            // Background track
            let track = NSBezierPath(ovalIn: arcRect.insetBy(dx: 1, dy: 1))
            track.lineWidth = 2
            NSColor.tertiaryLabelColor.withAlphaComponent(0.4).setStroke()
            track.stroke()

            // Foreground arc — clockwise from top (90° in AppKit coords)
            if fraction > 0 {
                let startAngle: CGFloat = 90
                let endAngle = startAngle - CGFloat(fraction * 360)
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center,
                              radius: radius - 1,
                              startAngle: startAngle,
                              endAngle: endAngle,
                              clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                NSColor.controlAccentColor.setStroke()
                arc.stroke()
            }

            // Percentage label to the right of the arc
            let pct = Int((fraction * 100).rounded())
            let label = "\(pct)%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: NSColor.labelColor
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let strSize = str.size()
            let labelX = arcRect.maxX + gap
            let labelY = (bounds.height - strSize.height) / 2
            str.draw(at: NSPoint(x: labelX, y: labelY))
        }
    }
}

// MARK: - StatusBarView

/// AppKit implementation of StatusBarViewProtocol using NSStatusItem + ArcProgressView.
final class StatusBarView: StatusBarViewProtocol {
    private let statusItem: NSStatusItem
    private let arcView: ArcProgressView
    private var menuItemActions: [Int: () -> Void] = [:]

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        arcView = ArcProgressView()

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            arcView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(arcView)
            NSLayoutConstraint.activate([
                arcView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                arcView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                arcView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            ])
        }
    }

    func updateState(_ state: StatusBarDisplayState) {
        DispatchQueue.main.async { [weak self] in
            self?.arcView.displayState = state
        }
    }

    func buildMenu(items: [StatusBarMenuItem]) {
        let menu = NSMenu()
        menuItemActions.removeAll()

        for (index, item) in items.enumerated() {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }

            if item.title == "Quit" {
                let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
                menu.addItem(quit)
                continue
            }

            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            menuItem.tag = index
            menuItem.isEnabled = item.isEnabled

            // Only wire action+target when enabled — responder chain ignores isEnabled otherwise
            if item.isEnabled, let action = item.action {
                menuItem.action = #selector(menuItemClicked(_:))
                menuItem.target = self
                menuItemActions[index] = action
            }

            menu.addItem(menuItem)
        }

        statusItem.menu = menu
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        menuItemActions[sender.tag]?()
    }

    func showRAMGraphView(samples: [RAMSample]) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 200)
        popover.behavior = .transient
        
        let viewController = NSViewController()
        let graphView = RAMGraphView()
        graphView.samples = samples
        graphView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        viewController.view = graphView
        
        popover.contentViewController = viewController
        popover.show(relativeTo: statusItem.button?.bounds ?? .zero, of: statusItem.button ?? NSView(), preferredEdge: .minY)
    }

    func closeRAMGraphView() {}

    func showHistoryView(records: [RequestRecord]) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 500, height: 300)
        popover.behavior = .transient
        
        let viewController = NSViewController()
        let chartView = HistoryChartView()
        chartView.records = records
        chartView.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        viewController.view = chartView
        
        popover.contentViewController = viewController
        popover.show(relativeTo: statusItem.button?.bounds ?? .zero, of: statusItem.button ?? NSView(), preferredEdge: .minY)
    }

    func closeHistoryView() {}

    func showLogView(lines: [(String, LogLineKind)]) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 500, height: 400)
        popover.behavior = .transient

        let viewController = NSViewController()
        let logView = LogPopoverView(lines: lines)
        logView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        viewController.view = logView

        popover.contentViewController = viewController
        popover.show(relativeTo: statusItem.button?.bounds ?? .zero,
                     of: statusItem.button ?? NSView(),
                     preferredEdge: .minY)
    }
}
