import SwiftUI
import UniformTypeIdentifiers
import WallpaperKit

struct LockScreenView: View {
    @Environment(AppModel.self) private var model
    @State private var showImage = false
    @State private var showVideo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LockPreview(summary: model.lockSummary)

                if let status = model.status {
                    StatusBanner(text: status, isError: false)
                }
                if let error = model.errorMessage {
                    StatusBanner(text: error, isError: true)
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button { showImage = true } label: {
                            Label("Choose image…", systemImage: "photo")
                        }
                        .buttonStyle(.glass)

                        Button { showVideo = true } label: {
                            Label("Choose video…", systemImage: "video")
                        }
                        .buttonStyle(.glass)

                        Button { model.setLockMacintosh() } label: {
                            Label("Macintosh", systemImage: "apple.logo")
                        }
                        .buttonStyle(.glass)

                        Spacer()

                        Button { model.lockNow() } label: {
                            Label("Lock now", systemImage: "lock.fill")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }

                GlassCard(title: "How this works") {
                    Text("Mural sets the **screen saver**, which is what the Lock Screen shows once the saver starts. macOS keeps the lock-screen background tied to your desktop picture, so the saver is the layer you can make different.")
                        .foregroundStyle(.secondary)
                    Text("With “Require password when the saver starts” enabled, locking (or starting the saver) gives you your own Lock Screen wallpaper **and** a locked Mac.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Lock Screen")
        .overlay {
            if model.isBusy {
                ProgressView("Encoding video…")
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
        .fileImporter(isPresented: $showImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                model.setLockImage(url)
            }
        }
        .fileImporter(isPresented: $showVideo, allowedContentTypes: [.movie]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                model.setLockVideo(url)
            }
        }
    }
}
