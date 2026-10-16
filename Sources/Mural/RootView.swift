import SwiftUI

enum MuralSection: String, CaseIterable, Identifiable {
    case lockScreen = "Lock Screen"
    case desktop = "Desktop"
    case builtIn = "Built-in"
    case settings = "Settings"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .lockScreen: return "lock.rectangle.on.rectangle"
        case .desktop: return "display"
        case .builtIn: return "photo.on.rectangle.angled"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: MuralSection? = .lockScreen

    var body: some View {
        NavigationSplitView {
            List(MuralSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .background(.background)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .lockScreen {
        case .lockScreen: LockScreenView()
        case .desktop: DesktopView()
        case .builtIn: BuiltInView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }
}
