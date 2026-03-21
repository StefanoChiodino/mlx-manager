import Foundation

/// Bootstraps the managed Python environment using `uv`.
///
/// Steps:
/// 1. Locate `uv`; if absent, run `uvInstallCommand`.
/// 2. `uv venv ~/.mlx-manager/venv --python 3.12`
/// 3. `uv pip install mlx-lm --python <venvPython>`
public final class EnvironmentBootstrapper {

    public var onOutput: ((String) -> Void)?
    public var onComplete: ((Bool) -> Void)?

    private let uvLocator: UVLocator
    private let runner: CommandRunner
    /// Runs the uv installer; returns true on success. nil = use default curl installer.
    private let uvInstallCommand: (() -> Bool)?

    public static let venvPath   = NSString("~/.mlx-manager/venv").expandingTildeInPath
    public static let pythonPath = venvPath + "/bin/python"

    public init(
        uvLocator: UVLocator = UVLocator(),
        runner: CommandRunner,
        uvInstallCommand: (() -> Bool)? = nil
    ) {
        self.uvLocator = uvLocator
        self.runner = runner
        self.uvInstallCommand = uvInstallCommand
    }

    public func install() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.runInstall()
        }
    }

    // MARK: - Private

    private func runInstall() {
        // Step 1: locate uv
        guard let uvPath = resolveUV() else {
            emit("Error: could not locate or install uv\n")
            DispatchQueue.main.async { self.onComplete?(false) }
            return
        }

        // Step 2: uv venv
        let venvOK = step(uvPath, ["venv", Self.venvPath, "--python", "3.12"], label: "Creating venv…")
        guard venvOK else {
            DispatchQueue.main.async { self.onComplete?(false) }
            return
        }

        // Step 3: uv pip install mlx-lm
        let mlxLMOK = step(uvPath, ["pip", "install", "mlx-lm",
                                    "--python", Self.pythonPath], label: "Installing mlx-lm…")
        guard mlxLMOK else {
            DispatchQueue.main.async { self.onComplete?(false) }
            return
        }

        // Step 4: uv pip install mlx-vlm
        let mlxVLMOK = step(uvPath, ["pip", "install", "mlx-vlm",
                                     "--python", Self.pythonPath], label: "Installing mlx-vlm…")
        DispatchQueue.main.async { self.onComplete?(mlxVLMOK) }
    }

    private func resolveUV() -> String? {
        if let path = uvLocator.locate() { return path }

        // uv not found — run installer
        emit("uv not found. Installing uv…\n")
        let installer = uvInstallCommand ?? defaultUVInstaller
        guard installer() else { return nil }

        // After install, uv lands at the first candidate path
        return uvLocator.locate()
    }

    private func defaultUVInstaller() -> Bool {
        emit("Running: curl -LsSf https://astral.sh/uv/install.sh | sh\n")
        let code = runner.run(
            command: "/bin/sh",
            arguments: ["-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"],
            onOutput: { [weak self] in self?.emit($0) }
        )
        return code == 0
    }

    private func step(_ command: String, _ arguments: [String], label: String) -> Bool {
        emit(label + "\n")
        let code = runner.run(command: command, arguments: arguments,
                              onOutput: { [weak self] in self?.emit($0) })
        return code == 0
    }

    private func emit(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onOutput?(text) }
    }
}
