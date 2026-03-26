import XCTest
@testable import MLXManager

final class PackageUpdateCheckerTests: XCTestCase {

    func test_parseOutdated_withUpdates_returnsPackageInfo() {
        let output = """
        Package    Version    Latest    Type
        mlx-lm     0.21.0     0.22.1    sdist
        """
        let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.currentVersion, "0.21.0")
        XCTAssertEqual(result?.latestVersion, "0.22.1")
    }

    func test_parseOutdated_noUpdates_returnsNil() {
        let output = """
        Package    Version    Latest    Type
        """
        let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
        XCTAssertNil(result)
    }

    func test_parseOutdated_emptyOutput_returnsNil() {
        let result = PackageUpdateChecker.parseOutdated(output: "", packageName: "mlx-lm")
        XCTAssertNil(result)
    }

    func test_parseOutdated_differentPackageOutdated_returnsNil() {
        let output = """
        Package    Version    Latest    Type
        numpy      1.25.0     1.26.0    sdist
        """
        let result = PackageUpdateChecker.parseOutdated(output: output, packageName: "mlx-lm")
        XCTAssertNil(result)
    }
}
