import Foundation

public struct AerialAsset: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let previewURL: URL?
    public init(id: String, label: String, previewURL: URL?) {
        self.id = id
        self.label = label
        self.previewURL = previewURL
    }
}

/// Reads and writes the aerial manifest so Mural can offer the built-in Apple
/// aerials and register the user's own videos as custom aerials.
public enum AerialCatalog {

    public static var aerialsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials", isDirectory: true)
    }
    public static var manifestURL: URL { aerialsDirectory.appendingPathComponent("manifest/entries.json") }
    public static var videosDirectory: URL { aerialsDirectory.appendingPathComponent("videos", isDirectory: true) }

    private static let customCategoryID = "A1B2C3D4-0001-4000-8000-000000000001"
    private static let customSubcategoryID = "A1B2C3D4-0002-4000-8000-000000000002"
    private static let customCategoryName = "Mural"

    // MARK: Read

    public static func listBuiltIn() throws -> [AerialAsset] {
        guard let data = try? Data(contentsOf: manifestURL),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]] else {
            return []
        }
        return assets.compactMap { asset in
            guard let id = asset["id"] as? String else { return nil }
            let label = (asset["accessibilityLabel"] as? String)
                ?? (asset["localizedNameKey"] as? String) ?? id
            let preview = (asset["previewImage"] as? String).flatMap(URL.init(string:))
            return AerialAsset(id: id, label: label, previewURL: preview)
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    // MARK: Write (register a custom video as an aerial)

    @discardableResult
    public static func register(video source: URL, title: String) async throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: videosDirectory, withIntermediateDirectories: true)

        let assetID = UUID().uuidString
        let movieURL = videosDirectory.appendingPathComponent("\(assetID).mov")
        let previewURL = videosDirectory.appendingPathComponent("\(assetID)-preview.png")

        try await VideoTranscoder.transcodeToHEVC(source, to: movieURL)
        try await VideoTranscoder.writePreview(of: movieURL, to: previewURL)

        var root: [String: Any]
        if let data = try? Data(contentsOf: manifestURL),
           let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        } else {
            root = ["version": 1, "assets": [Any](), "categories": [Any]()]
        }

        var categories = root["categories"] as? [[String: Any]] ?? []
        if !categories.contains(where: { $0["id"] as? String == customCategoryID }) {
            categories.insert(category(previewURL: previewURL, representative: assetID), at: 0)
        } else if let idx = categories.firstIndex(where: { $0["id"] as? String == customCategoryID }) {
            var subcategories = categories[idx]["subcategories"] as? [[String: Any]] ?? []
            if !subcategories.contains(where: { $0["id"] as? String == customSubcategoryID }) {
                subcategories.insert(subcategory(previewURL: previewURL, representative: assetID), at: 0)
                categories[idx]["subcategories"] = subcategories
            }
        }
        root["categories"] = categories

        var assets = root["assets"] as? [[String: Any]] ?? []
        assets.removeAll { $0["id"] as? String == assetID }
        assets.insert(asset(id: assetID, title: title, movieURL: movieURL, previewURL: previewURL), at: 0)
        root["assets"] = assets

        let out = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try out.write(to: manifestURL, options: .atomic)
        return assetID
    }

    // MARK: Asset / category shapes

    private static func asset(id: String, title: String, movieURL: URL, previewURL: URL) -> [String: Any] {
        [
            "id": id,
            "url-4K-SDR-240FPS": movieURL.absoluteString,
            "previewImage": previewURL.absoluteString,
            "accessibilityLabel": title,
            "localizedNameKey": title,
            "categories": [customCategoryID],
            "subcategories": [customSubcategoryID],
            "preferredOrder": 0,
            "includeInShuffle": false,
            "showInTopLevel": true,
            "pointsOfInterest": [String: Any](),
            "shotID": title,
        ]
    }

    private static func category(previewURL: URL, representative: String) -> [String: Any] {
        [
            "id": customCategoryID,
            "localizedDescriptionKey": "\(customCategoryName)Description",
            "localizedNameKey": customCategoryName,
            "preferredOrder": 0,
            "previewImage": previewURL.absoluteString,
            "representativeAssetID": representative,
            "subcategories": [subcategory(previewURL: previewURL, representative: representative)],
        ]
    }

    private static func subcategory(previewURL: URL, representative: String) -> [String: Any] {
        [
            "id": customSubcategoryID,
            "localizedDescriptionKey": "\(customCategoryName)SubDescription",
            "localizedNameKey": "\(customCategoryName)Sub",
            "preferredOrder": -1,
            "previewImage": previewURL.absoluteString,
            "representativeAssetID": representative,
        ]
    }
}
