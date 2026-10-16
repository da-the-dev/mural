import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Lock Screen Now") { model.lockNow() }
        Divider()
        Text("Lock Screen: \(model.lockSummary)")
        Divider()
        Button("Quit Mural") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
