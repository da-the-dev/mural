import Foundation

/// The lock-screen choice the user wants, persisted so `MuralHelper` can
/// re-apply it whenever macOS reverts the store.
public struct DesiredState: Codable, Sendable {
    public var provider: String
    public var configurationBase64: String

    public init(provider: String, configuration: Data) {
        self.provider = provider
        self.configurationBase64 = configuration.base64EncodedString()
    }

    public init(_ choice: WallpaperChoice) {
        self.init(provider: choice.provider, configuration: choice.configuration)
    }

    public var choice: WallpaperChoice {
        WallpaperChoice(provider: provider,
                        configuration: Data(base64Encoded: configurationBase64) ?? Data())
    }
}

public enum DesiredStateStore {
    public static var directory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mural", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static var url: URL { directory.appendingPathComponent("desired.json") }

    public static func save(_ state: DesiredState) {
        try? JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    public static func load() -> DesiredState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DesiredState.self, from: data)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
