import SwiftUI
import SwiftyGOG

/// A game's artwork, description, DLC, builds, installation, and actions.
struct GameDetailView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @Environment(InstallRegistry.self) private var registry
    @State private var details: ProductDetails?
    @State private var detailsError: PresentableError?
    @State private var sheet: InstallSheet.Mode?

    private var item: LibraryItem? { model.libraryItems.first { $0.id == id } }

    var body: some View {
        let record = registry.record(for: id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GameHeader(
                    id: id,
                    title: details?.title ?? item?.title ?? record?.title ?? "",
                    details: details
                )
                VStack(alignment: .leading, spacing: 24) {
                    GameActions(id: id, sheet: $sheet)
                    if let detailsError {
                        ErrorBanner(error: detailsError) { Task { await loadDetails() } }
                    }
                    if let record {
                        InstallationSection(record: record)
                        if record.installation != nil {
                            CloudSavesSection(record: record)
                        }
                    }
                    if let text = (details?.fullDescription ?? details?.lead).map(HTMLText.plainText),
                        !text.isEmpty
                    {
                        DetailSection("About") {
                            Text(text)
                                .textSelection(.enabled)
                                .frame(maxWidth: 720, alignment: .leading)
                        }
                    }
                    if let details, !details.dlcs.isEmpty {
                        DLCSection(details: details)
                    }
                    if let platform = record?.platform ?? details?.platforms.first(where: { $0 == .osx })
                        ?? details?.platforms.first,
                        platform != .linux
                    {
                        BuildsSection(id: id, platform: platform)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle(details?.title ?? item?.title ?? record?.title ?? "")
        .task(id: id) { await loadDetails() }
        .sheet(item: $sheet) { mode in
            InstallSheet(id: id, title: details?.title ?? item?.title ?? record?.title ?? "", mode: mode)
        }
    }

    private func loadDetails() async {
        do {
            details = try await library.details(for: id)
            detailsError = nil
        } catch {
            detailsError = presentableError(error)
        }
    }
}

private struct GameHeader: View {
    let id: String
    let title: String
    let details: ProductDetails?

    var body: some View {
        ArtworkImage(url: details?.images.background)
            .frame(height: 280)
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                    HStack(spacing: 10) {
                        ForEach(details?.platforms ?? [], id: \.self) { platform in
                            Label(platform.displayName, systemImage: platform.symbolName)
                        }
                        if let year = details?.releaseDate?.prefix(4) {
                            Text(year)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                }
                .padding(24)
            }
    }
}

/// The main buttons for a game, which depend on its installation status.
private struct GameActions: View {
    let id: String
    @Binding var sheet: InstallSheet.Mode?

    @Environment(AppModel.self) private var model
    @Environment(DownloadQueue.self) private var downloads
    @Environment(LaunchController.self) private var launcher
    @Environment(\.openSettings) private var openSettings
    @State private var confirmingUninstall = false

    var body: some View {
        let record = model.registry.record(for: id)
        HStack(spacing: 12) {
            switch model.status(of: id) {
            case .notInstalled:
                Button("Install…") { sheet = .install }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .installing(let job):
                JobControls(job: job)
            case .running:
                Button("Stop", role: .destructive) { launcher.stop(id) }
                    .controlSize(.large)
                ProgressView()
                    .controlSize(.small)
                Text("Playing")
                    .foregroundStyle(.secondary)
            case .installed, .updateAvailable:
                if let record {
                    PlayButton(record: record)
                    if let update = model.registry.updates[id] {
                        Button("Update to \(update.version ?? "the latest build")") { model.update(record) }
                            .controlSize(.large)
                    }
                    moreMenu(record)
                }
            case .foreign:
                if let record {
                    PlayButton(record: record)
                    Button("Verify with GOG…") { sheet = .adopt(record) }
                        .controlSize(.large)
                        .help("Check this game's files against GOG so MacGOG can update and repair it.")
                    moreMenu(record)
                }
            case .needsRepair:
                if let record {
                    Label(
                        "This game's install data is damaged.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button("Reinstall…") { sheet = .adopt(record) }
                        .buttonStyle(.borderedProminent)
                    moreMenu(record)
                }
            case .missing:
                if let record {
                    Label("The game folder is missing.", systemImage: "questionmark.folder.fill")
                        .foregroundStyle(.orange)
                    Button("Locate…") {
                        if let folder = FolderPicker.choose(message: "Find the folder of \(record.title).") {
                            Task { await model.locate(record, at: folder) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Remove from Library") { model.registry.remove(id) }
                }
            }
            Spacer()
        }
        .confirmationDialog(
            "Uninstall \(record?.title ?? "this game")?",
            isPresented: $confirmingUninstall
        ) {
            Button("Move to Trash", role: .destructive) {
                if let record {
                    Task { await model.uninstall(record) }
                }
            }
        } message: {
            Text("The game folder moves to the Trash. Cloud saves aren't affected.")
        }
    }

    private func moreMenu(_ record: InstalledGameRecord) -> some View {
        Menu {
            if record.installation != nil {
                Button("Verify and Repair") { model.repair(record) }
                Button("Change Language or DLC…") { sheet = .modify(record) }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([record.entry.folder])
            }
            if record.platform == .windows {
                Button("Windows Game Settings…") { openSettings() }
            }
            Divider()
            Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
            Button("Remove from Library") { model.registry.remove(record.id) }
                .help("Forget this game without deleting its files.")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Play, with a menu of the game's other play tasks.
private struct PlayButton: View {
    let record: InstalledGameRecord

    @Environment(AppModel.self) private var model
    @Environment(LaunchController.self) private var launcher

    private var tasks: [PlayTask] { record.info?.playTasks.filter { $0.kind == .file } ?? [] }

    private var links: [PlayTask] { record.info?.playTasks.filter { $0.kind == .url } ?? [] }

    var body: some View {
        let blocker = launcher.blocker(for: record)
        Group {
            if tasks.count > 1 || !links.isEmpty {
                Menu {
                    ForEach(tasks, id: \.index) { task in
                        Button(task.name ?? "Task \(task.index + 1)") { play(task.index) }
                    }
                    if !links.isEmpty {
                        Divider()
                        ForEach(links, id: \.index) { task in
                            if let link = task.link {
                                Link(task.name ?? link.host() ?? "Link", destination: link)
                            }
                        }
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                } primaryAction: {
                    play(nil)
                }
                .menuStyle(.button)
                .fixedSize()
            } else {
                Button {
                    play(nil)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(blocker != nil)
        .help(blocker?.presentable.message ?? "")
    }

    private func play(_ task: Int?) {
        Task {
            do {
                try await launcher.launch(record, task: task)
            } catch {
                model.present(error)
            }
        }
    }
}

/// Progress and controls for a game's job, inline on its page.
private struct JobControls: View {
    let job: DownloadJob

    @Environment(DownloadQueue.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(statusText)
                    .font(.headline)
                Spacer()
                switch job.state {
                case .running, .queued:
                    Button("Pause") { downloads.pause(job) }
                case .paused, .failed:
                    Button("Resume") { downloads.resume(job) }
                        .buttonStyle(.borderedProminent)
                case .finished:
                    EmptyView()
                }
                Button("Cancel", role: .destructive) { Task { await downloads.cancel(job) } }
            }
            if let fraction = job.progress.fraction {
                ProgressView(value: fraction)
            } else if job.isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if case .failed(let error) = job.state {
                Text(error.message)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .frame(maxWidth: 560)
    }

    private var statusText: String {
        switch job.state {
        case .queued: "\(job.verb) queued"
        case .running: "\(job.verb): \(job.progress.phaseText)"
        case .paused: "\(job.verb) paused"
        case .failed(let error): error.title
        case .finished: "\(job.verb) finished"
        }
    }
}

/// A file path that reveals itself in Finder, shortened in the middle to one line.
struct PathLink: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Text(url.path(percentEncoded: false))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.link)
        .help("Show in Finder")
    }
}

/// A titled block on the detail page.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InstallationSection: View {
    let record: InstalledGameRecord

    var body: some View {
        DetailSection("Installation") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                if let platform = record.platform {
                    row("Platform", platform.displayName)
                }
                if let version = record.version {
                    row("Version", version)
                }
                if let plan = record.installation?.plan {
                    row("Language", Language.match(plan.language)?.displayName ?? plan.language)
                    if let branch = plan.choices?.branch {
                        row("Branch", branch)
                    }
                    if !plan.files.isEmpty {
                        row("Size", plan.diskSize.formattedBytes)
                    }
                }
                GridRow {
                    Text("Location")
                        .foregroundStyle(.secondary)
                    PathLink(url: record.entry.folder)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct DLCSection: View {
    let details: ProductDetails

    @Environment(LibraryModel.self) private var library

    var body: some View {
        DetailSection("DLC") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(details.dlcs, id: \.id) { dlc in
                    HStack(spacing: 10) {
                        ArtworkImage(url: dlc.icon)
                            .frame(width: 32, height: 32)
                            .clipShape(.rect(cornerRadius: 6))
                        Text(dlc.title)
                        Spacer()
                        if library.ownedIDs.contains(dlc.id) {
                            Label("Owned", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Not owned")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: 560)
        }
    }
}

private struct BuildsSection: View {
    let id: String
    let platform: GamePlatform

    @Environment(AppModel.self) private var model
    @State private var builds: BuildList?
    @State private var failed = false

    var body: some View {
        DetailSection("Builds for \(platform.displayName)") {
            if let builds {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(builds.builds.prefix(8), id: \.id) { build in
                        HStack {
                            Text(build.version ?? "Build \(build.id)")
                                .monospacedDigit()
                            if let branch = build.branch {
                                Text(branch)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .background(.quaternary, in: .capsule)
                            }
                            Spacer()
                            if let published = build.published.flatMap(Self.date) {
                                Text(published, format: .dateTime.year().month().day())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if builds.hasPrivateBranches {
                        Text("Some builds are on password-protected branches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 560)
            } else if failed {
                Text("Builds couldn't be loaded.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: platform) {
            do {
                builds = try await model.client.buildList(id, platform: platform)
            } catch {
                failed = true
            }
        }
    }

    private static func date(_ text: String) -> Date? {
        // GOG writes offsets without a colon (+0000), which ISO8601DateFormatter accepts.
        ISO8601DateFormatter().date(from: text)
    }
}

private struct CloudSavesSection: View {
    let record: InstalledGameRecord

    @Environment(AppModel.self) private var model
    @Environment(CloudSaveModel.self) private var cloudSaves
    @State private var locations: [SaveLocation]?
    @State private var lookupError: PresentableError?
    @State private var confirmingDelete = false

    var body: some View {
        DetailSection("Cloud Saves") {
            VStack(alignment: .leading, spacing: 8) {
                if let lookupError {
                    Text("Cloud saves couldn't be checked. \(lookupError.message)")
                        .foregroundStyle(.secondary)
                } else if let locations {
                    if locations.isEmpty {
                        Text("This game doesn't use GOG cloud saves.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(locations, id: \.name) { location in
                            PathLink(url: location.url)
                        }
                        HStack {
                            if let date = cloudSaves.lastSynced(record.id) {
                                Text("Last synced \(date, format: .relative(presentation: .named))")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not synced yet")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if cloudSaves.isSyncing(record.id) {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button("Sync Now") {
                                Task {
                                    do {
                                        try await cloudSaves.sync(record)
                                    } catch {
                                        await model.handle(error, retry: nil)
                                    }
                                }
                            }
                            .disabled(cloudSaves.isSyncing(record.id))
                            Button("Delete Cloud Saves…", role: .destructive) { confirmingDelete = true }
                                .disabled(cloudSaves.isSyncing(record.id))
                        }
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
        .task(id: record.id) {
            do {
                locations = try await cloudSaves.loadLocations(for: record)
                lookupError = nil
            } catch {
                lookupError = presentableError(error)
            }
        }
        .confirmationDialog("Delete \(record.title)'s cloud saves?", isPresented: $confirmingDelete) {
            Button("Delete Cloud Saves", role: .destructive) {
                Task {
                    do {
                        try await cloudSaves.deleteCloudSaves(record)
                    } catch {
                        await model.handle(error, retry: nil)
                    }
                }
            }
        } message: {
            Text("Saves on this Mac stay, but every copy stored with GOG is deleted. This can't be undone.")
        }
    }
}

#Preview("Installed, update available") {
    NavigationStack {
        GameDetailView(id: PreviewData.witcherID)
    }
    .modelEnvironment(.preview())
    .frame(width: 900, height: 900)
}

#Preview("Not installed") {
    NavigationStack {
        GameDetailView(id: PreviewData.gwentID)
    }
    .modelEnvironment(.preview())
    .frame(width: 900, height: 700)
}

#Preview("Downloading") {
    NavigationStack {
        GameDetailView(id: PreviewData.tyrianID)
    }
    .modelEnvironment(.preview())
    .frame(width: 900, height: 600)
}
