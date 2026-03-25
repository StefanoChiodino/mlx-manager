import AppKit
import XCTest
@testable import MLXManager
@testable import MLXManagerApp

@MainActor
final class SettingsWindowControllerTests: XCTestCase {

    func test_lmPresetDisplaysContextInThousandsAndCacheInGB() throws {
        let controller = SettingsWindowController(
            presets: [
                ServerConfig(
                    name: "4-bit 40k",
                    model: "mlx-community/test-model",
                    maxTokens: 40 * 1024,
                    promptCacheSize: 7,
                    promptCacheBytes: 10 * 1024 * 1024 * 1024,
                    pythonPath: "/usr/bin/python3"
                )
            ],
            settings: AppSettings(),
            saveURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yaml")
        )
        let table = try XCTUnwrap(reflectedValue(named: "presetListTable", in: controller, as: NSTableView.self))
        let tokensField = try XCTUnwrap(reflectedValue(named: "detailMaxTokens", in: controller, as: NSTextField.self))
        let cacheField = try XCTUnwrap(reflectedValue(named: "detailCacheBytes", in: controller, as: NSTextField.self))

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: table)
        )

        XCTAssertEqual(tokensField.stringValue, "40")
        XCTAssertEqual(cacheField.stringValue, "10")
    }

    func test_close_appliesPendingLMUnitConvertedEdits() throws {
        let controller = SettingsWindowController(
            presets: [
                ServerConfig(
                    name: "4-bit 40k",
                    model: "mlx-community/test-model",
                    maxTokens: 40 * 1024,
                    promptCacheSize: 7,
                    promptCacheBytes: 10 * 1024 * 1024 * 1024,
                    pythonPath: "/usr/bin/python3"
                )
            ],
            settings: AppSettings(),
            saveURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yaml")
        )
        let table = try XCTUnwrap(reflectedValue(named: "presetListTable", in: controller, as: NSTableView.self))
        let tokensField = try XCTUnwrap(reflectedValue(named: "detailMaxTokens", in: controller, as: NSTextField.self))
        let cacheField = try XCTUnwrap(reflectedValue(named: "detailCacheBytes", in: controller, as: NSTextField.self))
        var dismissedPresets: [ServerConfig] = []
        controller.onDismiss = { presets, _, cancelled in
            XCTAssertFalse(cancelled)
            dismissedPresets = presets
        }

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: table)
        )
        tokensField.stringValue = "80"
        cacheField.stringValue = "12"

        controller.perform(NSSelectorFromString("closeTapped"))

        XCTAssertEqual(dismissedPresets.first?.maxTokens, 80 * 1024)
        XCTAssertEqual(dismissedPresets.first?.promptCacheBytes, 12 * 1024 * 1024 * 1024)
        XCTAssertEqual(dismissedPresets.first?.promptCacheSize, 7)
    }

    func test_close_appliesPendingServerPortFieldEdit() throws {
        let controller = SettingsWindowController(
            presets: [ServerConfig.fixture()],
            settings: AppSettings(),
            saveURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yaml")
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

    func test_close_persistsPresetEditsToDisk() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".yaml")
        let controller = SettingsWindowController(
            presets: [
                ServerConfig(
                    name: "4-bit 40k",
                    model: "mlx-community/old-model",
                    maxTokens: 40 * 1024,
                    pythonPath: "/usr/bin/python3"
                )
            ],
            settings: AppSettings(),
            saveURL: tempURL
        )
        let table = try XCTUnwrap(reflectedValue(named: "presetListTable", in: controller, as: NSTableView.self))
        let modelField = try XCTUnwrap(reflectedValue(named: "detailModel", in: controller, as: NSTextField.self))

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: table)
        )
        modelField.stringValue = "mlx-community/new-model"

        controller.perform(NSSelectorFromString("closeTapped"))

        let saved = try UserPresetStore.load(from: tempURL)
        XCTAssertEqual(saved.first?.model, "mlx-community/new-model")
    }

    private func reflectedValue<T>(named label: String, in subject: Any, as type: T.Type) -> T? {
        Mirror(reflecting: subject).descendant(label) as? T
    }
}
