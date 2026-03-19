import AppKit
import MLXManager

final class RAMGraphWindowController: NSWindowController {

    private let graphView: RAMGraphView

    init() {
        graphView = RAMGraphView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 250),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RAM Usage"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = graphView
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(samples: [RAMSample]) {
        graphView.samples = samples
        graphView.needsDisplay = true
    }
}

// MARK: -

public final class RAMGraphView: NSView {

    var samples: [RAMSample] = []

    private let totalRAMGB: Double = {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return Double(bytes) / 1_073_741_824
    }()

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let padding: CGFloat = 36
        let chartRect = NSRect(
            x: padding, y: padding,
            width: bounds.width - padding * 2,
            height: bounds.height - padding * 2
        )

        // Y axis max: total RAM, rounded up to nearest 8 GB
        let yMax = ceil(totalRAMGB / 8) * 8

        // Draw total RAM dashed line
        NSColor.systemRed.withAlphaComponent(0.4).setStroke()
        let ramY = chartRect.minY + chartRect.height * CGFloat(totalRAMGB / yMax)
        let dashPath = NSBezierPath()
        dashPath.setLineDash([4, 4], count: 2, phase: 0)
        dashPath.lineWidth = 1
        dashPath.move(to: NSPoint(x: chartRect.minX, y: ramY))
        dashPath.line(to: NSPoint(x: chartRect.maxX, y: ramY))
        dashPath.stroke()

        // Y axis label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        NSAttributedString(string: String(format: "%.0fGB", totalRAMGB), attributes: labelAttrs)
            .draw(at: NSPoint(x: 2, y: ramY - 6))

        guard samples.count >= 2 else {
            if samples.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 13)
                ]
                let str = NSAttributedString(string: "Waiting for data…", attributes: attrs)
                let size = str.size()
                str.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                     y: (bounds.height - size.height) / 2))
            }
            return
        }

        // Draw line chart
        let path = NSBezierPath()
        path.lineWidth = 1.5

        let timeMin = samples.first!.timestamp.timeIntervalSinceReferenceDate
        let timeMax = samples.last!.timestamp.timeIntervalSinceReferenceDate
        let timeRange = max(timeMax - timeMin, 1)

        for (i, sample) in samples.enumerated() {
            let t = sample.timestamp.timeIntervalSinceReferenceDate
            let x = chartRect.minX + chartRect.width * CGFloat((t - timeMin) / timeRange)
            let y = chartRect.minY + chartRect.height * CGFloat(sample.gb / yMax)
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) }
            else { path.line(to: NSPoint(x: x, y: y)) }
        }

        NSColor.systemBlue.setStroke()
        path.stroke()

        // Fill under line
        let fillPath = path.copy() as! NSBezierPath
        fillPath.line(to: NSPoint(x: chartRect.maxX, y: chartRect.minY))
        fillPath.line(to: NSPoint(x: chartRect.minX, y: chartRect.minY))
        fillPath.close()
        NSColor.systemBlue.withAlphaComponent(0.1).setFill()
        fillPath.fill()

        // Current value label
        if let last = samples.last {
            let valStr = NSAttributedString(
                string: String(format: "%.1f GB", last.gb),
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            valStr.draw(at: NSPoint(x: chartRect.maxX - 60, y: chartRect.maxY + 2))
        }
    }
}
