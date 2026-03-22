import Foundation

/// Bootstraps the managed Python environment using `uv`.
///
/// Each backend gets its own venv:
/// - mlxLM:  ~/.mlx-manager/venv      (installs mlx-lm)
/// - mlxVLM: ~/.mlx-manager/venv-vlm  (installs mlx-vlm)
public final class EnvironmentBootstrapper {

    public var onOutput: ((String) -> Void)?
    public var onComplete: ((Bool) -> Void)?

    private let backend: ServerType
    private let uvLocator: UVLocator
    private let runner: CommandRunner
    private let uvInstallCommand: (() -> Bool)?

    public static func venvPath(for backend: ServerType) -> String {
        switch backend {
        case .mlxLM:  return NSString("~/.mlx-manager/venv").expandingTildeInPath
        case .mlxVLM: return NSString("~/.mlx-manager/venv-vlm").expandingTildeInPath
        }
    }

    public static func pythonPath(for backend: ServerType) -> String {
        venvPath(for: backend) + "/bin/python"
    }

    // Legacy accessors (mlxLM defaults) for backwards compatibility
    public static var venvPath: String { venvPath(for: .mlxLM) }
    public static var pythonPath: String { pythonPath(for: .mlxLM) }

    public init(
        backend: ServerType = .mlxLM,
        uvLocator: UVLocator = UVLocator(),
        runner: CommandRunner,
        uvInstallCommand: (() -> Bool)? = nil
    ) {
        self.backend = backend
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
        guard let uvPath = resolveUV() else {
            emit("Error: could not locate or install uv\n")
            DispatchQueue.main.async { self.onComplete?(false) }
            return
        }

        let venv = Self.venvPath(for: backend)
        let python = Self.pythonPath(for: backend)
        let package = backend == .mlxLM ? "mlx-lm" : "mlx-vlm"

        let venvOK = step(uvPath, ["venv", venv, "--python", "3.12"], label: "Creating venv…")
        guard venvOK else {
            DispatchQueue.main.async { self.onComplete?(false) }
            return
        }

        let installOK = step(uvPath, ["pip", "install", package, "--python", python],
                             label: "Installing \(package)…")
        DispatchQueue.main.async { self.onComplete?(installOK) }
    }

    private func resolveUV() -> String? {
        if let path = uvLocator.locate() { return path }
        emit("uv not found. Installing uv…\n")
        let installer = uvInstallCommand ?? defaultUVInstaller
        guard installer() else { return nil }
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
