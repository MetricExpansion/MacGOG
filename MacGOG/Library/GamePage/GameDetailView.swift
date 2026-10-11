import SwiftUI
import SwiftyGOG

/// A game's page: its art as a backdrop, a hero with the title and actions, and everything known
/// about the game in two columns (one on narrow windows).
struct GameDetailView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @Environment(InstallRegistry.self) private var registry
    @State private var details: ProductDetails?
    @State private var detailsError: PresentableError?
    @State private var sheet: InstallSheet.Request?
    @State private var viewer: MediaViewer.Request?
    @State private var scrollOffset: CGFloat = 0

    /// Windows at least this wide get a side column.
    private static let twoColumnWidth: CGFloat = 960

    private var item: LibraryItem? { model.libraryItems.first { $0.id == id } }

    private var galaxy: GalaxyGame? { library.galaxy[id] }

    private var title: String {
        details?.title ?? item?.title ?? registry.record(for: id)?.title ?? ""
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = min(max(proxy.size.height * 0.6, 380), 640)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GameHero(
                        id: id,
                        title: title,
                        details: details,
                        galaxy: galaxy,
                        tile: item?.imageURL,
                        height: heroHeight,
                        scrollOffset: scrollOffset,
                        sheet: $sheet
                    )
                    content(wide: proxy.size.width >= Self.twoColumnWidth)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .padding(.bottom, 48)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            .background {
                Backdrop(art: galaxy?.background, tile: item?.imageURL)
            }
        }
        // The page sits on dark art in both appearances.
        .environment(\.colorScheme, .dark)
        // The hero runs up under the toolbar and shows the title large, so the toolbar doesn't.
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(removing: .title)
        .navigationTitle(title)
        .task(id: id) {
            async let galaxy = library.galaxyGame(for: id)
            await loadDetails()
            _ = await galaxy
        }
        .sheet(item: $sheet) { request in
            InstallSheet(id: id, title: title, mode: request.mode, requestedBuild: request.build)
        }
        .sheet(item: $viewer) { request in
            MediaViewer(request: request)
        }
    }

    @ViewBuilder private func content(wide: Bool) -> some View {
        let record = registry.record(for: id)
        if wide {
            HStack(alignment: .top, spacing: 32) {
                mainColumn(record: record)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 16) {
                    statusCards(record: record)
                    infoCards
                }
                .frame(width: 340)
            }
        } else {
            // On narrow windows, what's installed comes first and the reference cards last.
            VStack(alignment: .leading, spacing: 32) {
                statusCards(record: record)
                mainColumn(record: record)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    infoCards
                }
            }
        }
    }

    private func mainColumn(record: InstalledGameRecord?) -> some View {
        VStack(alignment: .leading, spacing: 36) {
            if let detailsError {
                ErrorBanner(error: detailsError) { Task { await loadDetails() } }
            }
            if let galaxy, !(galaxy.screenshots.isEmpty && galaxy.artworks.isEmpty) {
                MediaGallery(images: galaxy.screenshots + galaxy.artworks) { index in
                    viewer = MediaViewer.Request(images: galaxy.screenshots + galaxy.artworks, index: index)
                }
            }
            if let text = (details?.fullDescription ?? details?.lead).map(HTMLText.plainText), !text.isEmpty {
                AboutSection(text: text)
            }
            if let details, !details.dlcs.isEmpty {
                DLCSection(details: details)
            }
            if let galaxy, !galaxy.videos.isEmpty {
                VideosSection(videos: galaxy.videos, art: galaxy.artworks + galaxy.screenshots)
            }
            if !buildPlatforms(record: record).isEmpty {
                BuildsSection(id: id, platforms: buildPlatforms(record: record), sheet: $sheet)
            }
            if let changelog = details?.changelog.map(HTMLText.plainText), !changelog.isEmpty {
                ChangelogSection(text: changelog)
            }
        }
    }

    /// What's installed, or what installing costs.
    @ViewBuilder private func statusCards(record: InstalledGameRecord?) -> some View {
        if let record {
            InstallationCard(record: record)
            if record.platform == .windows, model.launcher.windowsRunner == .crossOver {
                CrossOverCard(record: record)
            }
            if record.installation != nil {
                CloudSavesCard(record: record)
            }
        } else if let details, !details.installerSizes.isEmpty {
            DownloadSizeCard(details: details)
        }
    }

    /// Reference facts about the game.
    @ViewBuilder private var infoCards: some View {
        FactsCard(details: details, galaxy: galaxy)
        if let details, !details.extras.isEmpty {
            ExtrasCard(extras: details.extras)
        }
        if let links = details?.links {
            LinksCard(links: links)
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

/// The game's art, heavily blurred and darkened, filling the window behind the whole page so the
/// art carries past the hero.
private struct Backdrop: View {
    let art: URL?
    let tile: URL?

    var body: some View {
        ZStack {
            Color.black
            ArtworkImage(url: art ?? tile, placeholder: AnyShapeStyle(.clear), showsPlaceholderIcon: false)
                .blur(radius: 90, opaque: true)
                .saturation(1.4)
                .opacity(0.9)
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .backgroundExtensionEffect()
    }
}

/// The sharp art with the title, pitch, facts, and actions over it. The art scrolls slower than
/// the page and stretches when pulled down, and its lower part dissolves into the backdrop.
private struct GameHero: View {
    let id: String
    let title: String
    let details: ProductDetails?
    let galaxy: GalaxyGame?
    let tile: URL?
    let height: CGFloat
    let scrollOffset: CGFloat
    @Binding var sheet: InstallSheet.Request?

    var body: some View {
        let pull = max(0, -scrollOffset)
        Color.clear
            .frame(height: height)
            .background(alignment: .top) {
                art
                    .frame(height: height + pull)
                    .offset(y: scrollOffset > 0 ? scrollOffset * 0.5 : -pull)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.55),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay(alignment: .bottomLeading) {
                titleBlock
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
    }

    private var art: some View {
        ZStack {
            if galaxy?.background == nil {
                // Until Galaxy's art arrives, or when there is none, the library tile stands in.
                ArtworkImage(url: tile, placeholder: AnyShapeStyle(.clear), showsPlaceholderIcon: false)
                    .blur(radius: 30, opaque: true)
                    .saturation(1.3)
            }
            ArtworkImage(
                url: galaxy?.background,
                placeholder: AnyShapeStyle(.clear),
                showsPlaceholderIcon: false
            )
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if details?.isInDevelopment == true {
                Text("EARLY ACCESS")
                    .font(.caption.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(.orange)
            }
            Text(title)
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 3)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let summary = galaxy?.summary {
                Text(summary)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: 680, alignment: .leading)
                    .shadow(color: .black.opacity(0.5), radius: 8)
            }
            chips
            GameActions(id: id, sheet: $sheet)
                .padding(.top, 6)
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if let rating = galaxy?.rating {
                Chip {
                    Label("\(Int(rating.rounded()))", systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                }
                .help("GOG's aggregated rating, out of 100")
            }
            if let year = (galaxy?.releaseDate).map({ $0.formatted(.dateTime.year()) })
                ?? details?.releaseDate.map({ String($0.prefix(4)) })
            {
                Chip { Text(year) }
            }
            ForEach((galaxy?.genres ?? []).prefix(3), id: \.self) { genre in
                Chip { Text(genre) }
            }
            ForEach(details?.platforms ?? [], id: \.self) { platform in
                Chip { Image(systemName: platform.symbolName) }
                    .help(platform.displayName)
            }
        }
    }
}

/// A small glass capsule for a fact over the art.
struct Chip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}

#if DEBUG
    #Preview("Installed, update available") {
        NavigationStack {
            GameDetailView(id: PreviewData.witcherID)
        }
        .modelEnvironment(.preview())
        .frame(width: 1200, height: 900)
    }

    #Preview("Not installed, narrow") {
        NavigationStack {
            GameDetailView(id: PreviewData.gwentID)
        }
        .modelEnvironment(.preview())
        .frame(width: 760, height: 800)
    }

    #Preview("Downloading") {
        NavigationStack {
            GameDetailView(id: PreviewData.tyrianID)
        }
        .modelEnvironment(.preview())
        .frame(width: 1100, height: 700)
    }
#endif
