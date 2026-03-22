import Foundation
import MLXManager

/// Thin adapter: public API for the app layer, delegates to `EnvironmentBootstrapper`.
final class EnvironmentInstaller {

    static func venvPath(for backend: ServerType) -> String {
        EnvironmentBootstrapper.venvPath(for: backend)
    }

    static func pythonPath(for backend: ServerType) -> String {
        EnvironmentBootstrapper.pythonPath(for: backend)
    }

    // Legacy (mlxLM default) for any call sites not yet updated
    static var venvPath: String { venvPath(for: .mlxLM) }
    static var pythonPath: String { pythonPath(for: .mlxLM) }

    var onOutput: ((String) -> Void)? {
        didSet { bootstrapper.onOutput = onOutput }
    }
    var onComplete: ((Bool) -> Void)? {
        didSet { bootstrapper.onComplete = onComplete }
    }

    private let bootstrapper: EnvironmentBootstrapper

    init(backend: ServerType = .mlxLM) {
        bootstrapper = EnvironmentBootstrapper(backend: backend, runner: ProcessCommandRunner())
    }

    func install() { bootstrapper.install() }

    func cancel() {
        // EnvironmentBootstrapper runs on a GCD queue; cancellation is best-effort
        // (the current step will finish, then onComplete is not called).
        bootstrapper.onComplete = nil
        bootstrapper.onOutput = nil
    }
}
