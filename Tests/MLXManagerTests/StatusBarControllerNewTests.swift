import XCTest
@testable import MLXManager

final class StatusBarControllerNewTests: XCTestCase {

    // MARK: - Status text menu item

    func test_statusText_offline() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let item = view.menuItems.first
        XCTAssertEqual(item?.title, "Server: Offline")
        XCTAssertEqual(item?.enabled, false)
    }

    func test_statusText_idle() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        let item = view.menuItems.first
        XCTAssertEqual(item?.title, "Server: Idle")
    }

    func test_statusText_processing() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 27611, total: 41061, percentage: 67.24))
        controller.update(state: state)
        let item = view.menuItems.first
        XCTAssertEqual(item?.title, "27,611 / 41,061  (67%)")
    }

    // MARK: - Progress bar includes percentage

    func test_progressBar_includesPercentage() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97))
        controller.update(state: state)
        // Icon should contain a percentage suffix
        XCTAssertTrue(view.lastTitle?.contains("%") == true, "Expected % in title, got: \(view.lastTitle ?? "nil")")
    }

    // MARK: - Pie progress style

    func test_progressStyle_pie() {
        let view = MockStatusBarView()
        var settings = AppSettings()
        settings.progressStyle = .pie
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 20000, total: 41061, percentage: 48.7))
        controller.update(state: state, settings: settings)
        // ~48.7% → ◑ (second quintile boundary)
        let pieGlyphs = ["○", "◔", "◑", "◕", "●"]
        XCTAssertTrue(pieGlyphs.contains(view.lastTitle ?? ""), "Expected pie glyph, got: \(view.lastTitle ?? "nil")")
    }

    // MARK: - Menu contains new items

    func test_menuContainsLogItem() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let titles = view.menuItems.map(\.title)
        XCTAssertTrue(titles.contains("Show Log"))
    }

    func test_menuContainsHistoryItem() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let titles = view.menuItems.map(\.title)
        XCTAssertTrue(titles.contains("Request History"))
    }

    func test_menuContainsSettings() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let titles = view.menuItems.map(\.title)
        XCTAssertTrue(titles.contains("Settings…"))
    }

    func test_menuRAMGraph_hiddenByDefault() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        let titles = view.menuItems.map(\.title)
        XCTAssertFalse(titles.contains("RAM Graph"))
    }

    func test_menuRAMGraph_shownWhenEnabled() {
        let view = MockStatusBarView()
        var settings = AppSettings()
        settings.ramGraphEnabled = true
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {},
                                             settings: settings)
        let titles = view.menuItems.map(\.title)
        XCTAssertTrue(titles.contains("RAM Graph"))
    }
}
