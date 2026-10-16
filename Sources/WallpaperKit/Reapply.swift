import Foundation

/// Headless re-apply entry point. The LaunchAgent (and the app itself, on launch)
/// invokes the app binary with `--reapply`; this re-applies the desired
/// lock-screen wallpaper if macOS reverted it, then the caller exits.
public enum MuralReapply {
    @discardableResult
    public static func handleIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--reapply") else { return false }
        run()
        return true
    }

    public static func run() {
        guard let desired = DesiredStateStore.load() else { return }
        let choice = desired.choice
        let store = WallpaperStore.shared
        do {
            if try !store.idleMatches(choice) {
                let count = try store.setIdle(choice)
                store.restartAgent()
                print("Mural: re-applied the Lock Screen wallpaper to \(count) projects")
            }
        } catch {
            FileHandle.standardError.write(Data("Mural reapply error: \(error)\n".utf8))
        }
    }
}
