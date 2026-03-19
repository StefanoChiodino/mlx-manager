import Foundation
import MLXManager

/// Production `CommandRunner` that executes commands via `Process`.
final class ProcessCommandRunner: CommandRunner {

    func run(command: String, arguments: [String], onOutput: @escaping (String) -> Void) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { onOutput(text) }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            DispatchQueue.main.async { onOutput("Error: \(error.localizedDescription)\n") }
            return 1
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        return process.terminationStatus
    }
}
