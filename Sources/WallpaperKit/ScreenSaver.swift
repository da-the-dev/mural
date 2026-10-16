import Foundation

/// Starts the screen saver and manages the "lock on saver" / idle-time settings.
public enum ScreenSaver {

    /// Asks the system to start the screen saver.
    ///
    /// Reverse-engineered from the Dock (`-[HotCorners _postScreenSaverNotification:1]`):
    /// a distributed notification `com.apple.screensaver.action` with `{ "action": 1 }`,
    /// observed by `loginwindow`. If "require password" is immediate, this also locks.
    public static func start() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.screensaver.action"),
            object: nil,
            userInfo: ["action": 1],
            deliverImmediately: true)
    }

    /// Whether the Mac locks when the saver starts (`askForPassword`).
    public static func lockOnStart() -> Bool {
        (defaultsRead("askForPassword") as? Int ?? 0) != 0
    }

    public static func setLockOnStart(_ enabled: Bool) {
        defaultsWrite("askForPassword", int: enabled ? 1 : 0)
        defaultsWrite("askForPasswordDelay", int: 0)
    }

    /// Seconds of inactivity before the saver starts (`idleTime`). 0 = never.
    public static func idleTime() -> Int {
        defaultsRead("idleTime") as? Int ?? 120
    }

    public static func setIdleTime(_ seconds: Int) {
        defaultsWrite("idleTime", int: max(0, seconds))
    }

    // MARK: - defaults helpers (currentHost domain com.apple.screensaver)

    private static func defaultsWrite(_ key: String, int value: Int) {
        run("/usr/bin/defaults", ["-currentHost", "write", "com.apple.screensaver", key, "-int", String(value)])
    }

    private static func defaultsRead(_ key: String) -> Any? {
        let out = run("/usr/bin/defaults", ["-currentHost", "read", "com.apple.screensaver", key])
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
