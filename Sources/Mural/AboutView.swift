import SwiftUI

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text("Mural").font(.largeTitle.weight(.semibold))
                    Text("Your Lock Screen, your wallpaper.").foregroundStyle(.secondary)
                    Text("Version \(version)").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.top, 12)

                GlassCard(title: "What it does") {
                    Text("Mural sets the macOS screen saver to your own photo or video, independent of the desktop — the closest macOS 26 allows to a separate Lock Screen wallpaper.")
                        .foregroundStyle(.secondary)
                    Text("It was reverse-engineered from the macOS 26 wallpaper store, the screen-saver notification, and the aerial manifest.")
                        .foregroundStyle(.secondary)
                }

                GlassCard(title: "Privacy") {
                    Text("Everything happens locally. Mural doesn't collect or send any data.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("About")
    }
}
