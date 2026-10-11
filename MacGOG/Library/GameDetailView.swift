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
    @State private var sheet: InstallSheet.Request?

    private var item: LibraryItem? { model.libraryItems.first { $0.id == id } }

    var body: some View {
        let record = registry.record(for: id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GameHeader(
                    id: id,
                    title: details?.title ?? item?.title ?? record?.title ?? "",
                    details: details,
                    tile: item?.imageURL
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
                    if !buildPlatforms(record: record).isEmpty {
                        BuildsSection(id: id, platforms: buildPlatforms(record: record), sheet: $sheet)
                    }
                }
                .padding(24)
            }
        }
        // The hero art runs up under the toolbar and shows the title large, so the toolbar doesn't.
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(removing: .title)
        .navigationTitle(details?.title ?? item?.title ?? record?.title ?? "")
        .task(id: id) { await loadDetails() }
        .sheet(item: $sheet) { request in
            InstallSheet(
                id: id,
                title: details?.title ?? item?.title ?? record?.title ?? "",
                mode: request.mode,
                requestedBuild: request.build
            )
        }
    }

    /// Platforms whose builds can be listed: the installed one, or every non-Linux platform the
    /// game ships on, macOS first. Linux games ship installers, which have no build list.
    private func buildPlatforms(record: InstalledGameRecord?) -> [GamePlatform] {
        if let platform = record?.platform {
            return platform == .linux ? [] : [platform]
        }
        let listed = details?.platforms ?? item?.platforms ?? []
        return [GamePlatform.osx, .windows].filter(listed.contains)
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

/// Galaxy's hero art behind the title, extending under the toolbar and sidebar.
private struct GameHeader: View {
    let id: String
    let title: String
    let details: ProductDetails?
    /// The library tile, blurred, fills the header until the hero art arrives, or when there is none.
    let tile: URL?

    @Environment(LibraryModel.self) private var library

    static let height: CGFloat = 340

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                ArtworkImage(url: tile, placeholder: AnyShapeStyle(.black), showsPlaceholderIcon: false)
                    .blur(radius: 40, opaque: true)
                    .saturation(1.3)
                ArtworkImage(
                    url: library.artwork[id]?.background,
                    placeholder: AnyShapeStyle(.clear),
                    showsPlaceholderIcon: false
                )
                // Some of Galaxy's hero images end in a thin light band; draw past the bottom edge
                // so it's clipped off.
                .frame(height: Self.height + 16)
                .frame(height: Self.height, alignment: .top)
            }
            .backgroundExtensionEffect()
            // Shade only behind the title, keeping the art's colour elsewhere.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.7), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            titleBlock
                .padding(24)
                // The title sits on dark art in both appearances, so its glass should be dark too.
                .environment(\.colorScheme, .dark)
        }
        .frame(height: Self.height)
        .clipped()
        .task(id: id) { _ = await library.artwork(for: id) }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            HStack(spacing: 8) {
                ForEach(details?.platforms ?? [], id: \.self) { platform in
                    chip(Label(platform.displayName, systemImage: platform.symbolName))
                }
                if let year = details?.releaseDate?.prefix(4) {
                    chip(Text(year))
                }
            }
        }
    }

    private func chip(_ content: some View) -> some View {
        content
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
    }
}

/// The main buttons for a game, which depend on its installation status.
private struct GameActions: View {
    let id: String
    @Binding var sheet: InstallSheet.Request?

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
                Button("Install…") { sheet = InstallSheet.Request(mode: .install) }
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
                    Button("Verify with GOG…") { sheet = InstallSheet.Request(mode: .adopt(record)) }
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
                    Button("Reinstall…") { sheet = InstallSheet.Request(mode: .adopt(record)) }
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
                Button("Change Version, Language, or DLC…") {
                    sheet = InstallSheet.Request(mode: .modify(record))
                }
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

/// Every build GOG offers for a platform, with buttons to install, update to, or downgrade to one.
private struct BuildsSection: View {
    let id: String
    /// The platforms to choose between; the first is shown first.
    let platforms: [GamePlatform]
    @Binding var sheet: InstallSheet.Request?

    @Environment(AppModel.self) private var model
    @Environment(InstallRegistry.self) private var registry
    @Environment(DownloadQueue.self) private var downloads
    @State private var platform: GamePlatform?
    @State private var builds: BuildList?
    @State private var failed = false
    @State private var showsAll = false

    /// Builds shown before "Show All".
    private static let shortListLength = 8

    private var shownPlatform: GamePlatform { platform ?? platforms.first ?? .osx }

    private var record: InstalledGameRecord? { registry.record(for: id) }

    /// The installed build, when it's for the shown platform.
    private var installedBuildID: String? {
        guard let plan = record?.installation?.plan, plan.platform == shownPlatform else { return nil }
        return plan.buildID
    }

    var body: some View {
        DetailSection("Builds") {
            VStack(alignment: .leading, spacing: 8) {
                if platforms.count > 1 {
                    Picker("Platform", selection: Binding(get: { shownPlatform }, set: { platform = $0 })) {
                        ForEach(platforms, id: \.self) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if let builds {
                    list(builds)
                } else if failed {
                    Text("Builds couldn't be loaded.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
        .task(id: shownPlatform) {
            builds = nil
            failed = false
            do {
                builds = try await model.client.buildList(id, platform: shownPlatform)
            } catch {
                failed = true
            }
        }
    }

    private func list(_ builds: BuildList) -> some View {
        let shown = showsAll ? builds.builds : Array(builds.builds.prefix(Self.shortListLength))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown, id: \.id) { build in
                row(build, in: builds)
            }
            if builds.builds.count > Self.shortListLength {
                Button(showsAll ? "Show Fewer" : "Show All \(builds.builds.count) Builds") {
                    showsAll.toggle()
                }
                .buttonStyle(.link)
            }
            if builds.hasPrivateBranches {
                Text("Some builds are on password-protected branches. Enter the password when installing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ build: GameBuild, in list: BuildList) -> some View {
        HStack {
            Text(build.version ?? "Build \(build.id)")
                .monospacedDigit()
            if let branch = build.branch {
                badge(branch)
            }
            if build.generation == 1 {
                badge("legacy")
            }
            if build.id == installedBuildID {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            if let published = build.publishedDate {
                Text(published, format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary)
            }
            if build.id != installedBuildID, let request = request(for: build) {
                Button(actionTitle(for: build, in: list)) { sheet = request }
                    .disabled(downloads.job(for: id)?.isActive == true)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .background(.quaternary, in: .capsule)
    }

    /// "Update…" or "Downgrade…" relative to the installed build, else "Install…".
    private func actionTitle(for build: GameBuild, in list: BuildList) -> String {
        switch installedBuildID.flatMap({ list.isBuild(build.id, olderThan: $0) }) {
        case true?: "Downgrade…"
        case false?: "Update…"
        case nil: "Install…"
        }
    }

    /// The sheet that installs `build`, or `nil` when it can't be installed from here, such as for
    /// a missing folder or another platform than the installed one.
    private func request(for build: GameBuild) -> InstallSheet.Request? {
        let wanted = InstallSheet.BuildRequest(platform: shownPlatform, id: build.id)
        guard let record else {
            return InstallSheet.Request(mode: .install, build: wanted)
        }
        switch record.status {
        case .ready where record.platform == shownPlatform:
            return InstallSheet.Request(mode: .modify(record), build: wanted)
        case .foreign, .needsRepair:
            return InstallSheet.Request(mode: .adopt(record), build: wanted)
        case .ready, .missing:
            return nil
        }
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

#if DEBUG
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
#endif
