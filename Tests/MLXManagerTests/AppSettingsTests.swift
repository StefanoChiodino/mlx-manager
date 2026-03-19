import XCTest
@testable import MLXManager

final class AppSettingsTests: XCTestCase {

    func test_appSettings_defaultValues() {
        let s = AppSettings()
        XCTAssertEqual(s.progressStyle, .bar)
        XCTAssertEqual(s.ramGraphEnabled, false)
        XCTAssertEqual(s.ramPollInterval, 5)
    }

    func test_appSettings_roundTripsJSON() throws {
        var s = AppSettings()
        s.progressStyle = .pie
        s.ramGraphEnabled = true
        s.ramPollInterval = 2

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, s)
    }
}
