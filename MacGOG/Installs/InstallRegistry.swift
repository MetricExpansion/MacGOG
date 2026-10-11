import Foundation
import Observation
import SwiftyGOG

/// A folder the app knows holds a game. The `.gogdl` manifest inside it stays the source of truth.
nonisolated struct RegistryEntry: Codable, Hashable, Sendable {
    var productID: String
    var path: String
    var title: String

    var folder: URL { URL(filePath: path, directoryHint: .isDirectory) }
}

/// What the app found in a registered folder.
nonisolated struct InstalledGameRecord: Sendable, Identifiable {
    enum Status: Sendable {
        /// Installed by SwiftyGOG, `gogdl`, or this app.
        case ready(Installation)
        /// Installed by Galaxy or another tool; it can be adopted by verifying it.
        case foreign(InstalledGame)
        case missing
        /// The folder exists but its install manifest can't be read.
        case needsRepair
    }

    let entry: RegistryEntry
    let status: Status
    /// GOG's own metadata (title, play tasks), when it's readable.
    let info: InstalledGame?

    var id: String { entry.productID }

    var installation: Installation? {
        if case .ready(let installation) = status { installation } else { nil }
    }

    var platform: GamePlatform? {
        installation?.plan.platform ?? info?.platform
    }

    var version: String? {
        installation?.plan.version ?? info?.versionName
    }

    var title: String { info?.title ?? entry.title }
}

/// The games installed on this Mac, persisted in `installations.json`.
@MainActor @Observable final class InstallRegistry {
    private(set) var records: [String: InstalledGameRecord] = [:]
    /// Newer builds found by the last update check, by product ID.
    private(set) var updates: [String: AvailableUpdate] = [:]
    private(set) var isCheckingForUpdates = false
    private(set) var lastUpdateCheck: Date?

    @ObservationIgnored private let file: StateFile<[RegistryEntry]>
    @ObservationIgnored private var entries: [RegistryEntry] = []

    init(file: URL) {
        self.file = StateFile(url: file)
    }

    var installedIDs: Set<String> { Set(records.keys) }

    func record(for productID: String) -> InstalledGameRecord? { records[productID] }

    /// Reads the registry and inspects every folder in it.
    func load() async {
        entries = (try? file.load()) ?? []
        var loaded: [String: InstalledGameRecord] = [:]
        for entry in entries {
            loaded[entry.productID] = await Self.inspect(entry)
        }
        records = loaded
    }

    /// Adds or replaces the game at `folder`, then inspects it.
    func register(productID: String, folder: URL, title: String) async {
        let entry = RegistryEntry(productID: productID, path: folder.standardizedFileURL.path, title: title)
        entries.removeAll { $0.productID == productID }
        entries.append(entry)
        persist()
        records[productID] = await Self.inspect(entry)
    }

    /// Re-reads one game's folder, such as after an install or repair.
    func refresh(_ productID: String) async {
        guard let entry = entries.first(where: { $0.productID == productID }) else { return }
        records[productID] = await Self.inspect(entry)
    }

    /// Forgets a game. Its files are left alone.
    func remove(_ productID: String) {
        entries.removeAll { $0.productID == productID }
        records[productID] = nil
        updates[productID] = nil
        persist()
    }

    func clearUpdate(for productID: String) {
        updates[productID] = nil
    }

    /// Checks every ready installation for a newer build, four at a time. Returns the first error
    /// that needs the user's attention, such as an ended session.
    @discardableResult
    func checkForUpdates(client: GOGClient) async -> (any Error)? {
        guard !isCheckingForUpdates else { return nil }
        isCheckingForUpdates = true
        defer {
            isCheckingForUpdates = false
            lastUpdateCheck = .now
        }
        let installations = records.values.compactMap(\.installation)
        var found: [String: AvailableUpdate] = [:]
        var failure: (any Error)?
        await withTaskGroup(of: (String, Result<AvailableUpdate?, any Error>).self) { group in
            var pending = installations[...]
            func addNext() {
                guard let installation = pending.popFirst() else { return }
                group.addTask {
                    do {
                        return (
                            installation.plan.product,
                            .success(try await installation.availableUpdate(client: client))
                        )
                    } catch {
                        return (installation.plan.product, .failure(error))
                    }
                }
            }
            for _ in 0..<4 {
                addNext()
            }
            for await (id, result) in group {
                switch result {
                case .success(let update):
                    found[id] = update
                case .failure(let error):
                    // An ended session matters more than one game's failure.
                    if failure == nil || requiresSignIn(error) {
                        failure = error
                    }
                }
                addNext()
            }
        }
        updates = found
        return failure
    }

    #if DEBUG
        /// Seeds records for previews and tests, without touching disk.
        func preload(_ records: [InstalledGameRecord], updates: [String: AvailableUpdate] = [:]) {
            entries = records.map(\.entry)
            self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            self.updates = updates
        }
    #endif

    private func persist() {
        try? file.save(entries)
    }

    /// Classifies a registered folder. Reading a manifest can take a while for big games.
    @concurrent
    nonisolated static func inspect(_ entry: RegistryEntry) async -> InstalledGameRecord {
        let folder = entry.folder
        let info = try? InstalledGame.read(at: folder)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return InstalledGameRecord(entry: entry, status: .missing, info: nil)
        }
        if let installation = try? Installation(at: folder) {
            return InstalledGameRecord(entry: entry, status: .ready(installation), info: info)
        }
        let manifest = folder.appending(path: ".gogdl/manifest.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            return InstalledGameRecord(entry: entry, status: .needsRepair, info: info)
        }
        if let info {
            return InstalledGameRecord(entry: entry, status: .foreign(info), info: info)
        }
        return InstalledGameRecord(entry: entry, status: .needsRepair, info: nil)
    }

    /// What a folder the user picked holds: an installation this app can manage, or a game another
    /// tool installed.
    enum FolderContents: Sendable {
        case installation(Installation, InstalledGame?)
        case foreign(InstalledGame)
    }

    @concurrent
    nonisolated static func inspectFolder(_ folder: URL) async throws -> FolderContents {
        if let installation = try? Installation(at: folder) {
            return .installation(installation, try? InstalledGame.read(at: folder))
        }
        return .foreign(try InstalledGame.read(at: folder))
    }
}
