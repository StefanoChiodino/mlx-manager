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

    func test_appSettings_serverPort_defaultsTo8080() {
        XCTAssertEqual(AppSettings().serverPort, 8080)
    }

    func test_appSettings_managedGatewayPort_defaultsTo8080() {
        XCTAssertEqual(AppSettings().managedGatewayPort, 8080)
    }

    func test_appSettings_startAtLogin_roundTripsJSON() throws {
        var s = AppSettings()
        s.startAtLogin = true

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.startAtLogin, true)
    }

    func test_appSettings_progressCompletionThreshold_defaultsTo0() {
        XCTAssertEqual(AppSettings().progressCompletionThreshold, 0)
    }

    func test_appSettings_progressCompletionThreshold_roundTripsJSON() throws {
        var s = AppSettings()
        s.progressCompletionThreshold = 95

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.progressCompletionThreshold, 95)
    }

    func test_appSettings_progressCompletionThreshold_migratesFromOldJSON() throws {
        // Old JSON without the field should default to disabled
        let oldData = Data("""
        {
          "ramGraphEnabled": false,
          "ramPollInterval": 5,
          "startAtLogin": false,
          "logPath": "~/repos/mlx/Logs/server.log"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldData)
        XCTAssertEqual(decoded.progressCompletionThreshold, 0)
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

    func test_appSettings_showLastLogLine_defaultsFalse() {
        XCTAssertEqual(AppSettings().showLastLogLine, false)
    }

    func test_appSettings_managedGatewayEnabled_defaultsFalse() {
        XCTAssertEqual(AppSettings().managedGatewayEnabled, false)
    }

    func test_appSettings_managedGatewayEnabled_roundTripsJSON() throws {
        var s = AppSettings()
        s.managedGatewayEnabled = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.managedGatewayEnabled, true)
    }

    func test_appSettings_managedGatewayEnabled_migratesFromOldJSON() throws {
        let oldData = Data("""
        {
          "ramGraphEnabled": false,
          "ramPollInterval": 5,
          "startAtLogin": false,
          "logPath": "~/repos/mlx/Logs/server.log",
          "progressCompletionThreshold": 99,
          "showLastLogLine": true
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldData)
        XCTAssertEqual(decoded.managedGatewayEnabled, false)
    }

    func test_appSettings_networkPorts_roundTripJSON() throws {
        var s = AppSettings()
        s.serverPort = 8088
        s.managedGatewayPort = 8080

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.serverPort, 8088)
        XCTAssertEqual(decoded.managedGatewayPort, 8080)
    }

    func test_appSettings_managedBackendPort_usesServerPortWhenPortsDiffer() {
        var settings = AppSettings()
        settings.serverPort = 8088
        settings.managedGatewayPort = 8080

        XCTAssertEqual(settings.managedGatewayBackendPort, 8088)
    }

    func test_appSettings_managedBackendPort_usesHiddenOffsetWhenPortsMatch() {
        var settings = AppSettings()
        settings.serverPort = 8080
        settings.managedGatewayPort = 8080

        XCTAssertEqual(settings.managedGatewayBackendPort, 8180)
    }

    func test_appSettings_pythonPathOverride_defaultsEmpty() {
        XCTAssertEqual(AppSettings().pythonPathOverride, "")
    }

    func test_appSettings_pythonPathOverride_roundTripsJSON() throws {
        var s = AppSettings()
        s.pythonPathOverride = "~/custom/python3"

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.pythonPathOverride, "~/custom/python3")
    }

    func test_appSettings_resolvedPythonPath_usesOverrideWhenPresent() {
        var settings = AppSettings()
        settings.pythonPathOverride = "~/custom/python3"
        let config = ServerConfig(name: "Test", model: "some/model", maxTokens: 4096, serverType: .mlxVLM)

        let resolved = settings.resolvedPythonPath(for: config)

        XCTAssertFalse(resolved.hasPrefix("~"))
        XCTAssertTrue(resolved.hasSuffix("/custom/python3"))
    }

    func test_appSettings_resolvedPythonPath_usesConfigPathWhenOverrideMissing() {
        let settings = AppSettings()
        let config = ServerConfig(
            name: "Test",
            model: "some/model",
            maxTokens: 4096,
            pythonPath: "~/custom/python3"
        )

        let resolved = settings.resolvedPythonPath(for: config)

        XCTAssertFalse(resolved.hasPrefix("~"))
        XCTAssertTrue(resolved.hasSuffix("/custom/python3"))
    }

    func test_appSettings_showLastLogLine_roundTripsJSON() throws {
        var s = AppSettings()
        s.showLastLogLine = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.showLastLogLine, true)
    }

    func test_appSettings_showLastLogLine_migratesFromOldJSON() throws {
        let oldData = Data("""
        {
          "ramGraphEnabled": false,
          "ramPollInterval": 5,
          "startAtLogin": false,
          "logPath": "~/repos/mlx/Logs/server.log",
          "progressCompletionThreshold": 99
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldData)
        XCTAssertEqual(decoded.showLastLogLine, false)
    }

    func test_appSettings_showPrefillTPS_defaultsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.showPrefillTPS)
    }

    func test_appSettings_showPrefillTPS_roundTripsJSON() throws {
        var settings = AppSettings()
        settings.showPrefillTPS = true
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.showPrefillTPS)
    }

    func test_appSettings_showPrefillTPS_missingKeyDefaultsFalse() throws {
        // Simulate an old settings file that doesn't have showPrefillTPS
        let json = """
        {"ramGraphEnabled":false,"ramPollInterval":5,"startAtLogin":false,
         "logPath":"~/repos/mlx/Logs/server.log","serverPort":8080,
         "managedGatewayPort":8080,"progressCompletionThreshold":0,
         "showLastLogLine":false,"managedGatewayEnabled":false,"pythonPathOverride":""}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(decoded.showPrefillTPS)
    }

    func test_appSettings_updateCheckInterval_defaultsTo0() {
        XCTAssertEqual(AppSettings().updateCheckInterval, 0)
    }

    func test_appSettings_updateCheckInterval_roundTripsJSON() throws {
        var s = AppSettings()
        s.updateCheckInterval = 12
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.updateCheckInterval, 12)
    }

    func test_appSettings_updateCheckInterval_migratesFromOldJSON() throws {
        let json = """
        {"ramGraphEnabled":false,"ramPollInterval":5,"startAtLogin":false,
         "logPath":"~/repos/mlx/Logs/server.log","serverPort":8080,
         "managedGatewayPort":8080,"progressCompletionThreshold":0,
         "showLastLogLine":false,"managedGatewayEnabled":false,"pythonPathOverride":"",
         "showPrefillTPS":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(decoded.updateCheckInterval, 0)
    }

    func test_appSettings_lastUpdateCheck_defaultsToNil() {
        XCTAssertNil(AppSettings().lastUpdateCheck)
    }

    func test_appSettings_lastUpdateCheck_roundTripsJSON() throws {
        var s = AppSettings()
        s.lastUpdateCheck = Date(timeIntervalSince1970: 1711500000)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.lastUpdateCheck, s.lastUpdateCheck)
    }

    func test_appSettings_restartNeeded_defaultsFalse() {
        XCTAssertEqual(AppSettings().restartNeeded, false)
    }

    func test_appSettings_restartNeeded_roundTripsJSON() throws {
        var s = AppSettings()
        s.restartNeeded = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.restartNeeded, true)
    }
}
