import AppKit
import MLXManager

final class LogPopoverView: NSView {

    private let textView: NSTextView
    private let scrollView: NSScrollView

    init(lines: [(String, LogLineKind)]) {
        scrollView = NSScrollView()
        textView = NSTextView()
        super.init(frame: NSRect(x: 0, y: 0, width: 500, height: 400))

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        renderLines(lines)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func renderLines(_ lines: [(String, LogLineKind)]) {
        let storage = textView.textStorage!
        for (line, kind) in lines {
            let colour: NSColor
            switch kind {
            case .progress:       colour = NSColor.labelColor
            case .kvCaches:       colour = NSColor.systemBlue
            case .httpCompletion: colour = NSColor.systemGreen
            case .warning:        colour = NSColor.systemOrange
            case .other:          colour = NSColor.labelColor
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: colour,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ]
            storage.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }
        textView.scrollToEndOfDocument(nil)
    }
}
