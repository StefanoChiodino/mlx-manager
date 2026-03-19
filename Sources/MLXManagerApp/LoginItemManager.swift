import Foundation

/// Manages the LaunchAgent plist for "Start at login" support.
enum LoginItemManager {

    private static let label = "com.stefano.mlx-manager"
    private static var plistDest: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Copies the bundled LaunchAgent.plist into ~/Library/LaunchAgents/ and loads it.
    static func enable() {
        guard let src = plistSourceURL() else { return }
        let dest = plistDest
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: src, to: dest)
        launchctl("load", dest.path)
    }

    /// Unloads the LaunchAgent and removes its plist.
    static func disable() {
        let dest = plistDest
        launchctl("unload", dest.path)
        try? FileManager.default.removeItem(at: dest)
    }

    /// Returns true if the plist file is present in ~/Library/LaunchAgents/.
    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistDest.path)
    }

    // MARK: - Private

    private static func plistSourceURL() -> URL? {
        if let url = Bundle.main.url(forResource: "LaunchAgent", withExtension: "plist") { return url }
        return Bundle.module.url(forResource: "LaunchAgent", withExtension: "plist")
    }

    private static func launchctl(_ verb: String, _ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = [verb, path]
        try? p.run()
        p.waitUntilExit()
    }
}
