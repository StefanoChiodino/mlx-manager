import Testing
import Foundation
@testable import MLXManager

@Suite("PIDFile")
struct PIDFileTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mlx-manager-test-\(UUID().uuidString)")
            .appendingPathComponent("server.pid")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - T1: write creates file with PID as decimal string

    @Test("write(pid:) writes PID as decimal string, creating parent dirs")
    func write_createFileWithPID() throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pidFile = PIDFile(url: url)

        try pidFile.write(pid: 42)

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents == "42")
    }

    // MARK: - T2: read returns PID from file

    @Test("read() returns PID from file contents")
    func read_returnsPID() throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pidFile = PIDFile(url: url)
        try pidFile.write(pid: 12345)

        let result = pidFile.read()

        #expect(result == 12345)
    }

    // MARK: - T3: read returns nil when file does not exist

    @Test("read() returns nil when file does not exist")
    func read_noFile_returnsNil() {
        let url = tempURL()
        let pidFile = PIDFile(url: url)

        #expect(pidFile.read() == nil)
    }

    // MARK: - T4: read returns nil for non-numeric content

    @Test("read() returns nil when file contains non-numeric content")
    func read_garbage_returnsNil() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not-a-number".write(to: url, atomically: true, encoding: .utf8)
        let pidFile = PIDFile(url: url)

        #expect(pidFile.read() == nil)
    }

    // MARK: - T5: delete removes the file

    @Test("delete() removes the PID file")
    func delete_removesFile() throws {
        let url = tempURL()
        defer { cleanup(url) }
        let pidFile = PIDFile(url: url)
        try pidFile.write(pid: 99)

        pidFile.delete()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - T6: delete is no-op when file does not exist

    @Test("delete() is a no-op when file does not exist")
    func delete_noFile_noOp() {
        let url = tempURL()
        let pidFile = PIDFile(url: url)

        // Should not throw or crash
        pidFile.delete()
    }

    // MARK: - T7: isProcessAlive returns true for living process

    @Test("isProcessAlive returns true for current process")
    func isProcessAlive_self_returnsTrue() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        #expect(PIDFile.isProcessAlive(pid: myPID) == true)
    }

    // MARK: - T8: isProcessAlive returns false for dead PID

    @Test("isProcessAlive returns false for a dead PID")
    func isProcessAlive_deadPID_returnsFalse() {
        // PID 99999 is extremely unlikely to be alive
        #expect(PIDFile.isProcessAlive(pid: 99999) == false)
    }
}
