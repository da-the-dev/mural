import Foundation
import AppKit

// MARK: - Models

/// A wallpaper choice: a provider id plus its nested binary-plist configuration.
public struct WallpaperChoice: Sendable, Equatable {
    public var provider: String
    public var configuration: Data

    public init(provider: String, configuration: Data = Data()) {
        self.provider = provider
        self.configuration = configuration
    }

    public static let macintosh = WallpaperChoice(provider: WallpaperProvider.macintosh)

    /// Still image (desktop or lock screen).
    public static func image(_ url: URL) throws -> WallpaperChoice {
        let config: [String: Any] = ["type": "imageFile", "url": ["relative": url.absoluteString]]
        let data = try PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)
        return WallpaperChoice(provider: WallpaperProvider.image, configuration: data)
    }

    /// Live aerial (registered asset id).
    public static func aerial(_ assetID: String) throws -> WallpaperChoice {
        let data = try PropertyListSerialization.data(fromPropertyList: ["assetID": assetID],
                                                      format: .binary, options: 0)
        return WallpaperChoice(provider: WallpaperProvider.aerials, configuration: data)
    }
}

public enum WallpaperProvider {
    public static let image = "com.apple.wallpaper.choice.image"
    public static let aerials = "com.apple.wallpaper.choice.aerials"
    public static let macintosh = "com.apple.wallpaper.choice.macintosh"
    public static let color = "com.apple.wallpaper.choice.color"
}

public enum WallpaperError: Error, LocalizedError {
    case storeNotFound
    case malformedStore
    case noDisplays
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .storeNotFound: return "The macOS wallpaper store was not found."
        case .malformedStore: return "The wallpaper store could not be parsed."
        case .noDisplays: return "No displays were found in the wallpaper store."
        case .encodeFailed(let m): return "Video encoding failed: \(m)"
        }
    }
}

// MARK: - Store

/// Reads and writes the macOS 26 wallpaper store
/// (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`).
///
/// The `Idle` project inside the store is what the system plays as the screen
/// saver, which is what shows over the Lock Screen. macOS also periodically
/// reverts it, so `MuralHelper` re-applies the user's choice.
public final class WallpaperStore {
    public static let shared = WallpaperStore()

    public let storeURL: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        storeURL = home.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    public var storeDirectory: URL { storeURL.deletingLastPathComponent() }

    // MARK: Load / save

    public func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw WallpaperError.storeNotFound
        }
        let data = try Data(contentsOf: storeURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else { throw WallpaperError.malformedStore }
        return dict
    }

    public func save(_ store: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
        try data.write(to: storeURL, options: .atomic)
    }

    // MARK: Idle (Lock Screen / screen saver)

    /// Applies `choice` to every `Idle` project in the store (Displays /
    /// SystemDefault / Spaces) and returns how many were written.
    @discardableResult
    public func setIdle(_ choice: WallpaperChoice, now: Date = Date()) throws -> Int {
        let store = try load()
        let template = optionTemplate(for: choice.provider, in: store)
        var count = 0
        func transform(_ node: Any) -> Any {
            if var dict = node as? [String: Any] {
                for (key, value) in dict {
                    if key == "Idle", var project = value as? [String: Any], project["Content"] != nil {
                        var content = project["Content"] as? [String: Any] ?? [:]
                        content["Choices"] = [[
                            "Provider": choice.provider,
                            "Files": [Any](),
                            "Configuration": choice.configuration,
                        ]]
                        content["EncodedOptionValues"] = template
                        if content["Shuffle"] == nil { content["Shuffle"] = "$null" }
                        project["Content"] = content
                        project["LastSet"] = now
                        project["LastUse"] = now
                        dict[key] = project
                        count += 1
                    } else {
                        dict[key] = transform(value)
                    }
                }
                return dict
            } else if let array = node as? [Any] {
                return array.map(transform)
            }
            return node
        }
        guard let updated = transform(store) as? [String: Any] else { throw WallpaperError.malformedStore }
        try save(updated)
        return count
    }

    /// True if every `Idle` project already equals `choice` (used by the re-apply helper).
    public func idleMatches(_ choice: WallpaperChoice) throws -> Bool {
        let store = try load()
        var found = false
        var matches = true
        Self.walkIdle(in: store) { project in
            found = true
            guard matches else { return }
            let choices = (project["Content"] as? [String: Any])?["Choices"] as? [[String: Any]]
            let first = choices?.first
            let provider = first?["Provider"] as? String
            let config = first?["Configuration"] as? Data ?? Data()
            if provider != choice.provider || config != choice.configuration { matches = false }
        }
        return found && matches
    }

    /// The active display's current `Idle` (Lock Screen / screen saver) choice.
    public func currentIdle() throws -> WallpaperChoice? {
        let store = try load()
        let displays = (store["Displays"] as? [String: Any]) ?? [:]
        let sorted = displays.values.compactMap { value -> (Date, [String: Any])? in
            guard let project = value as? [String: Any] else { return nil }
            let last = (project["Desktop"] as? [String: Any])?["LastUse"] as? Date ?? .distantPast
            return (last, project)
        }.sorted { $0.0 > $1.0 }
        guard let (_, project) = sorted.first else { throw WallpaperError.noDisplays }
        guard let idle = project["Idle"] as? [String: Any],
              let content = idle["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let first = choices.first,
              let provider = first["Provider"] as? String else { return nil }
        return WallpaperChoice(provider: provider, configuration: first["Configuration"] as? Data ?? Data())
    }

    public var displayCount: Int {
        ((try? load()).flatMap { ($0["Displays"] as? [String: Any])?.count }) ?? 0
    }

    // MARK: Desktop

    /// Sets the desktop picture on every screen (the classic `NSWorkspace` path -
    /// no Automation permission needed).
    public func setDesktopImage(_ url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    public func currentDesktopImage() -> URL? {
        NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    // MARK: Reload

    /// Restarts WallpaperAgent so it reloads the store. Briefly flashes the wallpaper.
    public func restartAgent() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["WallpaperAgent"]
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: Helpers

    private func optionTemplate(for provider: String, in store: [String: Any]) -> Data {
        var found: Data?
        var fallback: Data?
        Self.walkIdle(in: store) { project in
            guard let content = project["Content"] as? [String: Any] else { return }
            let choices = content["Choices"] as? [[String: Any]]
            let p = choices?.first?["Provider"] as? String
            if let eov = content["EncodedOptionValues"] as? Data, !eov.isEmpty {
                if p == provider, found == nil { found = eov }
                if fallback == nil { fallback = eov }
            }
        }
        return found ?? fallback ?? (try? PropertyListSerialization.data(
            fromPropertyList: ["values": [String: Any]()], format: .binary, options: 0)) ?? Data()
    }

    /// Visits every `Idle` project.
    static func walkIdle(in node: Any, _ visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if key == "Idle", let project = value as? [String: Any], project["Content"] != nil {
                    visit(project)
                } else {
                    walkIdle(in: value, visit)
                }
            }
        } else if let array = node as? [Any] {
            for item in array { walkIdle(in: item, visit) }
        }
    }
}
