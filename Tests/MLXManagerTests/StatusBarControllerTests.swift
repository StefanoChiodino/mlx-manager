import Testing
@testable import MLXManager

// MARK: - Test Doubles

/// Captures menu bar updates for testing without AppKit.
final class MockStatusBarView: StatusBarViewProtocol {
    var lastState: StatusBarDisplayState?
    var menuItems: [(title: String, enabled: Bool)] = []
    var menuBuilt = false
    var ramGraphSamples: [RAMSample]?
    var historyRecords: [RequestRecord]?
    var logLines: [(String, LogLineKind)]?
    var lastLogLine: String?

    func updateState(_ state: StatusBarDisplayState) {
        lastState = state
    }

    func buildMenu(items: [StatusBarMenuItem]) {
        menuBuilt = true
        menuItems = items.map { ($0.title, $0.isEnabled) }
    }

    func showRAMGraphView(samples: [RAMSample]) {
        ramGraphSamples = samples
    }

    func closeRAMGraphView() {
        ramGraphSamples = nil
    }

    func showHistoryView(records: [RequestRecord]) {
        historyRecords = records
    }

    func closeHistoryView() {
        historyRecords = nil
    }

    func showLogView(lines: [(String, LogLineKind)]) {
        logLines = lines
    }

    func updateLogLine(_ line: String?) {
        lastLogLine = line
    }
}

@Suite("StatusBarController")
struct StatusBarControllerTests {

    // MARK: - Initial display

    @Test("Initial state shows offline")
    func initialStateShowsOffline() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        #expect(view.lastState == .offline)
    }

    // MARK: - Icon states

    @Test("Server started shows idle")
    func serverStartedShowsIdle() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        #expect(view.lastState == .idle)
    }

    @Test("Server stopped shows offline")
    func serverStoppedShowsOffline() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.serverDidStop()
        #expect(view.lastState == .offline)
    }

    @Test("Progress event emits processing state with correct fraction")
    func progressEmitsProcessingFraction() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.update(state: makeState(status: .processing, current: 4096, total: 41061))
        // 4096/41061 ≈ 0.0997
        if case let .processing(fraction) = view.lastState {
            #expect(abs(fraction - (4096.0 / 41061.0)) < 0.001)
        } else {
            Issue.record("Expected .processing state, got \(String(describing: view.lastState))")
        }
    }

    @Test("Near-complete progress emits fraction near 1 when threshold disabled")
    func nearCompleteEmitsHighFractionWhenThresholdDisabled() {
        let view = MockStatusBarView()
        var settings = AppSettings()
        settings.progressCompletionThreshold = 0  // disabled
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: settings)
        controller.serverDidStart()
        controller.update(state: makeState(status: .processing, current: 41056, total: 41061))
        if case let .processing(fraction) = view.lastState {
            #expect(fraction > 0.999)
        } else {
            Issue.record("Expected .processing state")
        }
    }

    @Test("Completion signal returns to idle")
    func completionReturnsToIdle() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.update(state: makeState(status: .processing, current: 4096, total: 41061))
        controller.update(state: makeState(status: .idle))
        #expect(view.lastState == .idle)
    }

    @Test("Progress at threshold snaps to idle when threshold enabled")
    func progressAtThresholdSnapsToIdle() {
        let view = MockStatusBarView()
        var settings = AppSettings()
        settings.progressCompletionThreshold = 99
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: settings)
        controller.serverDidStart()
        // 41056/41061 ≈ 99.99% — above threshold of 99%
        controller.update(state: makeState(status: .processing, current: 41056, total: 41061))
        #expect(view.lastState == .idle)
    }

    @Test("Progress below threshold stays processing")
    func progressBelowThresholdStaysProcessing() {
        let view = MockStatusBarView()
        var settings = AppSettings()
        settings.progressCompletionThreshold = 99
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: settings)
        controller.serverDidStart()
        // 4096/41061 ≈ 10% — well below threshold
        controller.update(state: makeState(status: .processing, current: 4096, total: 41061))
        if case .processing = view.lastState { } else {
            Issue.record("Expected .processing, got \(String(describing: view.lastState))")
        }
    }

    @Test("Threshold of 0 disables snap behaviour")
    func thresholdZeroDisablesSnap() {
        let view = MockStatusBarView()
        var settings = AppSettings()
        settings.progressCompletionThreshold = 0
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {}, settings: settings)
        controller.serverDidStart()
        // 41056/41061 ≈ 99.99% — would snap if threshold were active
        controller.update(state: makeState(status: .processing, current: 41056, total: 41061))
        if case .processing = view.lastState { } else {
            Issue.record("Expected .processing, got \(String(describing: view.lastState))")
        }
    }

    // MARK: - Menu building

    @Test("Menu includes preset names and quit")
    func menuIncludesPresetsAndQuit() {
        let view = MockStatusBarView()
        let presets = [
            ServerConfig.fixture(name: "4-bit 40k"),
            ServerConfig.fixture(name: "8-bit 80k"),
        ]
        let _ = StatusBarController(view: view, presets: presets, onStart: { _ in }, onStop: {})
        #expect(view.menuBuilt == true)
        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("4-bit 40k"))
        #expect(titles.contains("8-bit 80k"))
        #expect(titles.contains("Quit"))
    }

    @Test("Stop is absent from menu when offline")
    func stopAbsentWhenOffline() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        #expect(!view.menuItems.map(\.title).contains("Stop"))
    }

    @Test("Stop is enabled when server is running")
    func stopEnabledWhenRunning() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        let stopItem = view.menuItems.first(where: { $0.title == "Stop" })
        #expect(stopItem?.enabled == true)
    }

    // MARK: - Callbacks

    @Test("Selecting a preset triggers onStart with correct config")
    func selectingPresetTriggersStart() {
        let view = MockStatusBarView()
        var startedWith: ServerConfig?
        let preset = ServerConfig.fixture(name: "4-bit 40k")
        let controller = StatusBarController(
            view: view, presets: [preset],
            onStart: { startedWith = $0 },
            onStop: {}
        )
        controller.selectPreset(at: 0)
        #expect(startedWith == preset)
    }

    @Test("Stop action triggers onStop callback")
    func stopTriggersCallback() {
        let view = MockStatusBarView()
        var stopCalled = false
        let controller = StatusBarController(
            view: view, presets: [],
            onStart: { _ in },
            onStop: { stopCalled = true }
        )
        controller.serverDidStart()
        controller.stopServer()
        #expect(stopCalled == true)
    }

    // MARK: - Missing python environment

    @Test("Preset with missing pythonPath is disabled and shows env missing suffix")
    func presetWithMissingPythonIsDisabled() {
        let view = MockStatusBarView()
        let preset = ServerConfig.fixture(name: "4-bit 40k", pythonPath: "/nonexistent/python")
        let _ = StatusBarController(
            view: view, presets: [preset],
            onStart: { _ in }, onStop: {},
            fileExists: { _ in false }
        )
        let item = view.menuItems.first(where: { $0.title.contains("4-bit 40k") })
        #expect(item != nil)
        #expect(item?.enabled == false)
        #expect(item?.title.contains("env missing") == true)
    }

    @Test("Preset with valid pythonPath is enabled")
    func presetWithValidPythonIsEnabled() {
        let view = MockStatusBarView()
        let preset = ServerConfig.fixture(name: "4-bit 40k")
        let _ = StatusBarController(
            view: view, presets: [preset],
            onStart: { _ in }, onStop: {},
            fileExists: { _ in true }
        )
        let item = view.menuItems.first(where: { $0.title == "4-bit 40k" })
        #expect(item?.enabled == true)
    }

    // MARK: - Preset section header

    @Test("Offline menu shows 'Start with:' header before presets")
    func offlineMenuShowsStartWithHeader() {
        let view = MockStatusBarView()
        let preset = ServerConfig.fixture(name: "4-bit 40k")
        let _ = StatusBarController(view: view, presets: [preset], onStart: { _ in }, onStop: {})
        let titles = view.menuItems.map(\.title)
        let headerIdx = titles.firstIndex(of: "Start with:")
        let presetIdx = titles.firstIndex(of: "4-bit 40k")
        #expect(headerIdx != nil)
        #expect(presetIdx != nil)
        if let h = headerIdx, let p = presetIdx {
            #expect(p > h, "preset item should follow header")
        }
    }

    @Test("'Start with:' header is not selectable")
    func startWithHeaderIsDisabled() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let headerItem = view.menuItems.first(where: { $0.title == "Start with:" })
        #expect(headerItem?.enabled == false)
    }

    @Test("Running menu shows 'Switch to:' header instead of 'Start with:'")
    func runningMenuShowsSwitchToHeader() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("Switch to:"))
        #expect(!titles.contains("Start with:"))
    }

    // MARK: - Environment install state

    @Test("environmentInstallStarted shows installing item and hides presets")
    func test_environmentInstallStarted_showsInstallingItem() {
        let view = MockStatusBarView()
        let preset = ServerConfig.fixture(name: "4-bit 40k", pythonPath: "/nonexistent/python")
        let controller = StatusBarController(
            view: view, presets: [preset],
            onStart: { _ in }, onStop: {},
            fileExists: { _ in false }
        )
        controller.environmentInstallStarted()
        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("Installing environment…"))
        #expect(!titles.contains("4-bit 40k"))
    }

    @Test("environmentInstallStarted item is not selectable")
    func test_environmentInstallStarted_itemIsDisabled() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.environmentInstallStarted()
        let item = view.menuItems.first(where: { $0.title == "Installing environment…" })
        #expect(item?.enabled == false)
    }

    @Test("environmentInstallFinished shows presets again")
    func test_environmentInstallFinished_showsPresets() {
        let view = MockStatusBarView()
        let preset = ServerConfig.fixture(name: "4-bit 40k")
        let controller = StatusBarController(
            view: view, presets: [preset],
            onStart: { _ in }, onStop: {},
            fileExists: { _ in true }
        )
        controller.environmentInstallStarted()
        controller.environmentInstallFinished()
        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("4-bit 40k"))
        #expect(!titles.contains("Installing environment…"))
    }

    // MARK: - Log view

    @Test("showLogView forwards lines to view")
    func showLogViewForwardsToView() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let lines: [(String, LogLineKind)] = [
            ("test line", .other),
            ("progress 1/10", .progress),
        ]
        controller.showLogView(lines: lines)
        #expect(view.logLines?.count == 2)
        #expect(view.logLines?[0].0 == "test line")
        #expect(view.logLines?[0].1 == .other)
    }

    // MARK: - Log line

    @Test("updateLogLine forwards to view")
    func updateLogLineForwardsToView() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.updateLogLine("processing: 4096/24378")
        #expect(view.lastLogLine == "processing: 4096/24378")
    }

    @Test("updateLogLine nil clears view")
    func updateLogLineNilClearsView() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.updateLogLine("some line")
        controller.updateLogLine(nil)
        #expect(view.lastLogLine == nil)
    }

    // MARK: - updatePresets

    @Test("updatePresets replaces preset menu items")
    func updatePresets_replacesPresetsAndRebuildsMenu() {
        let view = MockStatusBarView()
        let initial = ServerConfig.fixture(name: "Alpha")
        let controller = StatusBarController(view: view, presets: [initial], onStart: { _ in }, onStop: {})

        let updated = ServerConfig.fixture(name: "Beta")
        controller.updatePresets([updated])

        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("Beta"))
        #expect(!titles.contains("Alpha"))
    }

    @Test("updatePresets while running shows Switch to header")
    func updatePresets_whileRunning_showsSwitchToHeader() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.updatePresets([ServerConfig.fixture(name: "GPU")])
        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("Switch to:"))
        #expect(!titles.contains("Start with:"))
    }

    @Test("updatePresets while offline shows Start with header")
    func updatePresets_whileOffline_showsStartWithHeader() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.updatePresets([ServerConfig.fixture(name: "CPU")])
        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("Start with:"))
        #expect(!titles.contains("Switch to:"))
    }

    // MARK: - Helpers

    private func makeState(status: ServerStatus, current: Int? = nil, total: Int? = nil) -> ServerState {
        var state = ServerState()
        state.serverStarted()
        if status == .processing, let c = current, let t = total {
            state.handle(.progress(current: c, total: t, percentage: (Double(c) / Double(t)) * 100))
        }
        return state
    }

}
