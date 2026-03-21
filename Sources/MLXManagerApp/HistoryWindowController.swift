import AppKit
import MLXManager

final class HistoryWindowController: NSWindowController {

    private let chartView: HistoryChartView

    init() {
        chartView = HistoryChartView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Request History"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = chartView
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(records: [RequestRecord]) {
        chartView.records = records
        chartView.needsDisplay = true
    }
}

// MARK: -

public final class HistoryChartView: NSView {

    var records: [RequestRecord] = []

    private var trackingArea: NSTrackingArea?
    private var hoveredIndex: Int? = nil

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard !records.isEmpty else {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 13)
            ]
            let str = NSAttributedString(string: "No requests yet", attributes: attrs)
            let size = str.size()
            str.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                 y: (bounds.height - size.height) / 2))
            return
        }

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let maxTokens = records.map(\.tokens).max() ?? 1
        let maxDuration = records.map(\.duration).max() ?? 1

        let padding: CGFloat = 20
        let barWidth = max(4, (bounds.width - padding * 2) / CGFloat(records.count)) - 2
        let chartHeight = bounds.height - padding * 2

        for (i, record) in records.enumerated() {
            let x = padding + CGFloat(i) * (barWidth + 2)
            let heightFraction = CGFloat(record.tokens) / CGFloat(maxTokens)
            let barHeight = max(2, heightFraction * chartHeight)
            let y = padding

            let durationAlpha = 0.3 + 0.7 * (record.duration / maxDuration)
            let colour = NSColor.systemBlue.withAlphaComponent(durationAlpha)
            colour.setFill()

            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()

            if hoveredIndex == i {
                NSColor.selectedControlColor.withAlphaComponent(0.3).setFill()
                rect.fill()
                drawTooltip(for: record, at: NSPoint(x: x + barWidth / 2, y: y + barHeight + 4))
            }
        }
    }

    private func drawTooltip(for record: RequestRecord, at point: NSPoint) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let duration = String(format: "%.1fs", record.duration)
        let tokens = NumberFormatter.localizedString(from: NSNumber(value: record.tokens), number: .decimal)
        let text = "\(formatter.string(from: record.startedAt))\n\(duration)  •  \(tokens) tokens"

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let padding: CGFloat = 4
        let boxRect = NSRect(x: point.x - size.width / 2 - padding,
                             y: point.y,
                             width: size.width + padding * 2,
                             height: size.height + padding * 2)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3).stroke()
        str.draw(at: NSPoint(x: boxRect.minX + padding, y: boxRect.minY + padding))
    }

    public override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard !records.isEmpty else { hoveredIndex = nil; return }
        let padding: CGFloat = 20
        let barWidth = max(4, (bounds.width - padding * 2) / CGFloat(records.count))
        let idx = Int((loc.x - padding) / barWidth)
        hoveredIndex = (idx >= 0 && idx < records.count) ? idx : nil
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }
}
