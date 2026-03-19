import Testing
@testable import MLXManager

@Suite("EnvironmentChecker")
struct EnvironmentCheckerTests {

    @Test("isReady returns true when python binary exists")
    func test_isReady_whenPythonExists_returnsTrue() {
        let checker = EnvironmentChecker(fileExists: { _ in true })
        #expect(checker.isReady(pythonPath: "/some/path/python") == true)
    }

    @Test("isReady returns false when python binary is missing")
    func test_isReady_whenPythonMissing_returnsFalse() {
        let checker = EnvironmentChecker(fileExists: { _ in false })
        #expect(checker.isReady(pythonPath: "/some/path/python") == false)
    }

    @Test("isReady passes the given path to fileExists")
    func test_isReady_passesCorrectPathToFileExists() {
        var checked: String?
        let checker = EnvironmentChecker(fileExists: { path in
            checked = path
            return true
        })
        _ = checker.isReady(pythonPath: "/custom/python3")
        #expect(checked == "/custom/python3")
    }
}
