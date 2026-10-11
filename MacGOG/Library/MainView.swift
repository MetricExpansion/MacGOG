import SwiftUI
import SwiftyGOG

/// A section of the sidebar.
enum SidebarItem: Hashable {
    case all
    case installed
    case updates
    case platform(GamePlatform)
    case downloads

    var title: String {
        switch self {
        case .all: "All Games"
        case .installed: "Installed"
        case .updates: "Updates"
        case .platform(let platform): platform.displayName
        case .downloads: "Downloads"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .installed: "internaldrive"
        case .updates: "arrow.down.circle"
        case .platform(let platform): platform.symbolName
        case .downloads: "arrow.down.square"
        }
    }
}

/// The signed-in window: a sidebar of filters and the library or downloads.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(DownloadQueue.self) private var downloads
    @Environment(InstallRegistry.self) private var registry
    @State private var selection: SidebarItem? = .all
    @State private var path: [String] = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    row(.all)
                    row(.installed, count: registry.records.count)
                    row(.updates, count: registry.updates.count)
                }
                Section("Platforms") {
                    ForEach(GamePlatform.allCases, id: \.self) { row(.platform($0)) }
                }
                Section("Activity") {
                    row(.downloads, count: downloads.unfinishedJobs.count)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    switch selection ?? .all {
                    case .downloads:
                        DownloadsView()
                    case let filter:
                        LibraryGridView(filter: filter, path: $path)
                    }
                }
                .navigationDestination(for: String.self) { id in
                    GameDetailView(id: id)
                }
            }
        }
        .onChange(of: selection) { path = [] }
        .safeAreaInset(edge: .top, spacing: 0) {
            if downloads.restoredCount > 0 {
                RestoreBanner(count: downloads.restoredCount)
            }
        }
    }

    private func row(_ item: SidebarItem, count: Int = 0) -> some View {
        Label(item.title, systemImage: item.symbolName)
            .badge(count)
            .tag(item)
    }
}

/// Offers to resume downloads left unfinished when the app last quit.
private struct RestoreBanner: View {
    @Environment(DownloadQueue.self) private var downloads
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.tint)
            Text(count == 1 ? "1 download didn't finish." : "\(count) downloads didn't finish.")
            Spacer()
            Button("Not Now") { downloads.dismissRestored() }
            Button("Resume") { downloads.resumeAll() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview {
    MainView()
        .modelEnvironment(.preview())
        .frame(width: 1100, height: 720)
}
