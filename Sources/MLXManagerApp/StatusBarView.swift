import AppKit
import MLXManager

// MARK: - ArcProgressView

/// Custom view drawn into the NSStatusItem button.
/// Shows a thick arc ring with a centred "M" in all states.
/// Offline: muted ring. Idle: green ring. Processing: progress arc overlay.
final class ArcProgressView: NSView {

    var displayState: StatusBarDisplayState = .offline {
        didSet {
            guard displayState != oldValue else { return }
            needsDisplay = true
        }
    }

    private let diameter: CGFloat = 13
    private let strokeWidth: CGFloat = 2.5
    private let mFont = NSFont.systemFont(ofSize: 8, weight: .heavy)

    override var intrinsicContentSize: NSSize {
        return NSSize(width: diameter + 4, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let arcRect = NSRect(
            x: 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        switch displayState {

        case .offline:
            // Thick ring — muted
            let inset = strokeWidth / 2
            let ringRect = arcRect.insetBy(dx: inset, dy: inset)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = strokeWidth
            NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setStroke()
            ring.stroke()

            // Centered "M" — muted
            let attrs: [NSAttributedString.Key: Any] = [
                .font: mFont,
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let str = NSAttributedString(string: "M", attributes: attrs)
            let strSize = str.size()
            let mX = arcRect.midX - strSize.width / 2
            let mY = arcRect.midY - strSize.height / 2
            str.draw(at: NSPoint(x: mX, y: mY))

        case .idle:
            // Thick ring — green
            let inset = strokeWidth / 2
            let ringRect = arcRect.insetBy(dx: inset, dy: inset)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = strokeWidth
            NSColor.systemGreen.setStroke()
            ring.stroke()

            // Centered "M"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: mFont,
                .foregroundColor: NSColor.labelColor
            ]
            let str = NSAttributedString(string: "M", attributes: attrs)
            let strSize = str.size()
            let mX = arcRect.midX - strSize.width / 2
            let mY = arcRect.midY - strSize.height / 2
            str.draw(at: NSPoint(x: mX, y: mY))

        case let .processing(fraction):
            let inset = strokeWidth / 2
            let ringCenter = NSPoint(x: arcRect.midX, y: arcRect.midY)
            let ringRadius = diameter / 2 - inset

            // Background track — dim ring
            let track = NSBezierPath(ovalIn: arcRect.insetBy(dx: inset, dy: inset))
            track.lineWidth = strokeWidth
            NSColor.tertiaryLabelColor.withAlphaComponent(0.4).setStroke()
            track.stroke()

            // Foreground arc — clockwise from 12 o'clock
            // Snap to full ring when fraction >= 0.99 since progress
            // never reaches 1.0 (completion is signalled by KV Caches / HTTP 200)
            if fraction > 0 {
                NSColor.controlAccentColor.setStroke()
                if fraction >= 0.99 {
                    let full = NSBezierPath(ovalIn: arcRect.insetBy(dx: inset, dy: inset))
                    full.lineWidth = strokeWidth
                    full.stroke()
                } else {
                    let startAngle: CGFloat = 90
                    let endAngle = startAngle - CGFloat(fraction * 360)
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: ringCenter,
                                  radius: ringRadius,
                                  startAngle: startAngle,
                                  endAngle: endAngle,
                                  clockwise: true)
                    arc.lineWidth = strokeWidth
                    arc.lineCapStyle = .round
                    arc.stroke()
                }
            }

            // Centered "M"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: mFont,
                .foregroundColor: NSColor.labelColor
            ]
            let str = NSAttributedString(string: "M", attributes: attrs)
            let strSize = str.size()
            let mX = arcRect.midX - strSize.width / 2
            let mY = arcRect.midY - strSize.height / 2
            str.draw(at: NSPoint(x: mX, y: mY))
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
