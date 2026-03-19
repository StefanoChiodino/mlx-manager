import Foundation

/// Installs a Python venv with mlx-lm at ~/.mlx-manager/venv/.
final class EnvironmentInstaller {

    static let venvPath = NSString("~/.mlx-manager/venv").expandingTildeInPath
    static let pythonPath = venvPath + "/bin/python"

    var onOutput: ((String) -> Void)?
    var onComplete: ((Bool) -> Void)?

    private var currentProcess: Process?

    func install() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Step 1: create venv
            let success1 = self.runStep(
                command: "/usr/bin/python3",
                arguments: ["-m", "venv", Self.venvPath],
                label: "Creating venv…"
            )
            guard success1 else {
                DispatchQueue.main.async { self.onComplete?(false) }
                return
            }

            // Step 2: pip install mlx-lm
            let pipPath = Self.venvPath + "/bin/pip"
            let success2 = self.runStep(
                command: pipPath,
                arguments: ["install", "mlx-lm"],
                label: "Installing mlx-lm…"
            )
            DispatchQueue.main.async { self.onComplete?(success2) }
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }

    // MARK: - Private

    private func runStep(command: String, arguments: [String], label: String) -> Bool {
        emit(label)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.onOutput?(line) }
        }

        currentProcess = process
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            emit("Error: \(error.localizedDescription)\n")
            return false
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        return process.terminationStatus == 0
    }

    private func emit(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onOutput?(text) }
    }
}
