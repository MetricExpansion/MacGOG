import Foundation
import Observation
import SwiftyGOG

/// Syncs installed games' cloud saves and remembers when each save location was last synced.
@MainActor @Observable final class CloudSaveModel {
    /// A conflict waiting for the user to choose which side to keep.
    struct Conflict: Identifiable {
        let id = UUID()
        let title: String
        let location: String
        fileprivate let resolve: (SavePreference?) -> Void
    }

    nonisolated struct LocationState: Codable, Sendable {
        /// Seconds since 1970, as `CloudSaves.sync(since:)` takes it.
        var since: Double
        var lastSynced: Date?
    }

    /// Sync state per product ID, then per save location name.
    private(set) var state: [String: [String: LocationState]] = [:]
    private(set) var syncing: Set<String> = []
    /// Save locations found per product ID.
    private(set) var locations: [String: [SaveLocation]] = [:]
    var pendingConflict: Conflict?

    @ObservationIgnored private let saves: CloudSaves
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let file: StateFile<[String: [String: LocationState]]>

    init(client: GOGClient, settings: AppSettings, file: URL) {
        saves = CloudSaves(client: client)
        self.settings = settings
        self.file = StateFile(url: file)
        state = (try? self.file.load()) ?? [:]
    }

    func isSyncing(_ productID: String) -> Bool { syncing.contains(productID) }

    func lastSynced(_ productID: String) -> Date? {
        state[productID]?.values.compactMap(\.lastSynced).max()
    }

    /// Where a game keeps the saves GOG syncs; empty when it has none.
    func loadLocations(for record: InstalledGameRecord) async throws -> [SaveLocation] {
        if let known = locations[record.id] {
            return known
        }
        guard let platform = record.platform else { return [] }
        let found = try await saves.locations(
            id: record.id,
            platform: platform,
            installation: record.entry.folder,
            winePrefix: settings.winePrefix(for: record.id)
        )
        locations[record.id] = found
        return found
    }

    /// Syncs every save location of a game. A dry run picks the direction first; a conflict asks the
    /// user, unless `preference` already forces a side.
    func sync(_ record: InstalledGameRecord, preference: SavePreference = .automatic) async throws {
        guard let platform = record.platform, !isSyncing(record.id) else { return }
        syncing.insert(record.id)
        defer { syncing.remove(record.id) }
        for location in try await loadLocations(for: record) {
            let since = state[record.id]?[location.name]?.since ?? 0
            var chosen = preference
            let preview = try await saves.sync(
                id: record.id,
                platform: platform,
                root: location.url,
                name: location.name,
                since: since,
                preference: chosen,
                dryRun: true
            )
            if preview.direction == .conflict {
                guard let choice = await askToResolve(record: record, location: location.name) else {
                    continue
                }
                chosen = choice
            }
            let applied = try await saves.sync(
                id: record.id,
                platform: platform,
                root: location.url,
                name: location.name,
                since: since,
                preference: chosen,
                dryRun: false
            )
            var entry = state[record.id]?[location.name] ?? LocationState(since: since)
            if applied.direction != .none {
                entry.since = Date().timeIntervalSince1970
            }
            entry.lastSynced = .now
            state[record.id, default: [:]][location.name] = entry
            persist()
        }
    }

    /// Deletes every cloud save of a game.
    func deleteCloudSaves(_ record: InstalledGameRecord) async throws {
        guard let platform = record.platform else { return }
        for location in try await loadLocations(for: record) {
            try await saves.clear(id: record.id, platform: platform, name: location.name)
        }
        state[record.id] = nil
        persist()
    }

    func resolve(_ conflict: Conflict, with preference: SavePreference?) {
        pendingConflict = nil
        conflict.resolve(preference)
    }

    private func askToResolve(record: InstalledGameRecord, location: String) async -> SavePreference? {
        await withCheckedContinuation { continuation in
            pendingConflict = Conflict(title: record.title, location: location) { choice in
                continuation.resume(returning: choice)
            }
        }
    }

    private func persist() {
        try? file.save(state)
    }
}
