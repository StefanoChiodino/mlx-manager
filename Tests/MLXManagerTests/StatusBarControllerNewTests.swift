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

    // MARK: - Display state for progress

    func test_displayState_processingFraction() {
        let view = MockStatusBarView()
        let controller = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        controller.serverDidStart()
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97))
        controller.update(state: state)
        if case let .processing(fraction) = view.lastState {
            XCTAssertEqual(fraction, 4096.0 / 41061.0, accuracy: 0.001)
        } else {
            XCTFail("Expected .processing, got \(String(describing: view.lastState))")
        }
    }

    // MARK: - Menu contains new items

    func test_menuContainsLogItem() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        XCTAssertTrue(view.menuItems.map(\.title).contains("Show Log"))
    }

    func test_menuContainsHistoryItem() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        XCTAssertTrue(view.menuItems.map(\.title).contains("Request History"))
    }

    func test_menuContainsSettings() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        XCTAssertTrue(view.menuItems.map(\.title).contains("Settings…"))
    }

    func test_menuRAMGraph_hiddenByDefault() {
        let view = MockStatusBarView()
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {})
        XCTAssertFalse(view.menuItems.map(\.title).contains("RAM Graph"))
    }

    func test_menuRAMGraph_shownWhenEnabled() {
        let view = MockStatusBarView()
        var settings = AppSettings()
        settings.ramGraphEnabled = true
        let _ = StatusBarController(view: view, presets: [], onStart: { _ in }, onStop: {},
                                    settings: settings)
        XCTAssertTrue(view.menuItems.map(\.title).contains("RAM Graph"))
    }
}
