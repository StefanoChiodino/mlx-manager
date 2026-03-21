import AppKit
import MLXManager

final class LogWindowController: NSWindowController {

    private let textView: NSTextView
    private let scrollView: NSScrollView

    init() {
        scrollView = NSScrollView()
        textView = NSTextView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MLX Server Log"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearLog))
        clearButton.bezelStyle = .rounded

        let toolbar = NSView()
        toolbar.addSubview(clearButton)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clearButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        ])

        let container = NSView()
        container.addSubview(scrollView)
        container.addSubview(toolbar)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 36),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
        ])

        window.contentView = container
        container.frame = window.contentView?.bounds ?? .zero
        container.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }

    func append(line: String, kind: LogLineKind) {
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
        let attributed = NSAttributedString(string: line + "\n", attributes: attrs)

        let storage = textView.textStorage!
        storage.append(attributed)

        // Cap at 10,000 lines by removing from start
        let full = storage.string as NSString
        let lineCount = full.components(separatedBy: "\n").count
        if lineCount > 10_001 {
            let firstNewline = full.range(of: "\n")
            if firstNewline.location != NSNotFound {
                storage.deleteCharacters(in: NSRange(location: 0, length: firstNewline.location + 1))
            }
        }

        // Auto-scroll if near bottom
        if let scroller = scrollView.verticalScroller, scroller.floatValue >= 0.99 {
            textView.scrollToEndOfDocument(nil)
        }
    }

    func clear() {
        textView.string = ""
    }

    @objc private func clearLog() {
        clear()
    }
}
