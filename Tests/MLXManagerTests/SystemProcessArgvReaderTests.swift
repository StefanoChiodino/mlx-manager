import Testing
import Foundation
@testable import MLXManager

@Suite("SystemProcessArgvReader")
struct SystemProcessArgvReaderTests {

    // T15
    @Test("current process PID — argv contains executable path")
    func test_argv_currentProcess_containsExecutablePath() {
        let reader = SystemProcessArgvReader()
        let myPID = ProcessInfo.processInfo.processIdentifier
        let args = reader.argv(for: myPID)
        #expect(args != nil)
        #expect(args?.isEmpty == false)
    }

    // T16
    @Test("non-existent PID — returns nil")
    func test_argv_nonExistentPID_returnsNil() {
        let reader = SystemProcessArgvReader()
        // PID 99999 is extremely unlikely to exist
        let args = reader.argv(for: 99999)
        #expect(args == nil)
    }
}
