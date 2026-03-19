import Testing
@testable import MLXManager

// MARK: - Test Doubles

/// Captures menu bar updates for testing without AppKit.
final class MockStatusBarView: StatusBarViewProtocol {
    var lastTitle: String?
    var menuItems: [(title: String, enabled: Bool)] = []
    var menuBuilt = false

    func updateTitle(_ title: String) {
        lastTitle = title
    }

    func buildMenu(items: [StatusBarMenuItem]) {
        menuBuilt = true
        menuItems = items.map { ($0.title, $0.isEnabled) }
    }
}

@Suite("StatusBarController")
struct StatusBarControllerTests {

    // MARK: - Initial display

    @Test("Initial state shows offline icon")
    func initialStateShowsOffline() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        #expect(view.lastTitle == "○")
    }

    // MARK: - Icon states

    @Test("Server started shows idle icon")
    func serverStartedShowsIdle() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        #expect(view.lastTitle == "●")
    }

    @Test("Server stopped shows offline icon")
    func serverStoppedShowsOffline() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.serverDidStop()
        #expect(view.lastTitle == "○")
    }

    @Test("Progress event shows progress bar at ~10%")
    func progressShowsBar() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.update(state: makeState(status: .processing, current: 4096, total: 41061))
        // 4096/41061 ≈ 10% → 1 filled block out of 10
        #expect(view.lastTitle == "▓░░░░░░░░░")
    }

    @Test("Near-complete progress shows nearly full bar")
    func nearCompleteShowsFullBar() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.update(state: makeState(status: .processing, current: 41056, total: 41061))
        // 41056/41061 ≈ 99.99% → all 10 filled
        #expect(view.lastTitle == "▓▓▓▓▓▓▓▓▓▓")
    }

    @Test("Completion signal returns to idle icon")
    func completionReturnsToIdle() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        controller.update(state: makeState(status: .processing, current: 4096, total: 41061))
        controller.update(state: makeState(status: .idle))
        #expect(view.lastTitle == "●")
    }

    // MARK: - Menu building

    @Test("Menu includes preset names and quit")
    func menuIncludesPresetsAndQuit() {
        let view = MockStatusBarView()
        let presets = [
            ServerConfig(name: "4-bit 40k", model: "m1", maxTokens: 40960, extraArgs: []),
            ServerConfig(name: "8-bit 80k", model: "m2", maxTokens: 81920, extraArgs: []),
        ]
        let _ = StatusBarController(view: view, presets: presets, onStart: { _ in }, onStop: {})
        #expect(view.menuBuilt == true)
        // Should have: Start submenu header, presets, separator, Stop, separator, Quit
        let titles = view.menuItems.map(\.title)
        #expect(titles.contains("4-bit 40k"))
        #expect(titles.contains("8-bit 80k"))
        #expect(titles.contains("Stop"))
        #expect(titles.contains("Quit"))
    }

    @Test("Stop is disabled when offline")
    func stopDisabledWhenOffline() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let stopItem = view.menuItems.first(where: { $0.title == "Stop" })
        #expect(stopItem?.enabled == false)
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
        let preset = ServerConfig(name: "4-bit 40k", model: "m1", maxTokens: 40960, extraArgs: [])
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

    // MARK: - Helpers

    private func makeState(status: ServerStatus, current: Int? = nil, total: Int? = nil) -> ServerState {
        var state = ServerState()
        state.serverStarted()
        if status == .processing, let c = current, let t = total {
            state.handle(.progress(current: c, total: t, percentage: (Double(c) / Double(t)) * 100))
        }
        if status == .idle {
            // Already idle after serverStarted
        }
        return state
    }
}
