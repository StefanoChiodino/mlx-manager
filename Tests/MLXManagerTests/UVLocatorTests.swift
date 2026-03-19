import Testing
@testable import MLXManager

@Suite("UVLocator")
struct UVLocatorTests {

    @Test("locate returns first candidate when it exists")
    func test_locate_whenFirstCandidateExists_returnsIt() {
        let first = UVLocator.candidatePaths[0]
        let locator = UVLocator(fileExists: { path in path == first })
        #expect(locator.locate() == first)
    }

    @Test("locate falls back to second candidate when first is missing")
    func test_locate_whenFirstMissingSecondExists_returnsSecond() {
        let second = UVLocator.candidatePaths[1]
        let locator = UVLocator(fileExists: { path in path == second })
        #expect(locator.locate() == second)
    }

    @Test("locate returns nil when no candidate exists")
    func test_locate_whenNoneExist_returnsNil() {
        let locator = UVLocator(fileExists: { _ in false })
        #expect(locator.locate() == nil)
    }
}
