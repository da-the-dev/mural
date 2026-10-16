import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DesktopView: View {
    @Environment(AppModel.self) private var model
    @State private var showImage = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Group {
                    if let url = model.desktopURL, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.15)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                GlassEffectContainer {
                    HStack {
                        Button { showImage = true } label: {
                            Label("Choose desktop picture…", systemImage: "photo")
                        }
                        .buttonStyle(.glass)
                        Spacer()
                    }
                }

                GlassCard(title: "Note") {
                    Text("The Desktop uses the classic macOS picture setting. The Lock Screen mirrors it; use the Lock Screen tab to give the saver a different look.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Desktop")
        .fileImporter(isPresented: $showImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                model.setDesktopImage(url)
            }
        }
    }
}
