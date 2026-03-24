import AppKit
import MLXManager

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onChange: (([ServerConfig], AppSettings) -> Void)?
    var onDismiss: ((_ presets: [ServerConfig], _ settings: AppSettings, _ cancelled: Bool) -> Void)?
    private var dismissed = false

    private var draftPresets: [ServerConfig] = []
    private var draftSettings: AppSettings = AppSettings()
    private var currentDetailRow: Int = -1

    // Snapshot taken at open — restored on Cancel
    private var snapshotPresets: [ServerConfig] = []
    private var snapshotSettings: AppSettings = AppSettings()

    // MARK: - List (master)
    private let presetListTable = NSTableView()
    private let listScrollView = NSScrollView()

    // MARK: - Detail form fields
    private let detailName         = NSTextField()
    private let detailPythonPath   = NSTextField()
    private let detailModel        = NSTextField()
    private let detailPort         = NSTextField()
    private let detailMaxTokens    = NSTextField()
    private let detailPrefill      = NSTextField()
    private let detailCacheSize    = NSTextField()
    private let detailCacheBytes   = NSTextField()
    private let detailExtraArgs    = NSTextField()
    private let detailTrustRemote  = NSButton(checkboxWithTitle: "Trust Remote Code", target: nil, action: nil)
    private let detailEnableThinking = NSButton(checkboxWithTitle: "Enable Thinking", target: nil, action: nil)

    // Backend selector
    private let detailBackend = NSSegmentedControl(
        labels: ["LM", "VLM"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    // mlx-vlm only fields
    private let detailKvBits           = NSTextField()
    private let detailKvGroupSize      = NSTextField()
    private let detailMaxKvSize        = NSTextField()
    private let detailQuantizedKvStart = NSTextField()

    // Swappable backend-specific stack (replaced wholesale on backend change)
    private var backendSpecificStack = NSStackView()

    // Install button (needs to be a property so we can update its title)
    private let installButton = NSButton(title: "Install / Reinstall mlx-lm",
                                         target: nil, action: nil)

    // MARK: - General tab
    private let ramGraphCheckbox = NSButton(checkboxWithTitle: "Enable RAM graph", target: nil, action: nil)
    private let ramPollPopup = NSPopUpButton()
    private let startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
    private let showLastLogLineCheckbox = NSButton(checkboxWithTitle: "Show last log line in menu bar", target: nil, action: nil)
    private let completionThresholdField = NSTextField()

    // MARK: - Environment installer
    private let installerOutput = NSTextView()
    private var installer: EnvironmentInstaller?

    init(presets: [ServerConfig], settings: AppSettings) {
        self.draftPresets = presets
        self.draftSettings = settings
        self.snapshotPresets = presets
        self.snapshotSettings = settings

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

        window.delegate = self
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

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(views: [cancelButton, closeButton])
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

        let backendCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("listBackend"))
        backendCol.title = "Backend"
        backendCol.width = 55
        backendCol.isEditable = false

        presetListTable.addTableColumn(nameCol)
        presetListTable.addTableColumn(modelCol)
        presetListTable.addTableColumn(backendCol)
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
        // Wire up all editable text fields
        for f in [detailName, detailPythonPath, detailModel, detailPort, detailPrefill, detailExtraArgs,
                  detailMaxTokens, detailCacheSize, detailCacheBytes,
                  detailKvBits, detailKvGroupSize, detailMaxKvSize, detailQuantizedKvStart] {
            f.isEditable = true
            f.target = self
            f.action = #selector(detailFieldChanged(_:))
        }
        detailTrustRemote.target = self
        detailTrustRemote.action = #selector(detailCheckboxChanged(_:))
        detailEnableThinking.target = self
        detailEnableThinking.action = #selector(detailCheckboxChanged(_:))
        detailBackend.target = self
        detailBackend.action = #selector(backendChanged)

        // Helper: build a label+field row for use in a vertical NSStackView.
        // Both views are placed in a horizontal NSStackView with a fixed-width right-aligned label.
        func formRow(_ labelText: String, _ field: NSView) -> NSStackView {
            let lbl = NSTextField(labelWithString: labelText)
            lbl.alignment = .right
            lbl.widthAnchor.constraint(equalToConstant: 90).isActive = true
            let row = NSStackView(views: [lbl, field])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            return row
        }

        // — Shared-top rows (always visible) —
        let sharedTopStack = NSStackView(views: [
            formRow("Backend:", detailBackend),
            formRow("Name:", detailName),
            formRow("Python Path:", detailPythonPath),
            formRow("Model:", detailModel),
            formRow("Port:", detailPort),
            formRow("Prefill:", detailPrefill),
        ])
        sharedTopStack.orientation = .vertical
        sharedTopStack.alignment = .leading
        sharedTopStack.spacing = 6

        // — Shared-bottom rows (always visible) —
        let sharedBottomStack = NSStackView(views: [
            formRow("Extra Args:", detailExtraArgs),
            formRow("", detailTrustRemote),
        ])
        sharedBottomStack.orientation = .vertical
        sharedBottomStack.alignment = .leading
        sharedBottomStack.spacing = 6

        // — Backend-specific block (swapped on backend change) —
        backendSpecificStack = makeLMStack()

        // — Outer detail stack —
        let detailStack = NSStackView(views: [sharedTopStack, backendSpecificStack, sharedBottomStack])
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 6

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

        installButton.target = self
        installButton.action = #selector(installEnvironment)
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

        // Wrap detail stack in a scroll view so it never overflows into the env box
        let detailScrollView = NSScrollView()
        detailScrollView.documentView = detailStack
        detailScrollView.hasVerticalScroller = true
        detailScrollView.autohidesScrollers = true
        detailScrollView.drawsBackground = false

        // The stack must be at least as wide as the scroll view's content area
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailStack.widthAnchor.constraint(equalTo: detailScrollView.contentView.widthAnchor).isActive = true

        // — Layout —
        container.addSubview(listScrollView)
        container.addSubview(rowButtons)
        container.addSubview(detailScrollView)
        container.addSubview(envBox)

        listScrollView.translatesAutoresizingMaskIntoConstraints = false
        rowButtons.translatesAutoresizingMaskIntoConstraints = false
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        envBox.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // list on the left
            listScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listScrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            listScrollView.widthAnchor.constraint(equalToConstant: 270),
            listScrollView.bottomAnchor.constraint(equalTo: rowButtons.topAnchor, constant: -4),

            rowButtons.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rowButtons.bottomAnchor.constraint(equalTo: envBox.topAnchor, constant: -8),

            // detail form on the right — constrained top and bottom so it never overlaps env box
            detailScrollView.leadingAnchor.constraint(equalTo: listScrollView.trailingAnchor, constant: 12),
            detailScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            detailScrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            detailScrollView.bottomAnchor.constraint(equalTo: envBox.topAnchor, constant: -8),

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
        currentDetailRow = row
        let hasSelection = row >= 0 && row < draftPresets.count
        let textFields: [NSTextField] = [
            detailName, detailPythonPath, detailModel, detailPort,
            detailMaxTokens, detailPrefill, detailCacheSize, detailCacheBytes, detailExtraArgs,
            detailKvBits, detailKvGroupSize, detailMaxKvSize, detailQuantizedKvStart
        ]
        for f in textFields { f.isEnabled = hasSelection }
        detailBackend.isEnabled = hasSelection
        detailTrustRemote.isEnabled = hasSelection
        detailEnableThinking.isEnabled = hasSelection

        guard hasSelection else {
            for f in textFields { f.stringValue = "" }
            detailBackend.selectedSegment = 0
            detailTrustRemote.state = .off
            detailEnableThinking.state = .off
            swapBackendSpecificStack(for: .mlxLM)
            return
        }

        let p = draftPresets[row]
        detailName.stringValue         = p.name
        detailPythonPath.stringValue   = p.pythonPath
        detailModel.stringValue        = p.model
        detailPort.stringValue         = String(p.port)
        detailMaxTokens.stringValue    = String(p.maxTokens)
        detailPrefill.stringValue      = String(p.prefillStepSize)
        detailCacheSize.stringValue    = String(p.promptCacheSize)
        detailCacheBytes.stringValue   = String(p.promptCacheBytes)
        detailExtraArgs.stringValue    = p.extraArgs.joined(separator: " ")
        detailTrustRemote.state        = p.trustRemoteCode ? .on : .off
        detailEnableThinking.state     = p.enableThinking ? .on : .off

        detailBackend.selectedSegment  = p.serverType == .mlxLM ? 0 : 1
        detailKvBits.stringValue           = String(p.kvBits)
        detailKvGroupSize.stringValue      = String(p.kvGroupSize)
        detailMaxKvSize.stringValue        = String(p.maxKvSize)
        detailQuantizedKvStart.stringValue = String(p.quantizedKvStart)
        swapBackendSpecificStack(for: p.serverType)

        installButton.title = "Install / Reinstall \(p.serverType == .mlxLM ? "mlx-lm" : "mlx-vlm")"
    }

    private func applyDetail() {
        let row = currentDetailRow
        guard row >= 0, row < draftPresets.count else { return }
        let p = draftPresets[row]

        let serverType: ServerType = detailBackend.selectedSegment == 0 ? .mlxLM : .mlxVLM

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
            kvBits:           Int(detailKvBits.stringValue) ?? p.kvBits,
            kvGroupSize:      Int(detailKvGroupSize.stringValue) ?? p.kvGroupSize,
            maxKvSize:        Int(detailMaxKvSize.stringValue) ?? p.maxKvSize,
            quantizedKvStart: Int(detailQuantizedKvStart.stringValue) ?? p.quantizedKvStart,
            pythonPath:       detailPythonPath.stringValue
        )
        presetListTable.reloadData(forRowIndexes: IndexSet(integer: row),
                                   columnIndexes: IndexSet(integersIn: 0..<presetListTable.numberOfColumns))
    }

    // MARK: - Backend picker

    @objc private func backendChanged() {
        let row = presetListTable.selectedRow
        guard row >= 0, row < draftPresets.count else { return }
        let backend: ServerType = detailBackend.selectedSegment == 0 ? .mlxLM : .mlxVLM
        let p = draftPresets[row]
        draftPresets[row] = ServerConfig(
            name: p.name, model: p.model, maxTokens: p.maxTokens,
            port: p.port, prefillStepSize: p.prefillStepSize,
            promptCacheSize: p.promptCacheSize, promptCacheBytes: p.promptCacheBytes,
            trustRemoteCode: p.trustRemoteCode, enableThinking: p.enableThinking,
            extraArgs: p.extraArgs, serverType: backend,
            kvBits: p.kvBits, kvGroupSize: p.kvGroupSize,
            maxKvSize: p.maxKvSize, quantizedKvStart: p.quantizedKvStart,
            pythonPath: p.pythonPath
        )
        swapBackendSpecificStack(for: backend)
        installButton.title = "Install / Reinstall \(backend == .mlxLM ? "mlx-lm" : "mlx-vlm")"
        presetListTable.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: IndexSet(integersIn: 0..<presetListTable.numberOfColumns)
        )
        persistChanges()
    }

    private func makeLMStack() -> NSStackView {
        func row(_ labelText: String, _ field: NSView) -> NSStackView {
            let lbl = NSTextField(labelWithString: labelText)
            lbl.alignment = .right
            lbl.widthAnchor.constraint(equalToConstant: 90).isActive = true
            let r = NSStackView(views: [lbl, field])
            r.orientation = .horizontal
            r.spacing = 8
            r.alignment = .centerY
            return r
        }
        let stack = NSStackView(views: [
            row("Context:", detailMaxTokens),
            row("Cache Size:", detailCacheSize),
            row("Cache Bytes:", detailCacheBytes),
            row("", detailEnableThinking),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func makeVLMStack() -> NSStackView {
        func row(_ labelText: String, _ field: NSView) -> NSStackView {
            let lbl = NSTextField(labelWithString: labelText)
            lbl.alignment = .right
            lbl.widthAnchor.constraint(equalToConstant: 90).isActive = true
            let r = NSStackView(views: [lbl, field])
            r.orientation = .horizontal
            r.spacing = 8
            r.alignment = .centerY
            return r
        }
        let stack = NSStackView(views: [
            row("KV Bits:", detailKvBits),
            row("KV Group Size:", detailKvGroupSize),
            row("Max KV Size:", detailMaxKvSize),
            row("KV Start:", detailQuantizedKvStart),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func swapBackendSpecificStack(for backend: ServerType) {
        guard let parent = backendSpecificStack.superview as? NSStackView else { return }
        let insertIndex = parent.arrangedSubviews.firstIndex(of: backendSpecificStack) ?? 1
        parent.removeArrangedSubview(backendSpecificStack)
        backendSpecificStack.removeFromSuperview()
        backendSpecificStack = backend == .mlxLM ? makeLMStack() : makeVLMStack()
        parent.insertArrangedSubview(backendSpecificStack, at: insertIndex)
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
        ramPollPopup.target = self
        ramPollPopup.action = #selector(ramPollChanged)

        startAtLoginCheckbox.state = draftSettings.startAtLogin ? .on : .off
        startAtLoginCheckbox.target = self
        startAtLoginCheckbox.action = #selector(startAtLoginToggled)

        showLastLogLineCheckbox.state = draftSettings.showLastLogLine ? .on : .off
        showLastLogLineCheckbox.target = self
        showLastLogLineCheckbox.action = #selector(showLastLogLineToggled)

        completionThresholdField.stringValue = String(draftSettings.progressCompletionThreshold)
        completionThresholdField.placeholderString = "99"
        completionThresholdField.target = self
        completionThresholdField.action = #selector(completionThresholdChanged(_:))
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

        let grid = NSGridView(numberOfColumns: 2, rows: 5)
        grid.setContentHuggingPriority(.defaultHigh, for: .vertical)

        grid.cell(atColumnIndex: 0, rowIndex: 0).contentView = NSTextField(labelWithString: "")
        grid.cell(atColumnIndex: 1, rowIndex: 0).contentView = ramGraphCheckbox

        grid.cell(atColumnIndex: 0, rowIndex: 1).contentView =
            NSTextField(labelWithString: "Poll interval:")
        grid.cell(atColumnIndex: 1, rowIndex: 1).contentView = ramPollPopup

        grid.cell(atColumnIndex: 0, rowIndex: 2).contentView = NSTextField(labelWithString: "")
        grid.cell(atColumnIndex: 1, rowIndex: 2).contentView = startAtLoginCheckbox

        grid.cell(atColumnIndex: 0, rowIndex: 3).contentView = NSTextField(labelWithString: "")
        grid.cell(atColumnIndex: 1, rowIndex: 3).contentView = showLastLogLineCheckbox

        grid.cell(atColumnIndex: 0, rowIndex: 4).contentView =
            NSTextField(labelWithString: "Complete at %:")
        grid.cell(atColumnIndex: 1, rowIndex: 4).contentView = completionThresholdField

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

    // MARK: - Persistence

    private func persistChanges() {
        try? UserPresetStore.save(draftPresets, to: UserPresetStore.defaultURL)
        onChange?(draftPresets, draftSettings)
    }

    // MARK: - Actions

    @objc private func detailFieldChanged(_ sender: NSTextField) {
        applyDetail()
        persistChanges()
    }

    @objc private func detailCheckboxChanged(_ sender: NSButton) {
        applyDetail()
        persistChanges()
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
        persistChanges()
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
        persistChanges()
    }

    @objc private func ramGraphToggled() {
        draftSettings.ramGraphEnabled = ramGraphCheckbox.state == .on
        ramPollPopup.isEnabled = draftSettings.ramGraphEnabled
        persistChanges()
    }

    @objc private func ramPollChanged() {
        let intervals = [2, 5, 10]
        draftSettings.ramPollInterval = intervals[safe: ramPollPopup.indexOfSelectedItem] ?? 5
        persistChanges()
    }

    @objc private func startAtLoginToggled() {
        let newValue = startAtLoginCheckbox.state == .on
        if newValue != draftSettings.startAtLogin {
            if newValue { LoginItemManager.enable() } else { LoginItemManager.disable() }
        }
        draftSettings.startAtLogin = newValue
        persistChanges()
    }

    @objc private func showLastLogLineToggled() {
        draftSettings.showLastLogLine = showLastLogLineCheckbox.state == .on
        persistChanges()
    }

    @objc private func completionThresholdChanged(_ sender: NSTextField) {
        draftSettings.progressCompletionThreshold = Int(sender.stringValue) ?? 99
        persistChanges()
    }

    @objc private func installEnvironment() {
        installerOutput.string = ""
        let backend = draftPresets[safe: presetListTable.selectedRow]?.serverType ?? .mlxLM
        let inst = EnvironmentInstaller(backend: backend)
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

    @objc private func closeTapped() {
        window?.makeFirstResponder(nil)
        applyDetail()
        dismissed = true
        onDismiss?(draftPresets, draftSettings, false)
        window?.close()
    }

    @objc private func cancelTapped() {
        draftPresets = snapshotPresets
        draftSettings = snapshotSettings
        if snapshotSettings.startAtLogin != (startAtLoginCheckbox.state == .on) {
            if snapshotSettings.startAtLogin { LoginItemManager.enable() } else { LoginItemManager.disable() }
        }
        try? UserPresetStore.save(snapshotPresets, to: UserPresetStore.defaultURL)
        dismissed = true
        onDismiss?(snapshotPresets, snapshotSettings, true)
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

        switch id {
        case "listBackend":
            let cellView = tableView.makeView(
                withIdentifier: NSUserInterfaceItemIdentifier("listBackend"), owner: self
            ) as? NSTableCellView ?? NSTableCellView()
            if cellView.textField == nil {
                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                    tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                ])
                cellView.textField = tf
            }
            cellView.textField?.stringValue = preset.serverType == .mlxLM ? "LM" : "VLM"
            return cellView

        default:
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
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView, tv === presetListTable else { return }
        window?.makeFirstResponder(nil)  // commit any active field editor before switching
        applyDetail()
        populateDetail(row: tv.selectedRow)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !dismissed {
            onDismiss?(draftPresets, draftSettings, false)
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
