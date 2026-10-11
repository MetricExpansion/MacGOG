import SwiftUI
import SwiftyGOG

// MARK: Building blocks

/// A titled block in the page's main column.
struct PageSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.bold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A glass card in the page's side column.
struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        symbol = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// Label and value rows that line up, for facts.
private struct FactGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            content
        }
    }
}

private struct FactRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension FactRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.init(label) { Text(value) }
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

// MARK: Side column

/// Where and what is installed.
struct InstallationCard: View {
    let record: InstalledGameRecord

    var body: some View {
        Card("Installed", systemImage: "internaldrive") {
            FactGrid {
                if let platform = record.platform {
                    FactRow("Platform", platform.displayName)
                }
                if let version = record.version {
                    FactRow("Version", version)
                }
                if let plan = record.installation?.plan {
                    FactRow("Language", Language.match(plan.language)?.name ?? plan.language)
                    if let branch = plan.choices?.branch {
                        FactRow("Branch", branch)
                    }
                    if !plan.files.isEmpty {
                        FactRow("Size", plan.diskSize.formattedBytes)
                    }
                }
                FactRow("Location") { PathLink(url: record.entry.folder) }
            }
        }
    }
}

/// Roughly what a download costs, before there's a plan.
struct DownloadSizeCard: View {
    let details: ProductDetails

    var body: some View {
        Card("Download Size", systemImage: "arrow.down.circle") {
            FactGrid {
                ForEach(GamePlatform.allCases.filter { details.installerSizes[$0] != nil }, id: \.self) {
                    platform in
                    FactRow(
                        platform.displayName,
                        "About \(details.installerSizes[platform]?.formattedBytes ?? "")"
                    )
                }
            }
            Text("The exact size depends on the language and DLC you choose.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Credits, categories, and other facts about the game.
struct FactsCard: View {
    let details: ProductDetails?
    let galaxy: GalaxyGame?

    @State private var showsLanguages = false

    var body: some View {
        Card("Details", systemImage: "info.circle") {
            FactGrid {
                if let developers = list(galaxy?.developers) {
                    FactRow("Developer", developers)
                }
                if let publishers = list(galaxy?.publishers), publishers != list(galaxy?.developers) {
                    FactRow("Publisher", publishers)
                }
                if let date = galaxy?.releaseDate {
                    FactRow("Released", date.formatted(date: .long, time: .omitted))
                }
                if let series = galaxy?.series {
                    FactRow("Series", series)
                }
                if let genres = list(galaxy?.genres) {
                    FactRow("Genres", genres)
                }
                if let themes = list(galaxy?.themes) {
                    FactRow("Themes", themes)
                }
                if let modes = list(galaxy?.gameModes) {
                    FactRow("Modes", modes)
                }
                if let rating = galaxy?.rating {
                    FactRow("Rating") {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text("\(Int(rating.rounded())) / 100")
                        }
                    }
                }
                if let details {
                    if !details.platforms.isEmpty {
                        FactRow("Platforms", details.platforms.map(\.displayName).joined(separator: ", "))
                    }
                    if !details.supportedLanguages.isEmpty {
                        FactRow("Languages") {
                            Button(
                                details.supportedLanguages.count == 1
                                    ? details.supportedLanguages[0]
                                    : "\(details.supportedLanguages.count) languages"
                            ) {
                                showsLanguages = true
                            }
                            .buttonStyle(.link)
                            .popover(isPresented: $showsLanguages) {
                                Text(details.supportedLanguages.joined(separator: "\n"))
                                    .padding()
                                    .frame(minWidth: 180, alignment: .leading)
                            }
                        }
                    }
                }
            }
            if details == nil && galaxy == nil {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func list(_ names: [String]?) -> String? {
        guard let names, !names.isEmpty else { return nil }
        return names.formatted(.list(type: .and))
    }
}

/// Manuals, soundtracks, artbooks, and other goodies that come with the game.
struct ExtrasCard: View {
    let extras: [ProductExtra]

    var body: some View {
        Card("Goodies", systemImage: "gift") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(extras, id: \.self) { extra in
                    HStack(spacing: 10) {
                        Image(systemName: Self.symbol(for: extra.kind))
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text(extra.name.capitalized(with: .current))
                            .lineLimit(1)
                        Spacer()
                        if extra.size > 0 {
                            Text(extra.size.formattedBytes)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Link(
                "Download from your GOG library",
                destination: URL(string: "https://www.gog.com/account")!
            )
            .font(.callout)
        }
    }

    static func symbol(for kind: String) -> String {
        switch kind {
        case "manuals": "book.closed"
        case "audio": "music.note"
        case "video": "film"
        case "artworks", "wallpapers": "photo"
        case "avatars": "person.crop.square"
        case "game add-ons", "game_add_ons": "puzzlepiece.extension"
        case "guides and reference": "map"
        default: "doc"
        }
    }
}

/// The game's pages on gog.com.
struct LinksCard: View {
    let links: ProductLinks

    var body: some View {
        if links.store != nil || links.support != nil || links.forum != nil {
            Card("On GOG", systemImage: "globe") {
                VStack(alignment: .leading, spacing: 8) {
                    if let store = links.store {
                        Link(destination: store) { Label("Store Page", systemImage: "bag") }
                    }
                    if let forum = links.forum {
                        Link(destination: forum) {
                            Label("Forum", systemImage: "bubble.left.and.bubble.right")
                        }
                    }
                    if let support = links.support {
                        Link(destination: support) { Label("Support", systemImage: "lifepreserver") }
                    }
                }
            }
        }
    }
}

/// Where the game's cloud saves live, and syncing them.
struct CloudSavesCard: View {
    let record: InstalledGameRecord

    @Environment(AppModel.self) private var model
    @Environment(CloudSaveModel.self) private var cloudSaves
    @State private var locations: [SaveLocation]?
    @State private var lookupError: PresentableError?
    @State private var confirmingDelete = false

    var body: some View {
        Card("Cloud Saves", systemImage: "icloud") {
            if let lookupError {
                Text("Cloud saves couldn't be checked. \(lookupError.message)")
                    .foregroundStyle(.secondary)
            } else if let locations {
                if locations.isEmpty {
                    Text(
                        "This game doesn't use GOG cloud saves on \(record.platform?.displayName ?? "this platform")."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(locations, id: \.name) { location in
                        PathLink(url: location.url)
                    }
                    Group {
                        if let date = cloudSaves.lastSynced(record.id) {
                            Text("Last synced \(date, format: .relative(presentation: .named))")
                        } else {
                            Text("Not synced yet")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    HStack {
                        Button("Sync Now") {
                            Task {
                                do {
                                    try await cloudSaves.sync(record)
                                } catch {
                                    await model.handle(error, retry: nil)
                                }
                            }
                        }
                        .buttonStyle(.glass)
                        if cloudSaves.isSyncing(record.id) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Spacer()
                        Button("Delete…", role: .destructive) { confirmingDelete = true }
                            .buttonStyle(.glass)
                            .help("Delete the cloud copies of these saves")
                    }
                    .disabled(cloudSaves.isSyncing(record.id))
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
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

// MARK: Main column

/// Whether text is long enough to fold: more than about `lines` lines in the page's column.
private func isLong(_ text: String, lines: Int) -> Bool {
    text.count > lines * 90 || text.split(separator: "\n", omittingEmptySubsequences: false).count > lines
}

/// The store description, folded to a few paragraphs until expanded.
struct AboutSection: View {
    let text: String

    @State private var expanded = false

    var body: some View {
        PageSection("About") {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.body)
                    .lineSpacing(3)
                    .lineLimit(expanded ? nil : 9)
                    .textSelection(.enabled)
                    .frame(maxWidth: 820, alignment: .leading)
                if isLong(text, lines: 9) {
                    Button(expanded ? "Show Less" : "Show More") {
                        withAnimation(.snappy) { expanded.toggle() }
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

/// DLC as cards, marking which the account owns.
struct DLCSection: View {
    let details: ProductDetails

    @Environment(LibraryModel.self) private var library

    var body: some View {
        PageSection("DLC") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(details.dlcs, id: \.id) { dlc in
                    HStack(spacing: 12) {
                        ArtworkImage(url: dlc.icon, placeholder: AnyShapeStyle(.white.opacity(0.08)))
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dlc.title)
                                .lineLimit(2)
                            if library.ownedIDs.contains(dlc.id) {
                                Label("Owned", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Not owned")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                }
            }
        }
    }
}

/// Trailers and diaries, which open on their video site. The cards use the game's own art, so
/// browsing the page doesn't contact the video site.
struct VideosSection: View {
    let videos: [GalaxyVideo]
    let art: [GalaxyImage]

    var body: some View {
        PageSection("Videos") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(Array(videos.prefix(8).enumerated()), id: \.offset) { index, video in
                    if let url = video.url {
                        Link(destination: url) { card(video, index: index) }
                            .buttonStyle(.plain)
                            .help("Watch on YouTube")
                            .accessibilityLabel("Watch \(video.name ?? "video") on YouTube")
                    }
                }
            }
        }
    }

    private func card(_ video: GalaxyVideo, index: Int) -> some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ArtworkImage(
                    url: art.isEmpty ? nil : art[index % art.count].thumbnail,
                    placeholder: AnyShapeStyle(.white.opacity(0.08)),
                    showsPlaceholderIcon: false
                )
            }
            .overlay(Color.black.opacity(0.35))
            .overlay {
                Image(systemName: "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: .circle)
            }
            .overlay(alignment: .bottomLeading) {
                Text(video.name ?? "Video")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(radius: 4)
                    .padding(12)
            }
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// Release notes, folded until expanded.
struct ChangelogSection: View {
    let text: String

    @State private var expanded = false

    var body: some View {
        PageSection("What's New") {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 6)
                    .textSelection(.enabled)
                    .frame(maxWidth: 820, alignment: .leading)
                if isLong(text, lines: 6) {
                    Button(expanded ? "Show Less" : "Show Full Changelog") {
                        withAnimation(.snappy) { expanded.toggle() }
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

/// Every build GOG offers for a platform, with buttons to install, update to, or downgrade to one.
struct BuildsSection: View {
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
    private static let shortListLength = 6

    private var shownPlatform: GamePlatform { platform ?? platforms.first ?? .osx }

    private var record: InstalledGameRecord? { registry.record(for: id) }

    /// The installed build, when it's for the shown platform.
    private var installedBuildID: String? {
        guard let plan = record?.installation?.plan, plan.platform == shownPlatform else { return nil }
        return plan.buildID
    }

    var body: some View {
        PageSection("Builds") {
            VStack(alignment: .leading, spacing: 12) {
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
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, build in
                if index > 0 {
                    Divider()
                }
                row(build, in: builds)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            if builds.builds.count > Self.shortListLength || builds.hasPrivateBranches {
                Divider()
                HStack {
                    if builds.builds.count > Self.shortListLength {
                        Button(showsAll ? "Show Fewer" : "Show All \(builds.builds.count) Builds") {
                            withAnimation(.snappy) { showsAll.toggle() }
                        }
                        .buttonStyle(.link)
                    }
                    Spacer()
                    if builds.hasPrivateBranches {
                        Text("Some builds are on password-protected branches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func row(_ build: GameBuild, in list: BuildList) -> some View {
        HStack(spacing: 10) {
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
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(downloads.job(for: id)?.isActive == true)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.white.opacity(0.12), in: .capsule)
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
