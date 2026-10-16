import SwiftUI
import WallpaperKit

struct BuiltInView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                BuiltinTile(title: "Macintosh",
                            subtitle: "Default",
                            preview: nil,
                            selected: model.lockChoice?.provider == WallpaperProvider.macintosh) {
                    model.setLockMacintosh()
                }
                ForEach(model.builtins) { asset in
                    BuiltinTile(title: asset.label,
                                subtitle: "Live aerial",
                                preview: asset.previewURL,
                                selected: isSelected(asset)) {
                        model.setLockBuiltin(asset)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Built-in")
    }

    private func isSelected(_ asset: AerialAsset) -> Bool {
        guard let choice = model.lockChoice, choice.provider == WallpaperProvider.aerials,
              let cfg = try? PropertyListSerialization.propertyList(from: choice.configuration, options: [], format: nil) as? [String: Any],
              let id = cfg["assetID"] as? String else { return false }
        return id == asset.id
    }
}

private struct BuiltinTile: View {
    var title: String
    var subtitle: String
    var preview: URL?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let preview {
                        AsyncImage(url: preview) { phase in
                            switch phase {
                            case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                            default: Color.black.opacity(0.25)
                            }
                        }
                    } else {
                        LinearGradient(colors: [Color(red: 0.12, green: 0.15, blue: 0.22),
                                                Color(red: 0.45, green: 0.42, blue: 0.36)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .glassEffect(selected ? .regular.tint(.accentColor) : .regular,
                         in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
