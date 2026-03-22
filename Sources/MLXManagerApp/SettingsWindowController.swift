import AppKit
import MLXManager

final class SettingsWindowController: NSWindowController {

    var onSave: (([ServerConfig], AppSettings) -> Void)?

    private var draftPresets: [ServerConfig] = []
    private var draftSettings: AppSettings = AppSettings()

    // MARK: - List (master)
    private let presetListTable = NSTableView()
    private let listScrollView = NSScrollView()

    // MARK: - Detail form fields
    private let detailName         = NSTextField()
    private let detailPythonPath   = NSTextField()
    private let detailModel        = NSTextField()
    private let detailServerType   = NSPopUpButton()
    private let detailPort         = NSTextField()
    private let detailMaxTokens    = NSTextField()
    private let detailPrefill      = NSTextField()
    private let detailCacheSize    = NSTextField()
    private let detailCacheBytes   = NSTextField()
    private let detailExtraArgs    = NSTextField()
    private let detailTrustRemote  = NSButton(checkboxWithTitle: "Trust Remote Code", target: nil, action: nil)
    private let detailEnableThinking = NSButton(checkboxWithTitle: "Enable Thinking", target: nil, action: nil)

    // MARK: - General tab
    private let ramGraphCheckbox = NSButton(checkboxWithTitle: "Enable RAM graph", target: nil, action: nil)
    private let ramPollPopup = NSPopUpButton()
    private let startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
    private let completionThresholdField = NSTextField()

    // MARK: - Environment installer
    private let installerOutput = NSTextView()
    private var installer: EnvironmentInstaller?

    init(presets: [ServerConfig], settings: AppSettings) {
        self.draftPresets = presets
        self.draftSettings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MLX Manager Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildUI(in: window)
        presetListTable.reloadData()
        populateDetail(row: presetListTable.selectedRow)
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

    // MARK: - Presets tab

    private func buildPresetsView() -> NSView {
        let container = NSView()

        // — Master list —
        presetListTable.dataSource = self
        presetListTable.delegate = self
        presetListTable.usesAlternatingRowBackgroundColors = true
        presetListTable.rowHeight = 22
        presetListTable.allowsEmptySelection = true

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("listName"))
        nameCol.title = "Name"
        nameCol.width = 130
        nameCol.isEditable = false

        let modelCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("listModel"))
        modelCol.title = "Model"
        modelCol.width = 130
        modelCol.isEditable = false

        presetListTable.addTableColumn(nameCol)
        presetListTable.addTableColumn(modelCol)
        presetListTable.headerView = NSTableHeaderView()

        listScrollView.documentView = presetListTable
        listScrollView.hasVerticalScroller = true
        listScrollView.autohidesScrollers = true
        listScrollView.borderType = .bezelBorder

        // — Add / Remove buttons —
        let addButton = NSButton(title: "+", target: self, action: #selector(addPreset))
        addButton.bezelStyle = .rounded

        let removeButton = NSButton(title: "−", target: self, action: #selector(removePreset))
        removeButton.bezelStyle = .rounded

        let rowButtons = NSStackView(views: [addButton, removeButton])
        rowButtons.orientation = .horizontal
        rowButtons.spacing = 4

        // — Detail form —
        let detailFields: [(String, Any)] = [
            ("Name:",        detailName),
            ("Python Path:", detailPythonPath),
            ("Model:",       detailModel),
            ("Server Type:", detailServerType),
            ("Port:",        detailPort),
            ("Context:",     detailMaxTokens),
            ("Prefill:",     detailPrefill),
            ("Cache Size:",  detailCacheSize),
            ("Cache Bytes:", detailCacheBytes),
            ("Extra Args:",  detailExtraArgs),
        ]

        for (_, field) in detailFields {
            if let textField = field as? NSTextField {
                textField.isEditable = true
                textField.target = self
                textField.action = #selector(detailFieldChanged(_:))
            } else if let popup = field as? NSPopUpButton {
                popup.target = self
                popup.action = #selector(detailFieldChanged(_:))
                // Populate server type options
                popup.addItems(withTitles: ServerType.allCases.map { $0.descriptiveName })
                popup.isEnabled = false
            }
        }
        detailTrustRemote.target = self
        detailTrustRemote.action = #selector(detailCheckboxChanged(_:))
        detailEnableThinking.target = self
        detailEnableThinking.action = #selector(detailCheckboxChanged(_:))

        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        for (label, field) in detailFields {
            let lbl = NSTextField(labelWithString: label)
            lbl.alignment = .right
            if let textField = field as? NSTextField {
                grid.addRow(with: [lbl, textField])
            } else if let popup = field as? NSPopUpButton {
                grid.addRow(with: [lbl, popup])
            }
        }
        grid.addRow(with: [NSView(), detailTrustRemote])
        grid.addRow(with: [NSView(), detailEnableThinking])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 90

        // — Environment box —
        let envBox = NSBox()
        envBox.title = "Set Up Environment"
        envBox.titlePosition = .atTop

        let envLabel = NSTextField(string: "Default python: \(EnvironmentInstaller.pythonPath)")
        envLabel.isEditable = false
        envLabel.isBordered = false
        envLabel.drawsBackground = false
        envLabel.isSelectable = true
        envLabel.font = NSFont.systemFont(ofSize: 11)
        envLabel.lineBreakMode = .byTruncatingMiddle

        let installButton = NSButton(title: "Install / Reinstall mlx-lm",
                                     target: self, action: #selector(installEnvironment))
        installButton.bezelStyle = .rounded

        let outputScrollView = NSScrollView()
        installerOutput.isEditable = false
        installerOutput.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        installerOutput.backgroundColor = NSColor.textBackgroundColor
        outputScrollView.documentView = installerOutput
        outputScrollView.hasVerticalScroller = true
        outputScrollView.borderType = .bezelBorder

        let envTopRow = NSStackView(views: [envLabel, installButton])
        envTopRow.orientation = .horizontal
        envTopRow.spacing = 8

        let envStack = NSStackView(views: [envTopRow, outputScrollView])
        envStack.orientation = .vertical
        envStack.alignment = .leading
        envStack.spacing = 6
        envStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        outputScrollView.heightAnchor.constraint(equalToConstant: 50).isActive = true
        outputScrollView.widthAnchor.constraint(equalTo: envStack.widthAnchor, constant: -16).isActive = true

        envBox.contentView = envStack

        // — Layout —
        container.addSubview(listScrollView)
        container.addSubview(rowButtons)
        container.addSubview(grid)
        container.addSubview(envBox)

        listScrollView.translatesAutoresizingMaskIntoConstraints = false
        rowButtons.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        envBox.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // list on the left
            listScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listScrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            listScrollView.widthAnchor.constraint(equalToConstant: 270),
            listScrollView.bottomAnchor.constraint(equalTo: rowButtons.topAnchor, constant: -4),

            rowButtons.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rowButtons.bottomAnchor.constraint(equalTo: envBox.topAnchor, constant: -8),

            // detail form on the right
            grid.leadingAnchor.constraint(equalTo: listScrollView.trailingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),

            // env box full width at the bottom
            envBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            envBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            envBox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            envBox.heightAnchor.constraint(equalToConstant: 100),
        ])

        return container
    }

    // MARK: - Detail form population

    private func populateDetail(row: Int) {
        let hasSelection = row >= 0 && row < draftPresets.count
        let textFields: [NSTextField] = [
            detailName, detailPythonPath, detailModel, detailPort,
            detailMaxTokens, detailPrefill, detailCacheSize, detailCacheBytes, detailExtraArgs
        ]
        for f in textFields { f.isEnabled = hasSelection }
        detailServerType.isEnabled = hasSelection
        detailTrustRemote.isEnabled = hasSelection
        detailEnableThinking.isEnabled = hasSelection

        guard hasSelection else {
            for f in textFields { f.stringValue = "" }
            detailServerType.selectItem(at: 0)
            detailTrustRemote.state = .off
            detailEnableThinking.state = .off
            return
        }

        let p = draftPresets[row]
        detailName.stringValue         = p.name
        detailPythonPath.stringValue   = p.pythonPath
        detailModel.stringValue        = p.model
        detailServerType.selectItem(withTag: p.serverType.rawValue.hash)
        detailPort.stringValue         = String(p.port)
        detailMaxTokens.stringValue    = String(p.maxTokens)
        detailPrefill.stringValue      = String(p.prefillStepSize)
        detailCacheSize.stringValue    = String(p.promptCacheSize)
        detailCacheBytes.stringValue   = String(p.promptCacheBytes)
        detailExtraArgs.stringValue    = p.extraArgs.joined(separator: " ")
        detailTrustRemote.state        = p.trustRemoteCode ? .on : .off
        detailEnableThinking.state     = p.enableThinking ? .on : .off
    }

    private func applyDetail() {
        let row = presetListTable.selectedRow
        guard row >= 0, row < draftPresets.count else { return }
        let p = draftPresets[row]

        // Get server type from popup menu
        let serverTypeIndex = detailServerType.indexOfSelectedItem
        let serverType: ServerType
        if serverTypeIndex >= 0 && serverTypeIndex < ServerType.allCases.count {
            serverType = ServerType.allCases[serverTypeIndex]
        } else {
            serverType = p.serverType
        }

        draftPresets[row] = ServerConfig(
            name:             detailName.stringValue.isEmpty ? p.name : detailName.stringValue,
            model:            detailModel.stringValue,
            maxTokens:        Int(detailMaxTokens.stringValue) ?? p.maxTokens,
            port:             Int(detailPort.stringValue) ?? p.port,
            prefillStepSize:  Int(detailPrefill.stringValue) ?? p.prefillStepSize,
            promptCacheSize:  Int(detailCacheSize.stringValue) ?? p.promptCacheSize,
            promptCacheBytes: Int(detailCacheBytes.stringValue) ?? p.promptCacheBytes,
            trustRemoteCode:  detailTrustRemote.state == .on,
            enableThinking:   detailEnableThinking.state == .on,
            extraArgs:        detailExtraArgs.stringValue
                                .split(separator: " ").map(String.init),
            serverType:       serverType,
            pythonPath:       detailPythonPath.stringValue
        )
        presetListTable.reloadData(forRowIndexes: IndexSet(integer: row),
                                   columnIndexes: IndexSet(integersIn: 0..<presetListTable.numberOfColumns))
    }

    // MARK: - General tab

    private func buildGeneralView() -> NSView {
        ramGraphCheckbox.state = draftSettings.ramGraphEnabled ? .on : .off
        ramGraphCheckbox.target = self
        ramGraphCheckbox.action = #selector(ramGraphToggled)

        ramPollPopup.addItems(withTitles: ["2 seconds", "5 seconds", "10 seconds"])
        let pollIndex = [2, 5, 10].firstIndex(of: draftSettings.ramPollInterval) ?? 1
        ramPollPopup.selectItem(at: pollIndex)
        ramPollPopup.isEnabled = draftSettings.ramGraphEnabled

        startAtLoginCheckbox.state = draftSettings.startAtLogin ? .on : .off

        completionThresholdField.stringValue = String(draftSettings.progressCompletionThreshold)
        completionThresholdField.placeholderString = "99"
        completionThresholdField.formatter = {
            let f = NumberFormatter()
            f.minimum = 0
            f.maximum = 100
            f.allowsFloats = false
            return f
        }()

        let thresholdNote = NSTextField(wrappingLabelWithString:
            "Prompt processing logs never reach 100% — the server logs token counts, not generation. " +
            "Set a percentage to treat as done. 0 disables this and the icon stays at the last logged value."
        )
        thresholdNote.font = NSFont.systemFont(ofSize: 11)
        thresholdNote.textColor = .secondaryLabelColor

        let grid = NSGridView(numberOfColumns: 2, rows: 4)
        grid.setContentHuggingPriority(.defaultHigh, for: .vertical)

        grid.cell(atColumnIndex: 0, rowIndex: 0).contentView = NSTextField(labelWithString: "")
        grid.cell(atColumnIndex: 1, rowIndex: 0).contentView = ramGraphCheckbox

        grid.cell(atColumnIndex: 0, rowIndex: 1).contentView =
            NSTextField(labelWithString: "Poll interval:")
        grid.cell(atColumnIndex: 1, rowIndex: 1).contentView = ramPollPopup

        grid.cell(atColumnIndex: 0, rowIndex: 2).contentView = NSTextField(labelWithString: "")
        grid.cell(atColumnIndex: 1, rowIndex: 2).contentView = startAtLoginCheckbox

        grid.cell(atColumnIndex: 0, rowIndex: 3).contentView =
            NSTextField(labelWithString: "Complete at %:")
        grid.cell(atColumnIndex: 1, rowIndex: 3).contentView = completionThresholdField

        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8

        completionThresholdField.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let container = NSView()
        container.addSubview(grid)
        container.addSubview(thresholdNote)
        grid.translatesAutoresizingMaskIntoConstraints = false
        thresholdNote.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),

            thresholdNote.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            thresholdNote.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            thresholdNote.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
        ])
        return container
    }

    // MARK: - Actions

    @objc private func detailFieldChanged(_ sender: NSTextField) {
        applyDetail()
    }

    @objc private func detailCheckboxChanged(_ sender: NSButton) {
        applyDetail()
    }

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
            serverType: .mlxLM,
            pythonPath: EnvironmentInstaller.pythonPath
        ))
        presetListTable.reloadData()
        let newRow = draftPresets.count - 1
        presetListTable.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        populateDetail(row: newRow)
        detailName.window?.makeFirstResponder(detailName)
    }

    @objc private func removePreset() {
        let row = presetListTable.selectedRow
        guard row >= 0, row < draftPresets.count else { return }
        draftPresets.remove(at: row)
        presetListTable.reloadData()
        let nextRow = min(row, draftPresets.count - 1)
        if nextRow >= 0 {
            presetListTable.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        }
        populateDetail(row: presetListTable.selectedRow)
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
                                      extraArgs: $0.extraArgs, serverType: $0.serverType,
                                      pythonPath: EnvironmentInstaller.pythonPath)
                    }
                    self.presetListTable.reloadData()
                    self.populateDetail(row: self.presetListTable.selectedRow)
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
        draftSettings.ramGraphEnabled = ramGraphCheckbox.state == .on
        let intervals = [2, 5, 10]
        draftSettings.ramPollInterval = intervals[safe: ramPollPopup.indexOfSelectedItem] ?? 5
        draftSettings.progressCompletionThreshold = Int(completionThresholdField.stringValue) ?? 99

        let newStartAtLogin = startAtLoginCheckbox.state == .on
        if newStartAtLogin != draftSettings.startAtLogin {
            if newStartAtLogin { LoginItemManager.enable() } else { LoginItemManager.disable() }
        }
        draftSettings.startAtLogin = newStartAtLogin

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

        let field = NSTextField(labelWithString: {
            switch id {
            case "listName":  return preset.name
            case "listModel": return preset.model
            default:          return ""
            }
        }())
        field.font = NSFont.systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView, tv === presetListTable else { return }
        populateDetail(row: tv.selectedRow)
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
