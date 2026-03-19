import Foundation
import MLXManager

/// Thin adapter: public API for the app layer, delegates to `EnvironmentBootstrapper`.
final class EnvironmentInstaller {

    static let venvPath   = EnvironmentBootstrapper.venvPath
    static let pythonPath = EnvironmentBootstrapper.pythonPath

    var onOutput: ((String) -> Void)? {
        didSet { bootstrapper.onOutput = onOutput }
    }
    var onComplete: ((Bool) -> Void)? {
        didSet { bootstrapper.onComplete = onComplete }
    }

    private let bootstrapper: EnvironmentBootstrapper

    init() {
        bootstrapper = EnvironmentBootstrapper(runner: ProcessCommandRunner())
    }

    func install() {
        bootstrapper.install()
    }

    func cancel() {
        // EnvironmentBootstrapper runs on a GCD queue; cancellation is best-effort
        // (the current step will finish, then onComplete is not called).
        bootstrapper.onComplete = nil
        bootstrapper.onOutput = nil
    }
}
