import AppKit
import XCTest
@testable import MLXManager
@testable import MLXManagerApp

@MainActor
final class SettingsWindowControllerTests: XCTestCase {

    func test_close_appliesPendingServerPortFieldEdit() throws {
        let controller = SettingsWindowController(
            presets: [ServerConfig.fixture()],
            settings: AppSettings()
        )
        let field = try XCTUnwrap(reflectedValue(named: "serverPortField", in: controller, as: NSTextField.self))
        var dismissedSettings: AppSettings?
        controller.onDismiss = { _, settings, cancelled in
            XCTAssertFalse(cancelled)
            dismissedSettings = settings
        }

        field.stringValue = "9090"
        controller.perform(NSSelectorFromString("closeTapped"))

        XCTAssertEqual(dismissedSettings?.serverPort, 9090)
    }

    private func reflectedValue<T>(named label: String, in subject: Any, as type: T.Type) -> T? {
        Mirror(reflecting: subject).descendant(label) as? T
    }
}
