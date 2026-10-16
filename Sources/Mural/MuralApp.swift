import SwiftUI
import WallpaperKit

@main
struct MuralApp: App {
    @State private var model = AppModel()

    init() {
        // Headless mode used by the background re-apply agent.
        if MuralReapply.handleIfRequested() {
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 960, height: 640)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Lock Screen Now") { model.lockNow() }
                    .keyboardShortcut("l", modifiers: [.control, .command])
            }
        }

        MenuBarExtra("Mural", systemImage: "sparkles.rectangle.stack.fill") {
            MenuBarView().environment(model)
        }
    }
}
