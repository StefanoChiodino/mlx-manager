import AppKit
import MLXManager

final class SettingsWindowController: NSWindowController {

    var onSave: (([ServerConfig], AppSettings) -> Void)?

    private var draftPresets: [ServerConfig] = []
    private var draftSettings: AppSettings = AppSettings()

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let ramGraphCheckbox = NSButton(checkboxWithTitle: "Enable RAM graph", target: nil, action: nil)
    private let ramPollPopup = NSPopUpButton()
    private let startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
    private let installerOutput = NSTextView()
    private var installer: EnvironmentInstaller?

    private let portField = NSTextField()
    private let prefillStepSizeField = NSTextField()
    private let promptCacheSizeField = NSTextField()
    private let promptCacheBytesField = NSTextField()

    init(presets: [ServerConfig], settings: AppSettings) {
        self.draftPresets = presets
        self.draftSettings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MLX Manager Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildUI(in: window)
        tableView.reloadData()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build UI

    private func buildUI(in window: NSWindow) {
        let tabView = NSTabView()

        let presetsTab = NSTabViewItem(identifier: "presets")
        presetsTab.label = "Presets"
        presetsTab.view = buildPresetsView()

        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view = buildGeneralView()

        tabView.addTabViewItem(presetsTab)
        tabView.addTabViewItem(generalTab)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let buttonStack = NSStackView(views: [cancelButton, saveButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        let root = NSView()
        root.addSubview(tabView)
        root.addSubview(buttonStack)

        tabView.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            tabView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12),

            buttonStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])

        window.contentView = root
    }

    private func buildPresetsView() -> NSView {
        let container = NSView()

        // Table setup
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 22

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("name",       "Name",        90),
            ("pythonPath", "Python Path", 160),
            ("model",      "Model",       130),
            ("maxTokens",  "Context",     60),
            ("port",       "Port",        50),
            ("prefillStepSize", "Prefill", 70),
            ("promptCacheSize", "Cache Size", 80),
            ("promptCacheBytes", "Cache Bytes", 100),
            ("extraArgs",  "Extra Args",  130),
        ]
        for col in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            c.title = col.title
            c.width = col.width
            c.isEditable = true
            tableView.addTableColumn(c)
        }
        tableView.headerView = NSTableHeaderView()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let addButton = NSButton(title: "+", target: self, action: #selector(addPreset))
        addButton.bezelStyle = .rounded

        let removeButton = NSButton(title: "−", target: self, action: #selector(removePreset))
        removeButton.bezelStyle = .rounded

        let rowButtons = NSStackView(views: [addButton, removeButton])
        rowButtons.orientation = .horizontal
        rowButtons.spacing = 4

        // Environment installer section
        let envBox = NSBox()
        envBox.title = "Set Up Environment"
        envBox.titlePosition = .atTop

        let envLabel = NSTextField(labelWithString: "Default python: \(EnvironmentInstaller.pythonPath)")
        envLabel.font = NSFont.systemFont(ofSize: 11)
        envLabel.lineBreakMode = .byTruncatingMiddle

        let installButton = NSButton(title: "Install / Reinstall mlx-lm",
                                     target: self, action: #selector(installEnvironment))
        installButton.bezelStyle = .rounded
        installButton.isEnabled = true

        let outputScrollView = NSScrollView()
        installerOutput.isEditable = false
        installerOutput.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        installerOutput.backgroundColor = NSColor.textBackgroundColor
        outputScrollView.documentView = installerOutput
        outputScrollView.hasVerticalScroller = true
        outputScrollView.borderType = .bezelBorder

        let envStack = NSStackView(views: [envLabel, installButton, outputScrollView])
        envStack.orientation = .vertical
        envStack.alignment = .leading
        envStack.spacing = 6
        envStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        outputScrollView.heightAnchor.constraint(equalToConstant: 60).isActive = true
        outputScrollView.widthAnchor.constraint(equalTo: envStack.widthAnchor, constant: -16).isActive = true

        envBox.contentView = envStack

        container.addSubview(scrollView)
        container.addSubview(rowButtons)
        container.addSubview(envBox)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        rowButtons.translatesAutoresizingMaskIntoConstraints = false
        envBox.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: rowButtons.topAnchor, constant: -4),

            rowButtons.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rowButtons.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rowButtons.bottomAnchor.constraint(equalTo: envBox.topAnchor, constant: -8),

            envBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            envBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            envBox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            envBox.heightAnchor.constraint(equalToConstant: 90),
        ])

        return container
    }

    private func buildGeneralView() -> NSView {
        ramGraphCheckbox.state = draftSettings.ramGraphEnabled ? .on : .off
        ramGraphCheckbox.target = self
        ramGraphCheckbox.action = #selector(ramGraphToggled)

        ramPollPopup.addItems(withTitles: ["2 seconds", "5 seconds", "10 seconds"])
        let pollIndex = [2, 5, 10].firstIndex(of: draftSettings.ramPollInterval) ?? 1
        ramPollPopup.selectItem(at: pollIndex)
        ramPollPopup.isEnabled = draftSettings.ramGraphEnabled

        startAtLoginCheckbox.state = draftSettings.startAtLogin ? .on : .off

        let grid = NSGridView(numberOfColumns: 2, rows: 3)
        grid.setContentHuggingPriority(.defaultHigh, for: .vertical)

        grid.cell(atColumnIndex: 0, rowIndex: 0).contentView = NSTextField(labelWithString: "")
        grid.cell(atColumnIndex: 1, rowIndex: 0).contentView = ramGraphCheckbox

        grid.cell(atColumnIndex: 0, rowIndex: 1).contentView =
            NSTextField(labelWithString: "Poll interval:")
        grid.cell(atColumnIndex: 1, rowIndex: 1).contentView = ramPollPopup

        grid.cell(atColumnIndex: 0, rowIndex: 2).contentView = NSTextField(labelWithString: "")
        grid.cell(atColumnIndex: 1, rowIndex: 2).contentView = startAtLoginCheckbox

        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8

        let container = NSView()
        container.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
        ])
        return container
    }

    // MARK: - Actions

    @objc private func addPreset() {
        draftPresets.append(ServerConfig(
            name: "New Preset",
            model: "mlx-community/",
            maxTokens: 40960,
            port: 8080,
            prefillStepSize: 4096,
            promptCacheSize: 4,
            promptCacheBytes: 10 * 1024 * 1024 * 1024,
            trustRemoteCode: false,
            enableThinking: false,
            extraArgs: [],
            pythonPath: EnvironmentInstaller.pythonPath
        ))
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: draftPresets.count - 1), byExtendingSelection: false)
    }

    @objc private func removePreset() {
        let row = tableView.selectedRow
        guard row >= 0, row < draftPresets.count else { return }
        draftPresets.remove(at: row)
        tableView.reloadData()
    }

    @objc private func ramGraphToggled() {
        ramPollPopup.isEnabled = ramGraphCheckbox.state == .on
    }

    @objc private func installEnvironment() {
        installerOutput.string = ""
        let inst = EnvironmentInstaller()
        self.installer = inst
        inst.onOutput = { [weak self] text in
            self?.installerOutput.textStorage?.append(
                NSAttributedString(string: text, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                ])
            )
            self?.installerOutput.scrollToEndOfDocument(nil)
        }
        inst.onComplete = { [weak self] success in
            guard let self else { return }
            if success {
                let alert = NSAlert()
                alert.messageText = "Installation complete"
                alert.informativeText = "Update all presets to use \(EnvironmentInstaller.pythonPath)?"
                alert.addButton(withTitle: "Update Presets")
                alert.addButton(withTitle: "Leave as Is")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.draftPresets = self.draftPresets.map {
                        ServerConfig(name: $0.name, model: $0.model, maxTokens: $0.maxTokens,
                                     extraArgs: $0.extraArgs, pythonPath: EnvironmentInstaller.pythonPath)
                    }
                    self.tableView.reloadData()
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "Installation failed"
                alert.informativeText = "Check the output above for details."
                alert.runModal()
            }
        }
        inst.install()
    }

    @objc private func saveTapped() {
        // Collect general settings
        draftSettings.ramGraphEnabled = ramGraphCheckbox.state == .on
        let intervals = [2, 5, 10]
        draftSettings.ramPollInterval = intervals[safe: ramPollPopup.indexOfSelectedItem] ?? 5

        let newStartAtLogin = startAtLoginCheckbox.state == .on
        if newStartAtLogin != draftSettings.startAtLogin {
            if newStartAtLogin { LoginItemManager.enable() } else { LoginItemManager.disable() }
        }
        draftSettings.startAtLogin = newStartAtLogin

        // Persist
        try? UserPresetStore.save(draftPresets, to: UserPresetStore.defaultURL)

        onSave?(draftPresets, draftSettings)
        window?.close()
    }

    @objc private func cancelTapped() {
        window?.close()
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        draftPresets.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < draftPresets.count else { return nil }
        let preset = draftPresets[row]
        let id = tableColumn?.identifier.rawValue ?? ""

        let field = NSTextField()
        field.isEditable = true
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 12)
        field.identifier = NSUserInterfaceItemIdentifier(id)
        field.tag = row
        field.target = self
        field.action = #selector(cellEdited(_:))

        switch id {
        case "name":       field.stringValue = preset.name
        case "pythonPath": field.stringValue = preset.pythonPath
        case "model":      field.stringValue = preset.model
        case "maxTokens":  field.stringValue = String(preset.maxTokens)
        case "port":       field.stringValue = String(preset.port)
        case "prefillStepSize": field.stringValue = String(preset.prefillStepSize)
        case "promptCacheSize": field.stringValue = String(preset.promptCacheSize)
        case "promptCacheBytes": field.stringValue = String(preset.promptCacheBytes)
        case "trustRemoteCode": field.stringValue = preset.trustRemoteCode ? "✓" : " "
        case "enableThinking": field.stringValue = preset.enableThinking ? "✓" : " "
        case "extraArgs":  field.stringValue = preset.extraArgs.joined(separator: " ")
        default: break
        }
        return field
    }

    @objc private func cellEdited(_ sender: NSTextField) {
        let row = sender.tag
        guard row < draftPresets.count else { return }
        let p = draftPresets[row]
        let col = sender.identifier?.rawValue ?? ""
        let val = sender.stringValue

        switch col {
        case "name":
            draftPresets[row] = ServerConfig(name: val, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "pythonPath":
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: val)
        case "model":
            draftPresets[row] = ServerConfig(name: p.name, model: val, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "maxTokens":
            let tokens = Int(val) ?? p.maxTokens
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: tokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "port":
            let port = Int(val) ?? p.port
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "prefillStepSize":
            let prefill = Int(val) ?? p.prefillStepSize
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: prefill,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "promptCacheSize":
            let cacheSize = Int(val) ?? p.promptCacheSize
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: cacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "promptCacheBytes":
            let cacheBytes = Int(val) ?? p.promptCacheBytes
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: cacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "trustRemoteCode":
            let trust = val == "✓"
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: trust, enableThinking: p.enableThinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "enableThinking":
            let thinking = val == "✓"
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: thinking,
                                             extraArgs: p.extraArgs, pythonPath: p.pythonPath)
        case "extraArgs":
            let args = val.split(separator: " ").map(String.init)
            draftPresets[row] = ServerConfig(name: p.name, model: p.model, maxTokens: p.maxTokens,
                                             port: p.port, prefillStepSize: p.prefillStepSize,
                                             promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
                                             trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
                                             extraArgs: args, pythonPath: p.pythonPath)
        default: break
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
