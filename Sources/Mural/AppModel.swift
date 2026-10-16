import SwiftUI
import Observation
import WallpaperKit

@Observable
final class AppModel {
    // Current state
    var lockChoice: WallpaperChoice?
    var lockSummary: String = "Unknown"
    var builtins: [AerialAsset] = []
    var desktopURL: URL?

    // Settings
    var lockOnStart: Bool = ScreenSaver.lockOnStart()
    var idleTime: Int = ScreenSaver.idleTime()
    var keepActive: Bool = ReapplyAgent.isInstalled()

    // Feedback
    var isBusy = false
    var status: String?
    var errorMessage: String?

    init() { refresh() }

    var helperPath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "Mural"
    }

    // MARK: Load

    func refresh() {
        do {
            lockChoice = try WallpaperStore.shared.currentIdle()
            lockSummary = Self.describe(try WallpaperStore.shared.currentIdle())
        } catch {
            lockSummary = "Unknown"
        }
        builtins = (try? AerialCatalog.listBuiltIn()) ?? []
        desktopURL = WallpaperStore.shared.currentDesktopImage()
        lockOnStart = ScreenSaver.lockOnStart()
        idleTime = ScreenSaver.idleTime()
        keepActive = ReapplyAgent.isInstalled()
    }

    static func describe(_ choice: WallpaperChoice?) -> String {
        guard let choice else { return "None" }
        switch choice.provider {
        case WallpaperProvider.macintosh: return "Macintosh (default)"
        case WallpaperProvider.image:
            if let cfg = try? PropertyListSerialization.propertyList(from: choice.configuration, options: [], format: nil) as? [String: Any],
               let url = (cfg["url"] as? [String: Any])?["relative"] as? String {
                return (URL(string: url)?.lastPathComponent) ?? "Image"
            }
            return "Image"
        case WallpaperProvider.aerials:
            if let cfg = try? PropertyListSerialization.propertyList(from: choice.configuration, options: [], format: nil) as? [String: Any],
               let id = cfg["assetID"] as? String {
                return builtinLabel(for: id)
            }
            return "Live aerial"
        default:
            return choice.provider
        }
    }

    private static func builtinLabel(for id: String) -> String {
        (try? AerialCatalog.listBuiltIn())?.first(where: { $0.id == id })?.label ?? "Live aerial"
    }

    // MARK: Apply lock screen

    private func applyLock(_ choice: WallpaperChoice, note: String) {
        do {
            let count = try WallpaperStore.shared.setIdle(choice)
            DesiredStateStore.save(DesiredState(choice))
            WallpaperStore.shared.restartAgent()
            status = "\(note) — applied to \(count) display projects"
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLockImage(_ url: URL) {
        guard let choice = try? WallpaperChoice.image(url) else { return }
        applyLock(choice, note: "Lock Screen set to \(url.lastPathComponent)")
    }

    func setLockBuiltin(_ asset: AerialAsset) {
        guard let choice = try? WallpaperChoice.aerial(asset.id) else { return }
        applyLock(choice, note: "Lock Screen set to \(asset.label)")
    }

    func setLockMacintosh() {
        applyLock(.macintosh, note: "Lock Screen set to the Macintosh default")
    }

    func setLockVideo(_ url: URL, title: String? = nil) {
        isBusy = true
        status = "Encoding \(url.lastPathComponent) to HEVC…"
        Task {
            do {
                let name = title ?? url.deletingPathExtension().lastPathComponent
                let assetID = try await AerialCatalog.register(video: url, title: name)
                let choice = try WallpaperChoice.aerial(assetID)
                applyLock(choice, note: "Lock Screen set to “\(name)”")
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    // MARK: Desktop

    func setDesktopImage(_ url: URL) {
        do {
            try WallpaperStore.shared.setDesktopImage(url)
            status = "Desktop set to \(url.lastPathComponent)"
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Saver / settings

    func lockNow() { ScreenSaver.start() }

    func applySettings() {
        ScreenSaver.setLockOnStart(lockOnStart)
        ScreenSaver.setIdleTime(idleTime)
        status = "Settings saved"
    }

    func setKeepActive(_ on: Bool) {
        if on {
            ReapplyAgent.install(helperPath: helperPath)
            status = "Keeping your wallpaper active in the background"
        } else {
            ReapplyAgent.uninstall()
            status = "Background keeper turned off"
        }
        keepActive = ReapplyAgent.isInstalled()
    }
}
