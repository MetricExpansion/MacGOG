import Foundation
import Observation
import SwiftyGOG

/// The games the account owns, cached on disk so the library shows up before the network answers.
@MainActor @Observable final class LibraryModel {
    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(PresentableError)
    }

    private(set) var games: [OwnedGame] = []
    /// Every owned product ID, including DLC.
    private(set) var ownedIDs: Set<String> = []
    private(set) var state = LoadState.idle

    @ObservationIgnored private let client: GOGClient
    @ObservationIgnored private let cache: StateFile<[OwnedGame]>

    init(client: GOGClient, cache: URL) {
        self.client = client
        self.cache = StateFile(url: cache)
    }

    var isLoading: Bool {
        if case .loading = state { true } else { false }
    }

    func game(_ id: String) -> OwnedGame? {
        games.first { $0.id == id }
    }

    /// Store details fetched so far, by product ID.
    private(set) var details: [String: ProductDetails] = [:]
    @ObservationIgnored private var detailTasks: [String: Task<ProductDetails, any Error>] = [:]

    /// Store details for a product, fetched once and shared by every caller.
    func details(for id: String) async throws -> ProductDetails {
        if let cached = details[id] {
            return cached
        }
        let task = detailTasks[id] ?? Task { [client] in try await client.productDetails(id) }
        detailTasks[id] = task
        do {
            let fetched = try await task.value
            details[id] = fetched
            detailTasks[id] = nil
            return fetched
        } catch {
            detailTasks[id] = nil
            throw error
        }
    }

    /// Galaxy artwork fetched so far, by product ID.
    private(set) var artwork: [String: GameArtwork] = [:]
    @ObservationIgnored private var artworkTasks: [String: Task<GameArtwork, any Error>] = [:]

    /// Galaxy's hero art and covers for a product, fetched once. Artwork is decoration, so a failure
    /// returns `nil` and is retried next time.
    func artwork(for id: String) async -> GameArtwork? {
        if let cached = artwork[id] {
            return cached
        }
        let task = artworkTasks[id] ?? Task { [client] in try await client.artwork(id) }
        artworkTasks[id] = task
        defer { artworkTasks[id] = nil }
        guard let fetched = try? await task.value else { return nil }
        artwork[id] = fetched
        return fetched
    }

    /// Owned DLC of a product, in GOG's order.
    func ownedDLCs(of details: ProductDetails) -> [ProductDLC] {
        details.dlcs.filter { ownedIDs.contains($0.id) }
    }

    func loadCached() {
        if games.isEmpty, let cached = try? cache.load() {
            games = cached
        }
    }

    /// Fetches the library. Errors are kept in `state`; the caller decides whether one ends the session.
    @discardableResult
    func refresh() async -> (any Error)? {
        guard !isLoading else { return nil }
        state = .loading
        do {
            async let owned = client.ownedGames()
            let fetched = try await client.searchLibrary(nil)
            ownedIDs = Set(try await owned)
            games = fetched.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            state = .loaded
            try? cache.save(games)
            return nil
        } catch {
            state = presentableError(error).map(LoadState.failed) ?? .idle
            return error
        }
    }

    #if DEBUG
        /// Seeds the library for previews and tests.
        func preload(games: [OwnedGame], ownedIDs: Set<String> = []) {
            self.games = games
            self.ownedIDs = ownedIDs.union(games.map(\.id))
            state = .loaded
        }
    #endif

    /// Forgets account data after sign-out.
    func clear() {
        games = []
        ownedIDs = []
        state = .idle
        try? FileManager.default.removeItem(at: cache.url)
    }
}
