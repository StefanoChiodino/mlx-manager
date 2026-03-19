import Foundation

/// Runs a shell command synchronously, streaming output via a callback.
public protocol CommandRunner: AnyObject {
    /// Execute `command` with `arguments`. Calls `onOutput` with stdout+stderr chunks.
    /// Returns the process exit code.
    func run(command: String, arguments: [String], onOutput: @escaping (String) -> Void) -> Int32
}
