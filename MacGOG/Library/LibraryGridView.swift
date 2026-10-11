import SwiftUI
import SwiftyGOG

/// A searchable grid of games, filtered by the sidebar selection.
struct LibraryGridView: View {
    let filter: SidebarItem
    @Binding var path: [String]

    @Environment(AppModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @Environment(InstallRegistry.self) private var registry
    @State private var search = ""

    private var items: [LibraryItem] {
        model.libraryItems.filter { item in
            let matchesFilter =
                switch filter {
                case .all, .downloads: true
                case .installed: registry.record(for: item.id) != nil
                case .updates: registry.updates[item.id] != nil
                case .platform(let platform): item.platforms.contains(platform)
                }
            return matchesFilter && (search.isEmpty || item.title.localizedStandardContains(search))
        }
    }

    var body: some View {
        let items = items
        ScrollView {
            if case .failed(let error) = library.state {
                ErrorBanner(error: error) { Task { await model.refreshLibrary() } }
                    .padding([.horizontal, .top])
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20)], spacing: 24) {
                ForEach(items) { item in
                    Button {
                        path.append(item.id)
                    } label: {
                        GameTile(item: item, status: model.status(of: item.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { GameContextMenu(id: item.id) }
                }
            }
            .padding(20)
        }
        .overlay {
            if items.isEmpty {
                emptyState
            }
        }
        .navigationTitle(filter.title)
        .navigationSubtitle(subtitle(count: items.count))
        .searchable(text: $search, placement: .toolbar, prompt: "Search games")
        .toolbar {
            ToolbarItemGroup {
                if filter == .updates || filter == .installed {
                    Button {
                        Task { await model.checkForUpdates() }
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.down.circle")
                    }
                    .disabled(registry.isCheckingForUpdates)
                }
                Button {
                    Task { await model.refreshLibrary() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(library.isLoading)
            }
        }
    }

    private func subtitle(count: Int) -> String {
        if library.isLoading {
            return "Refreshing…"
        }
        if registry.isCheckingForUpdates {
            return "Checking for updates…"
        }
        return count == 1 ? "1 game" : "\(count) games"
    }

    @ViewBuilder private var emptyState: some View {
        if library.isLoading && library.games.isEmpty {
            ProgressView("Loading your library…")
        } else if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            switch filter {
            case .updates:
                ContentUnavailableView(
                    "No updates",
                    systemImage: "checkmark.circle",
                    description: Text("Installed games are up to date.")
                )
            case .installed:
                ContentUnavailableView(
                    "No installed games",
                    systemImage: "internaldrive",
                    description: Text(
                        "Install a game, or add one you already have with File > Add Existing Game."
                    )
                )
            default:
                ContentUnavailableView("No games", systemImage: "gamecontroller")
            }
        }
    }
}

/// One game's artwork, title, platforms, and status.
struct GameTile: View {
    let item: LibraryItem
    let status: GameStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // GOG's library tiles are 392×220.
            ArtworkImage(url: item.imageURL)
                .aspectRatio(392 / 220, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if let label = status.label {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                status.isAttention ? AnyShapeStyle(.red) : AnyShapeStyle(.tint),
                                in: .capsule
                            )
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if case .installing(let job) = status, job.isRunning, let fraction = job.progress.fraction
                    {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .padding(8)
                    }
                }
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            Text(item.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                ForEach(item.platforms, id: \.self) { platform in
                    Image(systemName: platform.symbolName)
                        .help(platform.displayName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

/// Quick actions for a game in the grid.
struct GameContextMenu: View {
    let id: String

    @Environment(AppModel.self) private var model

    var body: some View {
        if let record = model.registry.record(for: id) {
            if model.launcher.isRunning(id) {
                Button("Stop") { model.launcher.stop(id) }
            } else {
                Button("Play") {
                    Task {
                        do {
                            try await model.launcher.launch(record)
                        } catch {
                            model.present(error)
                        }
                    }
                }
                .disabled(model.launcher.blocker(for: record) != nil)
            }
            if model.registry.updates[id] != nil {
                Button("Update") { model.update(record) }
            }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([record.entry.folder])
            }
        }
    }
}

/// An inline error with an optional retry.
struct ErrorBanner: View {
    let error: PresentableError
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text(error.title)
                    .font(.headline)
                Text(error.message)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let retry, error.recoveries.contains(.retry) {
                Button("Try Again", action: retry)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }
}

#Preview("Library") {
    NavigationStack {
        LibraryGridView(filter: .all, path: .constant([]))
    }
    .modelEnvironment(.preview())
    .frame(width: 900, height: 600)
}

#Preview("Empty updates") {
    NavigationStack {
        LibraryGridView(filter: .updates, path: .constant([]))
    }
    .modelEnvironment(.preview(installed: false, downloading: false))
    .frame(width: 900, height: 600)
}

#Preview("Tile", traits: .sizeThatFitsLayout) {
    GameTile(
        item: LibraryItem(
            id: "1",
            title: "The Witcher: Enhanced Edition",
            platforms: [.windows, .osx],
            imageURL: nil
        ),
        status: .installed
    )
    .frame(width: 260)
    .padding()
    .modelEnvironment(.preview())
}
