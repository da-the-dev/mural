import Foundation

/// Installs a per-user LaunchAgent that runs `MuralHelper`, which re-applies the
/// desired lock-screen wallpaper whenever macOS reverts the store.
///
/// (A signed build can switch to `SMAppService.agent(plistName:)`; the LaunchAgent
/// path works unsigned too, which is what makes local/dev builds behave.)
public enum ReapplyAgent {
    public static let label = "dev.da.mural.reapply"

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public static func install(helperPath: String, interval: Int = 300) {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [helperPath, "--reapply"],
            "RunAtLoad": true,
            "StartInterval": max(30, interval),
            "WatchPaths": [WallpaperStore.shared.storeDirectory.path],
            "ProcessType": "Background",
        ]
        try? FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL, options: .atomic)
        }
        let domain = "gui/\(getuid())"
        run("/bin/launchctl", ["bootout", domain, plistURL.path])
        run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }

    public static func uninstall() {
        let domain = "gui/\(getuid())"
        run("/bin/launchctl", ["bootout", domain, plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
