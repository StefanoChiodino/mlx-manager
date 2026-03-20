import Testing
import Foundation
@testable import MLXManager

@Suite("SystemPIDLister")
struct SystemPIDListerTests {

    // T17
    @Test("allPIDs — returns non-empty list containing current process PID")
    func test_allPIDs_containsCurrentProcess() {
        let lister = SystemPIDLister()
        let myPID = ProcessInfo.processInfo.processIdentifier
        let pids = lister.allPIDs()
        #expect(!pids.isEmpty)
        #expect(pids.contains(myPID))
    }
}
