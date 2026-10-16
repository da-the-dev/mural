import SwiftUI
import WallpaperKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Locking") {
                    Toggle("Require password when the screen saver starts", isOn: Binding(
                        get: { model.lockOnStart },
                        set: { model.lockOnStart = $0; model.applySettings() }))

                    HStack {
                        Text("Start screen saver after")
                        Spacer()
                        Stepper(value: Binding(
                            get: { model.idleTime },
                            set: { model.idleTime = $0; model.applySettings() }),
                                in: 0...3600, step: 30) {
                            Text(model.idleTime == 0 ? "Never" : "\(model.idleTime) s")
                                .monospacedDigit()
                        }
                    }

                    Text("0 = never. A shorter delay makes your Lock Screen wallpaper appear sooner after you lock.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                GlassCard(title: "Keep it active") {
                    Toggle("Keep my Lock Screen wallpaper in the background", isOn: Binding(
                        get: { model.keepActive },
                        set: { model.setKeepActive($0) }))
                    Text("macOS periodically resets the wallpaper store. Mural installs a tiny background agent that re-applies your choice, so it never silently reverts.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                GlassEffectContainer {
                    HStack(spacing: 12) {
                        Button { model.applySettings() } label: {
                            Label("Save settings", systemImage: "checkmark")
                        }
                        .buttonStyle(.glassProminent)

                        Button { model.lockNow() } label: {
                            Label("Start saver now", systemImage: "play.fill")
                        }
                        .buttonStyle(.glass)

                        Spacer()
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Settings")
    }
}
