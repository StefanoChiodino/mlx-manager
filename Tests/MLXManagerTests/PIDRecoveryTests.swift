import Testing
import Foundation
@testable import MLXManager

// MARK: - Test Double

final class MockPIDFileReader: PIDFileReading {
    var storedPID: Int32?
    var deleteCalled = false
    var aliveChecker: ((Int32) -> Bool) = { _ in false }

    func read() -> Int32? { storedPID }
    func delete() { deleteCalled = true }
    static func isProcessAlive(pid: Int32) -> Bool { _sharedAliveChecker(pid) }

    // Static state for mock — set before each test
    static var _sharedAliveChecker: (Int32) -> Bool = { _ in false }
}

@Suite("PIDRecovery")
struct PIDRecoveryTests {

    // MARK: - T9: no file → .noFile

    @Test("recover returns .noFile when PID file does not exist")
    func recover_noFile() {
        let mock = MockPIDFileReader()
        mock.storedPID = nil
        let recovery = PIDRecovery()

        let result = recovery.recover(pidFile: mock, isAlive: { _ in false })

        #expect(result == .noFile)
    }

    // MARK: - T10: stale file → .staleFile, deletes file

    @Test("recover returns .staleFile when process is dead, and deletes file")
    func recover_staleFile() {
        let mock = MockPIDFileReader()
        mock.storedPID = 99999

        let recovery = PIDRecovery()
        let result = recovery.recover(pidFile: mock, isAlive: { _ in false })

        #expect(result == .staleFile)
        #expect(mock.deleteCalled == true)
    }

    // MARK: - T11: alive process → .adopted(pid)

    @Test("recover returns .adopted(pid) when process is alive")
    func recover_adopted() {
        let mock = MockPIDFileReader()
        mock.storedPID = 12345

        let recovery = PIDRecovery()
        let result = recovery.recover(pidFile: mock, isAlive: { _ in true })

        #expect(result == .adopted(pid: 12345))
    }
}
