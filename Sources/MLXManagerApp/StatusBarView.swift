import AppKit
import MLXManager

/// AppKit implementation of StatusBarViewProtocol using NSStatusItem.
final class StatusBarView: StatusBarViewProtocol {
    private let statusItem: NSStatusItem
    private var menuItemActions: [Int: () -> Void] = [:]

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func updateTitle(_ title: String) {
        statusItem.button?.title = title
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

            let menuItem = NSMenuItem(title: item.title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = index
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)

            if let action = item.action {
                menuItemActions[index] = action
            }
        }

        statusItem.menu = menu
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        menuItemActions[sender.tag]?()
    }
}
