import Testing
@testable import MLXManager

// MARK: - Test Doubles

/// Captures menu bar updates for testing without AppKit.
final class MockStatusBarView: StatusBarViewProtocol {
    var lastState: StatusBarDisplayState?
    var menuItems: [(title: String, enabled: Bool)] = []
    var menuBuilt = false

    func updateState(_ state: StatusBarDisplayState) {
        lastState = state
    }

    func buildMenu(items: [StatusBarMenuItem]) {
        menuBuilt = true
        menuItems = items.map { ($0.title, $0.isEnabled) }
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

    @Test("Near-complete progress emits fraction near 1")
    func nearCompleteEmitsHighFraction() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
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

    // MARK: - Menu building

    @Test("Menu includes preset names and quit")
    func menuIncludesPresetsAndQuit() {
        let view = MockStatusBarView()
        let presets = [
            ServerConfig(name: "4-bit 40k", model: "m1", maxTokens: 40960, extraArgs: [], pythonPath: "/usr/bin/python3"),
            ServerConfig(name: "8-bit 80k", model: "m2", maxTokens: 81920, extraArgs: [], pythonPath: "/usr/bin/python3"),
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
        let preset = ServerConfig(name: "4-bit 40k", model: "m1", maxTokens: 40960, extraArgs: [], pythonPath: "/usr/bin/python3")
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
        let preset = ServerConfig(name: "4-bit 40k", model: "m1", maxTokens: 40960, extraArgs: [], pythonPath: "/nonexistent/python")
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
        let preset = ServerConfig(name: "4-bit 40k", model: "m1", maxTokens: 40960, extraArgs: [], pythonPath: "/usr/bin/python3")
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
        let preset = ServerConfig(name: "4-bit 40k", model: "m1", maxTokens: 40960, extraArgs: [], pythonPath: "/usr/bin/python3")
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
        let preset = ServerConfig(name: "4-bit 40k", model: "m", maxTokens: 40960, extraArgs: [], pythonPath: "/p")
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
        let preset = ServerConfig(name: "4-bit 40k", model: "m", maxTokens: 40960, extraArgs: [], pythonPath: "/usr/bin/python3")
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
