import XCTest
@testable import MLXManager

final class AppSettingsTests: XCTestCase {

    func test_appSettings_defaultValues() {
        let s = AppSettings()
        XCTAssertEqual(s.ramGraphEnabled, false)
        XCTAssertEqual(s.ramPollInterval, 5)
    }

    func test_appSettings_logPath_defaultsToMLXPath() {
        let s = AppSettings()
        XCTAssertEqual(s.logPath, "~/repos/mlx/Logs/server.log")
    }

    func test_appSettings_logPath_customValue() {
        var s = AppSettings()
        s.logPath = "/custom/path/to/server.log"
        XCTAssertEqual(s.logPath, "/custom/path/to/server.log")
    }

    func test_appSettings_roundTripsJSON() throws {
        var s = AppSettings()
        s.ramGraphEnabled = true
        s.ramPollInterval = 2

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, s)
    }

    func test_appSettings_logPath_roundTripsJSON() throws {
        var s = AppSettings()
        s.logPath = "/var/log/mlx/server.log"

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.logPath, s.logPath)
    }

    func test_appSettings_startAtLogin_defaultsFalse() {
        XCTAssertEqual(AppSettings().startAtLogin, false)
    }

    func test_appSettings_startAtLogin_roundTripsJSON() throws {
        var s = AppSettings()
        s.startAtLogin = true

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.startAtLogin, true)
    }

    func test_appSettings_progressCompletionThreshold_defaultsTo99() {
        XCTAssertEqual(AppSettings().progressCompletionThreshold, 99)
    }

    func test_appSettings_progressCompletionThreshold_roundTripsJSON() throws {
        var s = AppSettings()
        s.progressCompletionThreshold = 95

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.progressCompletionThreshold, 95)
    }

    func test_appSettings_progressCompletionThreshold_migratesFromOldJSON() throws {
        // Old JSON without the field should default to 99
        let oldData = Data("""
        {
          "ramGraphEnabled": false,
          "ramPollInterval": 5,
          "startAtLogin": false,
          "logPath": "~/repos/mlx/Logs/server.log"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldData)
        XCTAssertEqual(decoded.progressCompletionThreshold, 99)
    }

    func test_appSettings_migrateWithoutLogPath() throws {
        let oldData = Data("""
        {
          "ramGraphEnabled": false,
          "ramPollInterval": 5,
          "startAtLogin": false,
          "logPath": ""
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldData)
        XCTAssertEqual(decoded.logPath, "")
    }
}
